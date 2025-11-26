#!/bin/bash
# SSH Whitelist Firewall Setup Script
# Sets up port-knock style security: SSH open to all, other ports blocked until login
#
# How it works:
# 1. SSH (port 22) is open to everyone
# 2. All other ports are blocked by default
# 3. On successful SSH login, full port access is granted to that IP
# 4. On SSH logout, full access is revoked (SSH-only again)

set -e

echo "========================================"
echo "SSH Whitelist Firewall Setup"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run as root"
    exit 1
fi

# Backup existing rules
BACKUP_FILE="/root/iptables-backup-$(date +%Y%m%d-%H%M%S).rules"
echo "Backing up current iptables rules to $BACKUP_FILE..."
iptables-save > "$BACKUP_FILE"
echo "Done"
echo ""

# Check if SSH accept rule exists for everyone
SSH_RULE_EXISTS=$(iptables -L INPUT -n | grep -E "ACCEPT.*tcp.*dpt:22" | grep -v "source" | head -1 | wc -l)

if [ "$SSH_RULE_EXISTS" -eq 0 ]; then
    echo "Adding SSH (port 22) accept rule for everyone..."

    # Find position before DROP all rule, or append if not found
    DROP_LINE=$(iptables -L INPUT -n --line-numbers | grep -E "DROP.*all.*0\.0\.0\.0/0.*0\.0\.0\.0/0" | head -1 | awk '{print $1}')

    if [ ! -z "$DROP_LINE" ]; then
        echo "  Inserting at position $DROP_LINE (before DROP all rule)"
        iptables -I INPUT $DROP_LINE -p tcp --dport 22 -j ACCEPT
    else
        echo "  Appending SSH rule (no DROP all rule found)"
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    fi
    echo "Done"
else
    echo "SSH accept rule already exists"
fi
echo ""

# Ensure default policy is DROP
echo "Setting default INPUT policy to DROP..."
iptables -P INPUT DROP
echo "Done"
echo ""

# Install shell hooks
echo "Installing shell hooks..."

# Backup and update .bashrc
if ! grep -q "auto-whitelist-on-ssh.sh" /root/.bashrc 2>/dev/null; then
    cat >> /root/.bashrc << 'BASHRC'

# SSH Whitelist - grant full access on login
if [ -n "$SSH_CLIENT" ] && [ -f /root/auto-whitelist-on-ssh.sh ]; then
    /root/auto-whitelist-on-ssh.sh
fi

# SSH Whitelist - revoke access on logout
trap '[[ -n "$SSH_CLIENT" ]] && /root/auto-remove-whitelist.sh 2>/dev/null' EXIT
BASHRC
    echo "  Added hooks to .bashrc"
else
    echo "  .bashrc hooks already exist"
fi

# Backup and update .zshrc
if ! grep -q "auto-whitelist-on-ssh.sh" /root/.zshrc 2>/dev/null; then
    cat >> /root/.zshrc << 'ZSHRC'

# SSH Whitelist - grant full access on login
if [ -n "$SSH_CLIENT" ] && [ -f /root/auto-whitelist-on-ssh.sh ]; then
    /root/auto-whitelist-on-ssh.sh
fi

# SSH Whitelist - revoke access on logout
trap '[[ -n "$SSH_CLIENT" ]] && /root/auto-remove-whitelist.sh 2>/dev/null' EXIT
ZSHRC
    echo "  Added hooks to .zshrc"
else
    echo "  .zshrc hooks already exist"
fi
echo ""

# Set script permissions
echo "Setting script permissions..."
chmod +x /root/auto-whitelist-on-ssh.sh
chmod +x /root/auto-remove-whitelist.sh
echo "Done"
echo ""

# Save iptables rules
echo "Saving iptables rules..."
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
echo "Done"
echo ""

# Create log file
touch /var/log/ssh-whitelist.log
chmod 644 /var/log/ssh-whitelist.log

echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "How it works:"
echo "  1. SSH (port 22) is open to everyone"
echo "  2. All other ports are blocked"
echo "  3. On SSH login  -> full port access granted"
echo "  4. On SSH logout -> full access revoked"
echo ""
echo "Files:"
echo "  /root/auto-whitelist-on-ssh.sh  - Grants access on login"
echo "  /root/auto-remove-whitelist.sh  - Revokes access on logout"
echo "  /var/log/ssh-whitelist.log      - Activity log"
echo "  /etc/iptables/rules.v4          - Saved firewall rules"
echo ""
echo "To verify:"
echo "  iptables -L INPUT -n --line-numbers | head -15"
echo ""
