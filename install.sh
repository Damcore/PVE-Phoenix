#!/bin/bash

# VM Watchdog Interactive Installer for Proxmox
# Makes installation easy with guided prompts

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Header
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   PVE Phoenix Installer for Proxmox    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Check if Proxmox (qm command exists)
if ! command -v qm &> /dev/null; then
    echo -e "${RED}Error: 'qm' command not found. Are you running this on Proxmox?${NC}"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Proxmox environment detected"
echo ""

# Get VM ID
echo -e "${YELLOW}Step 1: Which VM should be monitored?${NC}"
if [[ -t 0 ]]; then
    # Interactive mode (stdin is a terminal)
    read -p "Enter VM ID [default: 444]: " VMID
    VMID=${VMID:-444}
else
    # Non-interactive mode (piped from curl)
    # Use VMID env var or default to 444
    VMID=${VMID:-444}
    echo "Using VM ID: $VMID (set VMID env var to override)"
fi

# Validate VM exists
echo -n "Checking if VM $VMID exists... "
if ! qm status "$VMID" &>/dev/null; then
    echo -e "${RED}[FAIL]${NC}"
    echo -e "${RED}Error: VM $VMID does not exist!${NC}"
    echo ""
    echo "Available VMs:"
    qm list
    exit 1
fi
echo -e "${GREEN}[OK]${NC}"

# Show VM info
VM_NAME=$(qm config "$VMID" | grep '^name:' | cut -d' ' -f2- || echo "Unknown")
VM_STATUS=$(qm status "$VMID" | awk '{print $2}')
echo -e "  VM ID: ${GREEN}$VMID${NC}"
echo -e "  Name: ${GREEN}$VM_NAME${NC}"
echo -e "  Current Status: ${GREEN}$VM_STATUS${NC}"
echo ""

# Get rate limits
echo -e "${YELLOW}Step 2: Configure restart limits (prevents restart loops)${NC}"
if [[ -t 0 ]]; then
    # Interactive mode
    while true; do
        read -p "Max restarts per hour [default: 5]: " HOURLY_LIMIT
        HOURLY_LIMIT=${HOURLY_LIMIT:-5}
        if [[ "$HOURLY_LIMIT" =~ ^[0-9]+$ ]] && [[ "$HOURLY_LIMIT" -gt 0 ]]; then
            break
        else
            echo -e "${RED}Error: Please enter a positive number${NC}"
        fi
    done

    while true; do
        read -p "Max restarts per day [default: 20]: " DAILY_LIMIT
        DAILY_LIMIT=${DAILY_LIMIT:-20}
        if [[ "$DAILY_LIMIT" =~ ^[0-9]+$ ]] && [[ "$DAILY_LIMIT" -gt 0 ]]; then
            break
        else
            echo -e "${RED}Error: Please enter a positive number${NC}"
        fi
    done
else
    # Non-interactive mode
    HOURLY_LIMIT=${HOURLY_LIMIT:-5}
    DAILY_LIMIT=${DAILY_LIMIT:-20}
    echo "Using hourly limit: $HOURLY_LIMIT (set HOURLY_LIMIT env var to override)"
    echo "Using daily limit: $DAILY_LIMIT (set DAILY_LIMIT env var to override)"
fi
echo ""

# Get check interval
echo -e "${YELLOW}Step 3: Monitoring settings${NC}"
if [[ -t 0 ]]; then
    # Interactive mode
    while true; do
        read -p "Check VM status every X seconds [default: 30]: " CHECK_INTERVAL
        CHECK_INTERVAL=${CHECK_INTERVAL:-30}
        if [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] && [[ "$CHECK_INTERVAL" -gt 0 ]]; then
            break
        else
            echo -e "${RED}Error: Please enter a positive number${NC}"
        fi
    done
else
    # Non-interactive mode
    CHECK_INTERVAL=${CHECK_INTERVAL:-30}
    echo "Using check interval: $CHECK_INTERVAL seconds (set CHECK_INTERVAL env var to override)"
fi
echo ""

# Confirm settings
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Configuration Summary:${NC}"
echo -e "  VM ID: ${GREEN}$VMID${NC} (${VM_NAME})"
echo -e "  Hourly Limit: ${GREEN}$HOURLY_LIMIT${NC} restarts"
echo -e "  Daily Limit: ${GREEN}$DAILY_LIMIT${NC} restarts"
echo -e "  Check Interval: ${GREEN}$CHECK_INTERVAL${NC} seconds"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ -t 0 ]]; then
    # Interactive mode - ask for confirmation
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
else
    # Non-interactive mode - auto-proceed (set SKIP_CONFIRM=0 to abort)
    SKIP_CONFIRM=${SKIP_CONFIRM:-1}
    if [[ "$SKIP_CONFIRM" != "1" ]]; then
        echo "Installation cancelled (SKIP_CONFIRM not set to 1)."
        exit 0
    fi
    echo "Auto-proceeding with installation (non-interactive mode)..."
fi
echo ""

# Create customized script
echo -e "${BLUE}Installing VM Watchdog...${NC}"

# Get the directory where this installer script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if vm-watchdog.sh template exists
if [[ ! -f "$SCRIPT_DIR/vm-watchdog.sh" ]]; then
    echo -e "${RED}Error: vm-watchdog.sh template not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Copy template and replace default values with user-specified values
sed -e "s/^VMID=.*/VMID=$VMID/" \
    -e "s/HOURLY_RESTARTS -ge [0-9]\+/HOURLY_RESTARTS -ge $HOURLY_LIMIT/" \
    -e "s/DAILY_RESTARTS -ge [0-9]\+/DAILY_RESTARTS -ge $DAILY_LIMIT/" \
    -e "s/Hourly limit ([0-9]\+)/Hourly limit ($HOURLY_LIMIT)/" \
    -e "s/Daily limit ([0-9]\+)/Daily limit ($DAILY_LIMIT)/" \
    -e "s/Hourly: \$HOURLY_RESTARTS\/[0-9]\+/Hourly: \$HOURLY_RESTARTS\/$HOURLY_LIMIT/" \
    -e "s/Daily: \$DAILY_RESTARTS\/[0-9]\+/Daily: \$DAILY_RESTARTS\/$DAILY_LIMIT/" \
    -e "s/sleep [0-9]\+  # Check every/sleep $CHECK_INTERVAL  # Check every/" \
    "$SCRIPT_DIR/vm-watchdog.sh" > /usr/local/bin/vm-watchdog.sh

# Make executable
chmod +x /usr/local/bin/vm-watchdog.sh
echo -e "${GREEN}[OK]${NC} Script installed to /usr/local/bin/vm-watchdog.sh"

# Create systemd service
cat > /etc/systemd/system/vm-watchdog.service <<EOF
[Unit]
Description=Proxmox VM $VMID Watchdog ($VM_NAME)
After=network.target pve-cluster.service

[Service]
Type=simple
ExecStart=/usr/local/bin/vm-watchdog.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}[OK]${NC} Systemd service created"

# Create config directory
mkdir -p /etc/vm-watchdog
echo -e "${GREEN}[OK]${NC} Config directory created"

# Install logrotate configuration
if [[ -f "$SCRIPT_DIR/vm-watchdog.logrotate" ]]; then
    # Local file exists (cloned repo)
    cp "$SCRIPT_DIR/vm-watchdog.logrotate" /etc/logrotate.d/vm-watchdog
    echo -e "${GREEN}[OK]${NC} Log rotation configured"
else
    # Download from GitHub (curl | bash installation)
    echo -n "Downloading logrotate config from GitHub... "
    if curl -fsSL https://raw.githubusercontent.com/Damcore/pve-phoenix/main/vm-watchdog.logrotate \
        -o /etc/logrotate.d/vm-watchdog 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${YELLOW}[WARN]${NC}"
        echo -e "${YELLOW}[WARN]${NC} Failed to download logrotate config, logs won't auto-rotate"
    fi
fi

# Reload systemd
systemctl daemon-reload
echo -e "${GREEN}[OK]${NC} Systemd reloaded"

# Enable service
systemctl enable vm-watchdog
echo -e "${GREEN}[OK]${NC} Service enabled (will start on boot)"

# Restart service (starts if not running, restarts if already running)
systemctl restart vm-watchdog
echo -e "${GREEN}[OK]${NC} Service started/restarted"
echo ""

# Show status
sleep 1
if systemctl is-active --quiet vm-watchdog; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "✓ VM ${GREEN}$VMID${NC} (${VM_NAME}) is now monitored"
    echo ""
    echo -e "${YELLOW}Monitor & Control:${NC}"
    echo -e "  Logs:   ${BLUE}journalctl -u vm-watchdog -f${NC}"
    echo -e "  Pause:  ${BLUE}touch /etc/vm-watchdog/pause${NC}"
    echo -e "  Resume: ${BLUE}rm /etc/vm-watchdog/pause${NC}"
    echo ""
    echo -e "${YELLOW}Change VM or Add More:${NC}"
    echo -e "  Change VM ID:      Edit ${BLUE}/usr/local/bin/vm-watchdog.sh${NC} (line 6: VMID=$VMID)"
    echo -e "  Monitor more VMs:  Run installer again with different VMID"
    echo -e "  Example:           ${BLUE}VMID=101 curl -fsSL ... | sudo bash${NC}"
    echo ""
else
    echo -e "${RED}[FAIL] Service failed to start${NC}"
    echo "Check logs with: journalctl -u vm-watchdog -n 50"
    exit 1
fi
