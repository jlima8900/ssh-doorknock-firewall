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
3. **ALL ports become accessible** to your IP only (including Docker containers!)
4. **SSH logout removes access** - back to blocked
5. **No static whitelist** - purely dynamic via SSH "doorknock"

## How Docker Container Access Works

When you SSH in, the whitelist script configures two firewall chains:

1. **INPUT chain** - Allows all traffic from your IP to the host
2. **DOCKER-USER chain** - Allows your IP to access Docker containers

The `DOCKER-USER` chain setup:
```
1. RETURN  ctstate ESTABLISHED,RELATED  (allows return traffic - global rule)
2. RETURN  <your-ip>                     (allows new connections from your IP)
3. DROP    all                           (blocks everyone else)
```

**Why the ESTABLISHED,RELATED rule?**
Docker container traffic flows through the FORWARD chain, not INPUT. Without this rule, the TCP handshake fails because return packets (SYN-ACK) from containers get dropped. This global rule stays permanently and benefits all whitelisted IPs.

**On logout:**
- Your IP-specific rules are removed
- The ESTABLISHED,RELATED rule stays (it's shared by all users)

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
| `connect-with-tunnels.sh` | **Client script** - SSH connect with auto port forwards |
| `ssh-config-example` | **Client config** - SSH config template with tunnels |

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

## Client-Side: Accessing Services Behind Restrictive Firewalls

If your work/corporate network blocks non-standard ports (only allowing 22, 80, 443), use SSH tunnels to access your services.

### Option 1: Connection Script

Use the provided script to connect with auto-tunnels:

```bash
./connect-with-tunnels.sh
# Or with custom settings:
./connect-with-tunnels.sh -h your-server.com -u admin
```

This creates local port forwards so you can access services at `localhost:PORT`.

### Option 2: SSH Config (Recommended for Daily Use)

Add to `~/.ssh/config` on your **client machine**:

```
Host keeper-server
    HostName 149.102.159.192
    User root
    LocalForward 8080 localhost:8080
    LocalForward 8444 localhost:8444
    LocalForward 8000 localhost:8000
    LocalForward 3000 localhost:3000
    ServerAliveInterval 60
```

Then just run:
```bash
ssh keeper-server
```

Access services at:
- `https://localhost:8444` - Your HTTPS service
- `http://localhost:8080` - Your HTTP service
- `http://localhost:8000` - Backend API

See `ssh-config-example` for a complete configuration with connection multiplexing.

### How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│              SSH TUNNELING THROUGH RESTRICTIVE FIREWALL             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   YOUR LAPTOP          CORP FIREWALL           YOUR SERVER          │
│   ══════════           ═════════════           ═══════════          │
│                                                                     │
│   Browser ──► localhost:8444 ─┐                                     │
│                               │                                     │
│   SSH Client ────────────────►├──► port 22 ──────► sshd             │
│   (tunnel carrier)            │    (allowed)       │                │
│                               │                    ▼                │
│                               │              ┌───────────┐          │
│                               │              │ Doorknock │          │
│                               │              │ whitelist │          │
│                               │              └───────────┘          │
│                               │                    │                │
│   localhost:8444 ◄────────────┴────────────────────┴──► :8444       │
│   (your browser)              SSH tunnel              (service)     │
│                                                                     │
│   Result: Access blocked ports through SSH tunnel                   │
└─────────────────────────────────────────────────────────────────────┘
```

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
