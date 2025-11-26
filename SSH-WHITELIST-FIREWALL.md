# SSH Whitelist Firewall

A port-knock style security system that uses SSH authentication as the "knock" to open firewall access.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  DEFAULT STATE                                              │
│  - SSH (port 22): OPEN to everyone                          │
│  - All other ports: BLOCKED                                 │
└─────────────────────────────────────────────────────────────┘
                           │
                    SSH Login (success)
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  AUTHENTICATED STATE                                        │
│  - Your IP gets "ACCEPT all" rule                           │
│  - Full port access (80, 443, 3000, etc.)                   │
└─────────────────────────────────────────────────────────────┘
                           │
                    SSH Logout (all sessions)
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  BACK TO DEFAULT                                            │
│  - "ACCEPT all" rule removed for your IP                    │
│  - Only SSH access remains                                  │
└─────────────────────────────────────────────────────────────┘
```

## Security Benefits

1. **Reduced Attack Surface**: Only SSH is exposed; web services, APIs, databases are hidden
2. **Authentication Required**: Must authenticate via SSH before accessing any other service
3. **Automatic Cleanup**: Access is revoked when all SSH sessions close
4. **Multi-Session Aware**: Keeps access while any session from that IP is active
5. **Logging**: All whitelist/revoke actions are logged

## Files

| File | Description |
|------|-------------|
| `auto-whitelist-on-ssh.sh` | Grants full access on SSH login |
| `auto-remove-whitelist.sh` | Revokes access on SSH logout |
| `setup-ssh-whitelist.sh` | Initial setup script |
| `/var/log/ssh-whitelist.log` | Activity log |
| `/etc/iptables/rules.v4` | Saved firewall rules |

## Installation

### Quick Setup

```bash
# Clone the repository (if not already present)
git clone https://github.com/jlima8900/keeper-security-motd.git
cd keeper-security-motd

# Run the setup script
chmod +x setup-ssh-whitelist.sh
./setup-ssh-whitelist.sh
```

### Manual Setup

1. **Copy scripts to /root/**:
```bash
cp auto-whitelist-on-ssh.sh /root/
cp auto-remove-whitelist.sh /root/
chmod +x /root/auto-whitelist-on-ssh.sh
chmod +x /root/auto-remove-whitelist.sh
```

2. **Add SSH accept rule for everyone** (CRITICAL):
```bash
# Find the DROP all rule position
iptables -L INPUT -n --line-numbers | grep "DROP.*all"

# Insert SSH accept BEFORE the DROP all rule
# Example: if DROP all is at position 12
iptables -I INPUT 12 -p tcp --dport 22 -j ACCEPT
```

3. **Add shell hooks to ~/.bashrc and ~/.zshrc**:
```bash
# SSH Whitelist - grant full access on login
if [ -n "$SSH_CLIENT" ] && [ -f /root/auto-whitelist-on-ssh.sh ]; then
    /root/auto-whitelist-on-ssh.sh
fi

# SSH Whitelist - revoke access on logout
trap '[[ -n "$SSH_CLIENT" ]] && /root/auto-remove-whitelist.sh 2>/dev/null' EXIT
```

4. **Save iptables rules**:
```bash
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
```

## Verification

### Check firewall rules
```bash
iptables -L INPUT -n --line-numbers | head -20
```

Expected output should include:
```
X    ACCEPT     tcp  --  0.0.0.0/0  0.0.0.0/0  tcp dpt:22   <- SSH open to all
...
Y    DROP       all  --  0.0.0.0/0  0.0.0.0/0                <- Default drop
```

### Check whitelist log
```bash
tail -f /var/log/ssh-whitelist.log
```

### Test the system
1. SSH from a new IP
2. Check that ACCEPT all rule was added: `iptables -L INPUT -n | grep YOUR_IP`
3. Access other services (should work)
4. Disconnect SSH
5. Verify ACCEPT all rule was removed

## Troubleshooting

### SSH connections blocked
The SSH accept rule must be BEFORE any DROP all rule:
```bash
# Check rule order
iptables -L INPUT -n --line-numbers

# If SSH rule is missing or after DROP, add it
iptables -I INPUT [POSITION_BEFORE_DROP] -p tcp --dport 22 -j ACCEPT
```

### Whitelist not being added
Check shell hooks are installed:
```bash
grep "auto-whitelist" ~/.bashrc ~/.zshrc
```

### Access not revoked on logout
- Multiple sessions keep access active (by design)
- Check: `who | grep YOUR_IP`
- Manual revoke: `iptables -D INPUT -s YOUR_IP -j ACCEPT`

## Firewall Rule Order

Recommended order:
1. ACCEPT rules for always-trusted IPs
2. ACCEPT rules for whitelisted session IPs
3. Loopback/established connections
4. Block lists (fail2ban, country blocks)
5. **ACCEPT tcp port 22** (SSH for everyone)
6. DROP all (default deny)

## License

MIT License
