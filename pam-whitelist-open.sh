#!/bin/bash
###############################################################################
# PAM Session Open - Whitelist IP for Docker/Service Access
# Called by pam_exec on SSH session start
# Uses PAM_RHOST for client IP (more reliable than SSH_CLIENT)
###############################################################################

CLIENT_IP="$PAM_RHOST"
[ -z "$CLIENT_IP" ] && exit 0

# Log the action
echo "[$(date)] PAM whitelist: $CLIENT_IP (user: $PAM_USER)" >> /var/log/ssh-whitelist.log

# Add INPUT rule if not exists (allows all traffic from this IP)
if ! iptables -L INPUT -n | grep -qE "ACCEPT.*all.*$CLIENT_IP"; then
    iptables -I INPUT 5 -s "$CLIENT_IP" -j ACCEPT
    echo "[$(date)] Added INPUT ACCEPT rule for $CLIENT_IP" >> /var/log/ssh-whitelist.log
fi

# Add DOCKER-USER rule if not exists (allows Docker container access)
if ! iptables -L DOCKER-USER -n 2>/dev/null | grep -qE "RETURN.*$CLIENT_IP"; then
    iptables -I DOCKER-USER -s "$CLIENT_IP" -j RETURN
    echo "[$(date)] Added DOCKER-USER RETURN rule for $CLIENT_IP" >> /var/log/ssh-whitelist.log
fi

# Flush conntrack to ensure new rules take effect immediately
# This clears stale connection states that might block traffic
conntrack -D -s "$CLIENT_IP" 2>/dev/null
conntrack -D -d "$CLIENT_IP" 2>/dev/null

exit 0
