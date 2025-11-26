#!/bin/bash
###############################################################################
# Initialize DOCKER-USER Chain with DROP Rule
# Run after Docker starts to ensure Docker container ports are blocked by default
# Only SSH doorknock (PAM whitelist) can grant access
###############################################################################

# Wait for Docker to create the DOCKER-USER chain (up to 30 seconds)
for i in {1..30}; do
    if iptables -L DOCKER-USER -n >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Check if DOCKER-USER chain exists
if ! iptables -L DOCKER-USER -n >/dev/null 2>&1; then
    echo "[$(date)] DOCKER-USER chain not found, Docker may not be running" >> /var/log/ssh-whitelist.log
    exit 0
fi

# Check if DROP rule already exists at the end
DROP_EXISTS=$(iptables -L DOCKER-USER -n | tail -1 | grep -c "DROP.*0.0.0.0/0.*0.0.0.0/0")

if [ "$DROP_EXISTS" -eq 0 ]; then
    echo "[$(date)] Adding DROP rule to DOCKER-USER chain" >> /var/log/ssh-whitelist.log
    iptables -A DOCKER-USER -j DROP
    echo "DROP rule added to DOCKER-USER"
else
    echo "DROP rule already exists in DOCKER-USER"
fi
