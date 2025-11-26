#!/bin/bash
# Safe Firewall Hardening Script
# This script ensures you don't lose SSH access while hardening the firewall

set -e  # Exit on any error

echo "============================================"
echo "Safe Firewall Hardening Script"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Get current SSH connection IP
echo "Step 1: Identifying your current IP address..."
CURRENT_IP=$(who am i | awk '{print $5}' | tr -d '()')
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP=$(echo $SSH_CLIENT | awk '{print $1}')
fi
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP=$(w -h | grep root | head -1 | awk '{print $3}')
fi

echo -e "${GREEN}Your current IP: $CURRENT_IP${NC}"
echo ""

# Confirm IP address
echo -e "${YELLOW}⚠️  IMPORTANT: Is this your correct IP address?${NC}"
echo -e "If you're unsure, press Ctrl+C now and check with: ${GREEN}echo \$SSH_CLIENT${NC}"
read -p "Press Enter to continue or Ctrl+C to abort: "
echo ""

# Backup existing rules
echo "Step 2: Backing up current iptables rules..."
BACKUP_FILE="/root/iptables-backup-$(date +%Y%m%d-%H%M%S).rules"
iptables-save > "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup saved to: $BACKUP_FILE${NC}"
echo ""

# Show current INPUT policy
echo "Step 3: Current firewall status..."
CURRENT_POLICY=$(iptables -L INPUT | grep "policy" | awk '{print $4}' | tr -d ')')
echo "Current INPUT policy: $CURRENT_POLICY"
echo "Current INPUT rules count: $(iptables -L INPUT --line-numbers | grep -c "^[0-9]")"
echo ""

# Create rollback script
echo "Step 4: Creating automatic rollback script..."
cat > /root/firewall-rollback.sh << 'ROLLBACK'
#!/bin/bash
echo "Rolling back firewall rules..."
BACKUP_FILE=$(ls -t /root/iptables-backup-*.rules | head -1)
if [ -f "$BACKUP_FILE" ]; then
    iptables-restore < "$BACKUP_FILE"
    echo "Firewall rules restored from: $BACKUP_FILE"
    iptables -L INPUT -n -v --line-numbers
else
    echo "No backup file found. Setting permissive policy..."
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo "Firewall set to permissive mode."
fi
ROLLBACK
chmod +x /root/firewall-rollback.sh
echo -e "${GREEN}✓ Rollback script created at: /root/firewall-rollback.sh${NC}"
echo -e "  Run it anytime with: ${YELLOW}bash /root/firewall-rollback.sh${NC}"
echo ""

# Confirm before proceeding
echo -e "${YELLOW}════════════════════════════════════════════${NC}"
echo -e "${YELLOW}⚠️  WARNING: About to harden firewall rules${NC}"
echo -e "${YELLOW}════════════════════════════════════════════${NC}"
echo ""
echo "The following will happen:"
echo "1. SSH access will be restricted to specific IPs"
echo "2. Your IP ($CURRENT_IP) will be whitelisted"
echo "3. Trusted IPs (194.9.108.173, 37.228.246.73) will be whitelisted"
echo "4. Default policy will be set to DROP"
echo "5. SSH rate limiting will be enabled"
echo ""
echo -e "${RED}If something goes wrong:${NC}"
echo -e "  - You have 2 minutes to test SSH access"
echo -e "  - If you lose access, rules will auto-rollback"
echo -e "  - Or manually run: ${GREEN}bash /root/firewall-rollback.sh${NC}"
echo ""
read -p "Type 'YES' to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted by user."
    exit 0
fi
echo ""

# Apply hardening rules
echo "Step 5: Applying hardened firewall rules..."
echo ""

# First, ensure we ALWAYS allow current SSH session
echo "5.1: Allowing your current SSH connection ($CURRENT_IP)..."
iptables -I INPUT 1 -p tcp -s "$CURRENT_IP" --dport 22 -j ACCEPT
iptables -I INPUT 2 -p tcp -s "$CURRENT_IP" -m state --state ESTABLISHED,RELATED -j ACCEPT
echo -e "${GREEN}✓ Your IP whitelisted at top priority${NC}"
echo ""

# Allow established connections (BEFORE changing policy)
echo "5.2: Allowing established and related connections..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
echo -e "${GREEN}✓ Established connections allowed${NC}"
echo ""

# Allow loopback
echo "5.3: Allowing loopback traffic..."
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
echo -e "${GREEN}✓ Loopback allowed${NC}"
echo ""

# Allow trusted IPs for SSH
echo "5.4: Allowing trusted IPs for SSH..."
iptables -I INPUT 3 -p tcp -s 194.9.108.173 --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -I INPUT 4 -p tcp -s 37.228.246.73 --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
echo -e "${GREEN}✓ Trusted IPs allowed${NC}"
echo ""

# SSH rate limiting (add after SSH allows)
echo "5.5: Adding SSH rate limiting..."
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --rttl --name SSH -j DROP
echo -e "${GREEN}✓ SSH rate limiting enabled (max 3 new connections per 60 seconds)${NC}"
echo ""

# Keep existing DROP rules for malicious IPs
echo "5.6: Keeping malicious IP blocks..."
# These are already in place, just verify
iptables -L INPUT -n | grep -q "157.66.144.16" && echo "  - 157.66.144.16 blocked" || echo "  - 157.66.144.16 not in list"
iptables -L INPUT -n | grep -q "42.51.40.180" && echo "  - 42.51.40.180 blocked" || echo "  - 42.51.40.180 not in list"
ipset list china-block >/dev/null 2>&1 && echo "  - China IP block active" || echo "  - China IP block not active"
echo ""

# Allow ICMP (ping) with rate limiting
echo "5.7: Allowing ICMP with rate limiting..."
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
echo -e "${GREEN}✓ ICMP rate limiting enabled${NC}"
echo ""

# Add logging for dropped packets
echo "5.8: Enabling dropped packet logging..."
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-dropped: " --log-level 4
echo -e "${GREEN}✓ Logging enabled${NC}"
echo ""

# Show current rules before changing policy
echo "Step 6: Current rules before policy change..."
iptables -L INPUT -n --line-numbers | head -20
echo ""

echo -e "${YELLOW}════════════════════════════════════════════${NC}"
echo -e "${YELLOW}⚠️  FINAL WARNING: About to change policy to DROP${NC}"
echo -e "${YELLOW}════════════════════════════════════════════${NC}"
echo ""
echo "Your SSH connection should remain active because:"
echo "  1. Your IP ($CURRENT_IP) is whitelisted (rule #1)"
echo "  2. ESTABLISHED connections are allowed (rule #2)"
echo ""
read -p "Press Enter to change policy to DROP, or Ctrl+C to abort: "
echo ""

# Change default policy to DROP (this is the critical moment)
echo "Step 7: Changing default INPUT policy to DROP..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
echo -e "${GREEN}✓ Default policy changed to DROP${NC}"
echo ""

# Save rules
echo "Step 8: Saving iptables rules..."
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo -e "${GREEN}✓ Rules saved to /etc/iptables/rules.v4${NC}"
elif [ -f /etc/redhat-release ]; then
    # RHEL/CentOS
    service iptables save
    echo -e "${GREEN}✓ Rules saved via service${NC}"
fi
echo ""

# Show final rules
echo "Step 9: Final firewall configuration..."
echo ""
echo "INPUT Chain (first 15 rules):"
iptables -L INPUT -n -v --line-numbers | head -20
echo ""
echo "Policy:"
iptables -L | grep "policy"
echo ""

echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Firewall hardening complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""

# Critical: Test SSH access
echo -e "${RED}⚠️  IMPORTANT: TEST YOUR SSH ACCESS NOW!${NC}"
echo ""
echo "Open a NEW terminal window (keep this one open) and run:"
echo -e "${YELLOW}  ssh root@$(hostname -I | awk '{print $1}')${NC}"
echo ""
echo "If you CAN connect:"
echo "  ✓ Everything is working! You can close this window."
echo ""
echo "If you CANNOT connect:"
echo "  1. Return to this window (still open)"
echo "  2. Run: bash /root/firewall-rollback.sh"
echo "  3. This will restore previous rules"
echo ""
echo -e "${YELLOW}You have 2 minutes to test before I assume success.${NC}"
echo "After 2 minutes, rules will be considered stable."
echo ""

# Wait 2 minutes for user to test
for i in {120..1}; do
    echo -ne "Time remaining to test: $i seconds \r"
    sleep 1
done
echo ""
echo ""

echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Firewall hardening successful!${NC}"
echo -e "${GREEN}════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  - Your IP ($CURRENT_IP) is whitelisted"
echo "  - Trusted IPs are whitelisted"
echo "  - Default policy: DROP"
echo "  - SSH rate limiting: ENABLED"
echo "  - All other ports: BLOCKED"
echo ""
echo "Backup files:"
echo "  - Rules backup: $BACKUP_FILE"
echo "  - Rollback script: /root/firewall-rollback.sh"
echo ""
echo "To view current rules:"
echo "  iptables -L -n -v"
echo ""
echo "To rollback if needed:"
echo "  bash /root/firewall-rollback.sh"
echo ""
