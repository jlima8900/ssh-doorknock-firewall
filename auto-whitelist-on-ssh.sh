#!/bin/bash
# Automatic IP Whitelisting on SSH Login
# Grants full access to SSH client IP (all ports)
# Removed on logout by auto-remove-whitelist.sh

# Get the SSH client IP
CLIENT_IP=$(echo $SSH_CLIENT | awk '{print $1}')
if [ -z "$CLIENT_IP" ]; then
    CLIENT_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
fi

if [ -z "$CLIENT_IP" ]; then
    echo "Could not detect SSH client IP"
    exit 1
fi

# Log the action
echo "[$(date)] Auto-whitelisting IP: $CLIENT_IP (full access)" >> /var/log/ssh-whitelist.log

# Check if ACCEPT all rule already exists for this IP
RULE_EXISTS=$(iptables -L INPUT -n | grep -E "ACCEPT.*all.*$CLIENT_IP" | grep -v "tcp\|udp" | wc -l)

if [ $RULE_EXISTS -gt 0 ]; then
    echo "IP $CLIENT_IP already has full access"
else
    echo "Granting full access to IP: $CLIENT_IP..."

    # Add single ACCEPT all rule (insert after SSH rules, position 5)
    iptables -I INPUT 5 -s "$CLIENT_IP" -j ACCEPT

    echo "[$(date)] Granted full access to $CLIENT_IP" >> /var/log/ssh-whitelist.log
    echo "Full access granted to $CLIENT_IP"
fi

# Also handle DOCKER-USER chain for Docker container access

# First, ensure ESTABLISHED,RELATED rule exists at top of DOCKER-USER
# This allows return traffic from containers (critical for TCP handshakes)
ESTAB_RULE_EXISTS=$(iptables -L DOCKER-USER -n 2>/dev/null | grep -E "RETURN.*ctstate.*RELATED,ESTABLISHED" | wc -l)

if [ $ESTAB_RULE_EXISTS -eq 0 ]; then
    echo "Adding ESTABLISHED,RELATED rule to DOCKER-USER chain..."
    iptables -I DOCKER-USER 1 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    echo "[$(date)] Added ESTABLISHED,RELATED rule to DOCKER-USER" >> /var/log/ssh-whitelist.log
fi

# Now add the IP-specific RETURN rule
DOCKER_RULE_EXISTS=$(iptables -L DOCKER-USER -n 2>/dev/null | grep -E "RETURN.*$CLIENT_IP" | wc -l)

if [ $DOCKER_RULE_EXISTS -gt 0 ]; then
    echo "IP $CLIENT_IP already has Docker access"
else
    echo "Granting Docker access to IP: $CLIENT_IP..."

    # Add RETURN rule to DOCKER-USER (allows traffic to continue to DOCKER chain)
    # Insert after the ESTABLISHED,RELATED rule
    iptables -I DOCKER-USER 2 -s "$CLIENT_IP" -j RETURN

    echo "[$(date)] Granted Docker access to $CLIENT_IP" >> /var/log/ssh-whitelist.log
    echo "Docker access granted to $CLIENT_IP"
fi

# Flush conntrack entries for this IP to ensure immediate access
# This clears any stale "blocked" connection states
if command -v conntrack >/dev/null 2>&1; then
    conntrack -D -s "$CLIENT_IP" 2>/dev/null
    conntrack -D -d "$CLIENT_IP" 2>/dev/null
fi
