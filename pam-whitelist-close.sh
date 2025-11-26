#!/bin/bash
###############################################################################
# PAM Session Close - Remove IP Whitelist if No Other Sessions
# Called by pam_exec on SSH session end
# Only removes whitelist when the last session from this IP disconnects
###############################################################################

CLIENT_IP="$PAM_RHOST"
[ -z "$CLIENT_IP" ] && exit 0

# Count other sessions from this IP (exclude current closing session)
# Use 'ss' which is more reliable than 'who' for counting SSH connections
ACTIVE=$(ss -tn state established '( sport = :22 )' 2>/dev/null | grep -c "$CLIENT_IP")

# If more than 1 session (current one still counted), keep whitelist
if [ "$ACTIVE" -gt 1 ]; then
    echo "[$(date)] PAM keeping whitelist: $CLIENT_IP ($ACTIVE sessions)" >> /var/log/ssh-whitelist.log
    exit 0
fi

# Remove rules - this is the last session
echo "[$(date)] PAM removing whitelist: $CLIENT_IP" >> /var/log/ssh-whitelist.log

# Remove INPUT rules
while iptables -L INPUT -n --line-numbers | grep -qE "ACCEPT.*all.*$CLIENT_IP"; do
    LINE=$(iptables -L INPUT -n --line-numbers | grep -E "ACCEPT.*all.*$CLIENT_IP" | head -1 | awk '{print $1}')
    [ -z "$LINE" ] && break
    iptables -D INPUT $LINE
done

# Remove DOCKER-USER rules
while iptables -L DOCKER-USER -n --line-numbers 2>/dev/null | grep -qE "RETURN.*$CLIENT_IP"; do
    LINE=$(iptables -L DOCKER-USER -n --line-numbers | grep -E "RETURN.*$CLIENT_IP" | head -1 | awk '{print $1}')
    [ -z "$LINE" ] && break
    iptables -D DOCKER-USER $LINE
done

exit 0
