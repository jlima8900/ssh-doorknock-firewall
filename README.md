# SSH Doorknock Firewall

Dynamic IP whitelisting via SSH authentication - like a VPN without the VPN.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SSH DOORKNOCK FIREWALL                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   INTERNET                        YOUR SERVER                       │
│   ════════                        ═══════════                       │
│                                                                     │
│   Attacker ──────────────────X────► All Ports (BLOCKED)             │
│   (no SSH)                    │                                     │
│                               │    ┌─────────────────────┐          │
│                               └────│ DOCKER-USER: DROP   │          │
│                                    └─────────────────────┘          │
│                                                                     │
│   You ─────► SSH (port 22) ──────► PAM detects login                │
│   (with key)        │              │                                │
│                     │              ▼                                │
│                     │         ┌─────────────────────┐               │
│                     │         │ pam-whitelist-open  │               │
│                     │         │ - Add ACCEPT rule   │               │
│                     │         │ - Add DOCKER RETURN │               │
│                     │         └─────────────────────┘               │
│                     │              │                                │
│                     │              ▼                                │
│                     └────────► ALL PORTS (ALLOWED) ◄── You only!    │
│                                                                     │
│   On logout ──────────────────────► pam-whitelist-close             │
│                                     - Remove rules                  │
│                                     - Back to blocked               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Only SSH (port 22) is open** to the world
2. **SSH login triggers PAM** which adds your IP to iptables
3. **ALL ports become accessible** to your IP only
4. **SSH logout removes access** - back to blocked
5. **No static whitelist** - purely dynamic via SSH "doorknock"

## Requirements

- Linux (Debian, Ubuntu, RHEL, CentOS, Fedora, etc.)
- iptables
- Root access
- Optional: Docker (for container port protection)

## Quick Install (PAM Method - Recommended)

The PAM method triggers on actual SSH session events, not shell startup.

**1. Copy scripts:**
```bash
cp pam-whitelist-open.sh /root/
cp pam-whitelist-close.sh /root/
chmod +x /root/pam-whitelist-*.sh
```

**2. Configure PAM:**
```bash
echo "session optional pam_exec.so type=open_session /root/pam-whitelist-open.sh" >> /etc/pam.d/sshd
echo "session optional pam_exec.so type=close_session /root/pam-whitelist-close.sh" >> /etc/pam.d/sshd
```

**3. For Docker (optional):**
```bash
cp docker-user-firewall-init.sh /root/
cp docker-user-firewall.service /etc/systemd/system/
chmod +x /root/docker-user-firewall-init.sh
systemctl daemon-reload
systemctl enable --now docker-user-firewall.service
```

**4. Test it:**
```bash
# Open a NEW SSH session (keep current one open!)
tail -f /var/log/ssh-whitelist.log
```

## Alternative: Shell-based Setup

If PAM isn't suitable, use the shell-based method:

```bash
chmod +x setup-ssh-whitelist.sh
./setup-ssh-whitelist.sh
```

This adds whitelist/remove scripts to `.bashrc` and `.bash_logout`.

## Files

| File | Purpose |
|------|---------|
| `pam-whitelist-open.sh` | PAM script - grants ALL port access on SSH login |
| `pam-whitelist-close.sh` | PAM script - revokes access when last session ends |
| `docker-user-firewall-init.sh` | Boot script - adds DROP rule to DOCKER-USER chain |
| `docker-user-firewall.service` | Systemd service for Docker firewall persistence |
| `auto-whitelist-on-ssh.sh` | Alternative: shell-based whitelist (via .bashrc) |
| `auto-remove-whitelist.sh` | Alternative: shell-based removal (via .bash_logout) |
| `safe-firewall-hardening.sh` | Interactive firewall hardening with rollback |
| `setup-ssh-whitelist.sh` | One-click shell-based setup |

## How the PAM Scripts Work

**On login (`pam-whitelist-open.sh`):**
- Detects your SSH client IP from `$SSH_CLIENT`
- Adds `iptables -I INPUT -s $IP -j ACCEPT`
- Adds `iptables -I DOCKER-USER -s $IP -j RETURN` (if Docker)
- Logs to `/var/log/ssh-whitelist.log`

**On logout (`pam-whitelist-close.sh`):**
- Checks if other sessions from your IP exist
- If last session, removes iptables rules
- Logs the removal

## Security Notes

- This is **not** a replacement for proper SSH hardening
- Use SSH keys, disable password auth
- Consider fail2ban for brute force protection
- The firewall only protects against unauthorized port access

## Troubleshooting

**Check if rules are active:**
```bash
iptables -L INPUT -n --line-numbers | head -20
iptables -L DOCKER-USER -n --line-numbers
```

**View whitelist log:**
```bash
tail -f /var/log/ssh-whitelist.log
```

**Manual rule removal:**
```bash
# Find and remove rules for a specific IP
iptables -L INPUT -n --line-numbers | grep "YOUR_IP"
iptables -D INPUT <line_number>
```

## License

MIT - Do whatever you want with it!
