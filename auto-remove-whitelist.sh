#!/bin/bash
# Automatic IP Whitelist Removal on SSH Logout
# Removes full access rule for SSH client IP

# Get the SSH client IP
CLIENT_IP=$(echo $SSH_CLIENT | awk '{print $1}')
if [ -z "$CLIENT_IP" ]; then
    CLIENT_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
fi

if [ -z "$CLIENT_IP" ]; then
    echo "Could not detect SSH client IP"
    exit 1
fi

# Check if there are other active SSH sessions from this IP
ACTIVE_SESSIONS=$(who | grep "$CLIENT_IP" | wc -l)

if [ $ACTIVE_SESSIONS -gt 1 ]; then
    echo "Other SSH sessions from $CLIENT_IP still active, keeping whitelist"
    echo "[$(date)] Keeping whitelist for $CLIENT_IP ($ACTIVE_SESSIONS sessions active)" >> /var/log/ssh-whitelist.log
    exit 0
fi

echo "Removing full access for IP: $CLIENT_IP"

# Remove the ACCEPT all rule for this IP
# Loop in case multiple rules exist
REMOVED_COUNT=0
while iptables -L INPUT -n --line-numbers | grep -E "ACCEPT.*all.*$CLIENT_IP" | grep -v "tcp\|udp" > /dev/null 2>&1; do
    # Get line number of the ACCEPT all rule
    LINE_NUM=$(iptables -L INPUT -n --line-numbers | grep -E "ACCEPT.*all.*$CLIENT_IP" | grep -v "tcp\|udp" | head -1 | awk '{print $1}')

    if [ ! -z "$LINE_NUM" ]; then
        iptables -D INPUT $LINE_NUM
        ((REMOVED_COUNT++))
        echo "  Removed ACCEPT all rule #$LINE_NUM for $CLIENT_IP"
    else
        break
    fi

    # Safety check
    if [ $REMOVED_COUNT -gt 10 ]; then
        echo "Warning: Removed more than 10 rules, stopping"
        break
    fi
done

if [ $REMOVED_COUNT -gt 0 ]; then
    echo "[$(date)] Removed full access for $CLIENT_IP ($REMOVED_COUNT rules)" >> /var/log/ssh-whitelist.log
    echo "Full access revoked for $CLIENT_IP"
else
    echo "No full access rule found for $CLIENT_IP"
fi

# Also remove DOCKER-USER rules for this IP
echo "Removing Docker access for IP: $CLIENT_IP"
DOCKER_REMOVED=0
while iptables -L DOCKER-USER -n --line-numbers 2>/dev/null | grep -E "RETURN.*$CLIENT_IP" > /dev/null 2>&1; do
    LINE_NUM=$(iptables -L DOCKER-USER -n --line-numbers | grep -E "RETURN.*$CLIENT_IP" | head -1 | awk '{print $1}')

    if [ ! -z "$LINE_NUM" ]; then
        iptables -D DOCKER-USER $LINE_NUM
        ((DOCKER_REMOVED++))
        echo "  Removed DOCKER-USER RETURN rule #$LINE_NUM for $CLIENT_IP"
    else
        break
    fi

    # Safety check
    if [ $DOCKER_REMOVED -gt 10 ]; then
        echo "Warning: Removed more than 10 Docker rules, stopping"
        break
    fi
done

if [ $DOCKER_REMOVED -gt 0 ]; then
    echo "[$(date)] Removed Docker access for $CLIENT_IP ($DOCKER_REMOVED rules)" >> /var/log/ssh-whitelist.log
    echo "Docker access revoked for $CLIENT_IP"
fi
