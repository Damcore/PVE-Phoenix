# Troubleshooting Guide

This guide helps diagnose and fix common issues with VM Watchdog.

---

## VM not restarting after crash?

**Step-by-step diagnostic:**

```bash
# 1. Check if service is running
sudo systemctl status vm-watchdog

# 2. View recent logs for errors
sudo journalctl -u vm-watchdog -n 50

# 3. Check if paused
ls /etc/vm-watchdog/pause  # If exists, remove it

# 4. Check if disabled (hit daily limit)
cat /etc/vm-watchdog/config.conf | grep ENABLED

# 5. Verify VM exists and is accessible
qm status 444  # Replace 444 with your VM ID
```

**Common causes:**
- Service is stopped or crashed
- Pause file exists (`/etc/vm-watchdog/pause`) - remove it to resume
- Daily limit reached (ENABLED=false in config)
- VM ID doesn't match (check VMID in script)
- State file is corrupted (delete and restart service)

**Note:** If you previously paused, stopped the VM, and unpaused, the latest version handles this correctly—it won't restart because state tracking continued during pause. If you're on an older version and experience this, update your vm-watchdog.sh script.

---

## Service won't start?

**Diagnostic steps:**

```bash
# Check for errors in logs
sudo journalctl -u vm-watchdog -n 20

# Verify script is executable
ls -l /usr/local/bin/vm-watchdog.sh

# Check for syntax errors
bash -n /usr/local/bin/vm-watchdog.sh

# Manually test the script (Ctrl+C to stop)
sudo /usr/local/bin/vm-watchdog.sh
```

**Common causes:**
- Script not executable (`chmod +x` needed)
- Syntax errors in edited script
- Missing dependencies (Proxmox `qm` command)
- Permission issues

---

## Crash detection not working?

If the watchdog isn't detecting crashes or is restarting when it shouldn't:

**Reset state tracking:**

```bash
# Remove state file and restart
sudo rm /var/run/vm-watchdog-*.state
sudo systemctl restart vm-watchdog
```

**Verify state transitions:**

```bash
# Watch logs in real-time
sudo journalctl -u vm-watchdog -f

# In another terminal, test crash detection
qm stop 444  # Replace with your VM ID
```

You should see logs showing:
- "VM 444 crashed (was running, now stopped)"
- "Attempting to restart VM 444"
- "SUCCESS: VM 444 restarted"

**Important:** State tracking now works correctly during pause mode. If you pause, stop the VM, and unpause, the watchdog will NOT incorrectly restart the VM because it tracked the state change even while paused. This is expected behavior as of the latest version.

---

## Hit daily/hourly limit?

**Check current counters:**

```bash
cat /etc/vm-watchdog/config.conf
```

**Re-enable after daily limit:**

```bash
# Edit config file
sudo vim /etc/vm-watchdog/config.conf

# Change:
ENABLED=false

# To:
ENABLED=true

# Optionally reset counter:
DAILY_RESTARTS=0

# Save and exit, then restart the service:
sudo systemctl restart vm-watchdog
```

**Wait for automatic reset:**
- Hourly limit (5 restarts) resets after 1 hour
- Daily limit (20 restarts) resets at midnight

---

## Stop/Start watchdog temporarily

**For maintenance or testing:**

```bash
# Stop service
sudo systemctl stop vm-watchdog

# Do your maintenance...

# Start when ready
sudo systemctl start vm-watchdog
```

**Alternative: Use pause file (Recommended)**

```bash
# Pause monitoring (state tracking continues in background)
sudo touch /etc/vm-watchdog/pause

# Do your work (e.g., stop/start VM for maintenance)

# Resume monitoring (safe to unpause regardless of VM state)
sudo rm /etc/vm-watchdog/pause
```

**Note:** The pause file prevents restart actions but VM state tracking continues. This means you can safely remove the pause file at any time—even if the VM is stopped—without triggering a false crash detection. The watchdog tracks state changes continuously, preventing it from misinterpreting an intentional shutdown as a crash when you unpause.

---

## Logs showing errors?

**Common error messages:**

### "Could not get status for VM XXX. Does it exist?"
- VM ID in script doesn't match actual VM
- Edit `/usr/local/bin/vm-watchdog.sh` and update `VMID=XXX`
- Restart service: `sudo systemctl restart vm-watchdog`

### "Failed to restart VM XXX (qm start exit code: N)"
- VM is locked or in use
- Insufficient permissions
- Proxmox storage issues
- Check exit code meaning in Proxmox documentation
- Check Proxmox logs: `/var/log/pve/tasks/`

### "Watchdog disabled. Daily limit reached."
- This is normal behavior after hitting limit
- Re-enable in config.conf or wait until midnight

---

## View detailed logs

**Systemd journal (recommended):**

```bash
# Live logs
sudo journalctl -u vm-watchdog -f

# Last 100 lines
sudo journalctl -u vm-watchdog -n 100

# Logs from today
sudo journalctl -u vm-watchdog --since today

# Logs with timestamps
sudo journalctl -u vm-watchdog -o short-precise
```

**Log file:**

```bash
# View log file
sudo tail -f /var/log/vm-watchdog.log

# Search for errors
sudo grep ERROR /var/log/vm-watchdog.log

# Search for restarts
sudo grep SUCCESS /var/log/vm-watchdog.log
```

---

## Configuration issues?

**Reset to defaults:**

```bash
# Stop service
sudo systemctl stop vm-watchdog

# Remove config (will be recreated)
sudo rm /etc/vm-watchdog/config.conf

# Start service (creates fresh config)
sudo systemctl start vm-watchdog
```

**Check configuration values:**

```bash
# View runtime config
cat /etc/vm-watchdog/config.conf

# View script settings
grep -E "VMID|HOURLY|DAILY" /usr/local/bin/vm-watchdog.sh | head -10
```

---

## Still having issues?

**Gather diagnostic information:**

```bash
# Service status
sudo systemctl status vm-watchdog -l

# Recent logs
sudo journalctl -u vm-watchdog -n 50 --no-pager

# Configuration
cat /etc/vm-watchdog/config.conf

# Script info
ls -la /usr/local/bin/vm-watchdog.sh
head -20 /usr/local/bin/vm-watchdog.sh

# VM status
qm status 444  # Replace with your VM ID
```

Share this information when seeking help on GitHub Issues or forums.

---

## Need to reinstall?

If all else fails, reinstall from scratch:

```bash
# Uninstall completely
sudo systemctl stop vm-watchdog
sudo systemctl disable vm-watchdog
sudo rm /etc/systemd/system/vm-watchdog.service
sudo rm /usr/local/bin/vm-watchdog.sh
sudo rm -rf /etc/vm-watchdog
sudo rm /var/run/vm-watchdog-*.state
sudo systemctl daemon-reload

# Reinstall using interactive installer
git clone https://github.com/Damcore/pve-phoenix.git
cd pve-phoenix
sudo bash install.sh
```
