#!/bin/bash
# SSH Doorknock Connection Script with Auto-Tunnels
# Connects via SSH (triggers doorknock whitelist) and creates local port forwards
# for accessing services when behind restrictive firewalls

set -e

# Configuration - customize these
SERVER_HOST="${SERVER_HOST:-149.102.159.192}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PORT="${SERVER_PORT:-22}"

# Default tunnels - add/remove as needed
# Format: LOCAL_PORT:REMOTE_HOST:REMOTE_PORT
TUNNELS=(
    "8080:localhost:8080"    # MultiplexSSH HTTP
    "8444:localhost:8444"    # MultiplexSSH HTTPS
    "8000:localhost:8000"    # Backend API
    "3000:localhost:3000"    # Frontend Dev
    "6080:localhost:6080"    # VNC/noVNC
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║          SSH DOORKNOCK - Tunnel Connection Script             ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Connects to server and creates local port forwards           ║"
    echo "║  Your IP will be auto-whitelisted via doorknock on login      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_tunnels() {
    echo -e "${GREEN}Local Port Forwards:${NC}"
    echo "┌─────────────────────────────────────────────────────────────┐"
    for tunnel in "${TUNNELS[@]}"; do
        local_port=$(echo "$tunnel" | cut -d: -f1)
        remote_host=$(echo "$tunnel" | cut -d: -f2)
        remote_port=$(echo "$tunnel" | cut -d: -f3)
        echo "│  localhost:${local_port} → ${remote_host}:${remote_port}"
    done
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo -e "${YELLOW}After connection, access services at:${NC}"
    echo "  https://localhost:8444  - MultiplexSSH"
    echo "  http://localhost:8080   - MultiplexSSH (HTTP)"
    echo "  http://localhost:8000   - Backend API"
    echo "  http://localhost:3000   - Frontend Dev"
    echo ""
}

build_ssh_command() {
    local cmd="ssh"

    # Add port if not default
    if [ "$SERVER_PORT" != "22" ]; then
        cmd="$cmd -p $SERVER_PORT"
    fi

    # Add tunnel forwards
    for tunnel in "${TUNNELS[@]}"; do
        cmd="$cmd -L $tunnel"
    done

    # Add user@host
    cmd="$cmd ${SERVER_USER}@${SERVER_HOST}"

    echo "$cmd"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            SERVER_HOST="$2"
            shift 2
            ;;
        -u|--user)
            SERVER_USER="$2"
            shift 2
            ;;
        -p|--port)
            SERVER_PORT="$2"
            shift 2
            ;;
        --add-tunnel)
            TUNNELS+=("$2")
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -h, --host HOST      Server hostname/IP (default: $SERVER_HOST)"
            echo "  -u, --user USER      SSH username (default: $SERVER_USER)"
            echo "  -p, --port PORT      SSH port (default: $SERVER_PORT)"
            echo "  --add-tunnel L:H:P   Add extra tunnel (local:host:port)"
            echo "  --help               Show this help"
            echo ""
            echo "Environment variables:"
            echo "  SERVER_HOST          Override default host"
            echo "  SERVER_USER          Override default user"
            echo "  SERVER_PORT          Override default SSH port"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main
print_banner
print_tunnels

SSH_CMD=$(build_ssh_command)
echo -e "${GREEN}Connecting...${NC}"
echo "Command: $SSH_CMD"
echo ""

# Execute SSH with tunnels
exec $SSH_CMD
