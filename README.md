# PVE Phoenix

![Bash](https://img.shields.io/badge/bash-5.0+-green.svg)
![Proxmox](https://img.shields.io/badge/proxmox-VE-orange.svg)

**Automatically restart crashed Proxmox VMs — rising from the ashes with intelligent rate limiting**

PVE Phoenix is a lightweight systemd service that monitors your Proxmox VMs and automatically restarts them when they stop running. It detects running→stopped transitions and restarts the VM. Use pause mode to prevent unwanted restarts during manual maintenance.

## Features

- **State Transition Detection** - Only restarts on running→stopped transitions (detects when a running VM stops)
- **Rate Limiting** - Prevents restart loops with hourly (5) and daily (20) limits
- **Interactive Setup** - User-friendly installer prompts for VM ID and configuration
- **Comprehensive Logging** - Track all restart events via journald and log files
- **Pause Mode** - Temporarily disable monitoring for maintenance (state tracking continues in background)
- **Auto-Reset** - Counters reset automatically (hourly/daily)
- **Auto-Disable** - Stops after hitting daily limit to prevent runaway restarts

## Quick Installation

**One-liner installation (uses defaults: VM 444, 5/hour, 20/day, 30s interval):**

```bash
curl -fsSL https://raw.githubusercontent.com/Damcore/pve-phoenix/main/install.sh | sudo bash
```

**Custom settings with environment variables:**

```bash
VMID=101 HOURLY_LIMIT=10 DAILY_LIMIT=50 CHECK_INTERVAL=60 \
  curl -fsSL https://raw.githubusercontent.com/Damcore/pve-phoenix/main/install.sh | sudo bash
```

**Interactive installation (clone for prompts):**

```bash
git clone https://github.com/Damcore/pve-phoenix.git
cd pve-phoenix
sudo bash install.sh
```

**Environment Variables:**
- `VMID` - VM ID to monitor (default: 444)
- `HOURLY_LIMIT` - Max restarts per hour (default: 5)
- `DAILY_LIMIT` - Max restarts per day (default: 20)
- `CHECK_INTERVAL` - Seconds between checks (default: 30)
- `SKIP_CONFIRM` - Set to 0 to prevent auto-installation (default: 1)

---

## Manual Installation

```bash
sudo cp vm-watchdog.sh /usr/local/bin/ && sudo chmod +x /usr/local/bin/vm-watchdog.sh
sudo cp vm-watchdog.service /etc/systemd/system/
sudo cp vm-watchdog.logrotate /etc/logrotate.d/vm-watchdog
sudo mkdir -p /etc/vm-watchdog
sudo systemctl daemon-reload && sudo systemctl enable --now vm-watchdog
```

> **Note:** Defaults to VM 444. Edit `/usr/local/bin/vm-watchdog.sh` to customize VMID and limits.

---

## How It Works

Checks VM status every 30 seconds (configurable). On running→stopped transitions, verifies rate limits and restarts the VM.

**Rate Limiting:**
- Hourly: 5 restarts (resets after 1 hour)
- Daily: 20 restarts (resets at midnight, auto-disables when exceeded)

**Important:** Cannot distinguish crashes from manual stops—use pause mode (`touch /etc/vm-watchdog/pause`) before manual shutdowns. State tracking remains synchronized even during pause mode, so you can safely unpause regardless of VM state without triggering false crash detection.

---

## Usage

**Monitor:**
```bash
sudo systemctl status vm-watchdog        # Service status
sudo journalctl -u vm-watchdog -f        # Live logs
cat /etc/vm-watchdog/config.conf         # View counters
```

**Pause for maintenance:**
```bash
sudo touch /etc/vm-watchdog/pause        # Pause (state tracking continues)
sudo rm /etc/vm-watchdog/pause           # Resume (safe to unpause anytime)
```

**Re-enable after daily limit:**
```bash
sudo vim /etc/vm-watchdog/config.conf    # Change ENABLED=false to true
sudo systemctl restart vm-watchdog        # Apply changes
```

**Test crash detection:**
```bash
qm stop 444 && sudo journalctl -u vm-watchdog -f
```

---

## Configuration

Edit `/usr/local/bin/vm-watchdog.sh`, then `sudo systemctl restart vm-watchdog`:

- **VMID** (line 6): Default 444
- **Hourly Limit** (line 145): Default 5
- **Daily Limit** (line 150): Default 20
- **Check Interval** (line 191): Default 30s

---

## File Locations

- `/usr/local/bin/vm-watchdog.sh` - Main script
- `/etc/systemd/system/vm-watchdog.service` - Service unit
- `/etc/vm-watchdog/config.conf` - Runtime state (counters, ENABLED flag)
- `/var/log/vm-watchdog.log` - Operation log (rotated weekly)
- `/var/run/vm-watchdog-$VMID.state` - Current VM state tracking for crash detection
- `/etc/vm-watchdog/pause` - Create to pause monitoring

---

## Uninstall

```bash
sudo systemctl stop vm-watchdog
sudo systemctl disable vm-watchdog
sudo rm /etc/systemd/system/vm-watchdog.service
sudo rm /usr/local/bin/vm-watchdog.sh
sudo rm -rf /etc/vm-watchdog
sudo rm /var/run/vm-watchdog-*.state
sudo systemctl daemon-reload
```

---

## Troubleshooting

Having issues? See the **[Troubleshooting Guide](TROUBLESHOOTING.md)** for detailed diagnostic steps.
