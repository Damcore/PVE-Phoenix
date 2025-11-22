#!/bin/bash

# VM Watchdog Script for Proxmox
# Automatically restarts crashed VMs with rate limiting

VMID=444
CONFIG_FILE="/etc/vm-watchdog/config.conf"
LOG_FILE="/var/log/vm-watchdog.log"
STATE_FILE="/var/run/vm-watchdog-$VMID.state"
PAUSE_FILE="/etc/vm-watchdog/pause"

# Ensure config directory exists
mkdir -p "$(dirname "$CONFIG_FILE")"

# Initialize or repair config file
initialize_config() {
    echo "HOURLY_RESTARTS=0" > "$CONFIG_FILE"
    echo "DAILY_RESTARTS=0" >> "$CONFIG_FILE"
    echo "LAST_HOUR_RESET=$(date +%s)" >> "$CONFIG_FILE"
    echo "LAST_DAY_RESET=$(date +%Y-%m-%d)" >> "$CONFIG_FILE"
    echo "ENABLED=true" >> "$CONFIG_FILE"
}

if [[ ! -f "$CONFIG_FILE" ]]; then
    initialize_config
fi

# Load config with error handling
if ! source "$CONFIG_FILE" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Config file corrupted. Recreating..." | tee -a "$LOG_FILE"
    initialize_config
    source "$CONFIG_FILE"
fi

# Validate required variables are set
if [[ -z "$HOURLY_RESTARTS" ]] || [[ -z "$DAILY_RESTARTS" ]] || [[ -z "$LAST_HOUR_RESET" ]] || [[ -z "$LAST_DAY_RESET" ]] || [[ -z "$ENABLED" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Config file missing required variables. Recreating..." | tee -a "$LOG_FILE"
    initialize_config
    source "$CONFIG_FILE"
fi

# State tracking for logging (prevent spam)
LAST_LOGGED_STATE=""

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Save config function
save_config() {
    cat > "$CONFIG_FILE" <<EOF
HOURLY_RESTARTS=$HOURLY_RESTARTS
DAILY_RESTARTS=$DAILY_RESTARTS
LAST_HOUR_RESET=$LAST_HOUR_RESET
LAST_DAY_RESET=$LAST_DAY_RESET
ENABLED=$ENABLED
EOF
}

# Get previous VM state
get_previous_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "unknown"
    fi
}

# Save current VM state
save_state() {
    echo "$1" > "$STATE_FILE"
}

# Reset counters if needed
reset_counters_if_needed() {
    local current_time=$(date +%s)
    local current_date=$(date +%Y-%m-%d)
    local hour_diff=$(( (current_time - LAST_HOUR_RESET) / 3600 ))
    
    # Reset hourly counter (also reset if clock jumped backward)
    if [[ $hour_diff -ge 1 ]] || [[ $hour_diff -lt 0 ]]; then
        log "Resetting hourly counter (last reset: $(date -d @$LAST_HOUR_RESET '+%Y-%m-%d %H:%M:%S'))"
        HOURLY_RESTARTS=0
        LAST_HOUR_RESET=$current_time
        save_config
    fi
    
    # Reset daily counter
    if [[ "$current_date" != "$LAST_DAY_RESET" ]]; then
        log "New day detected. Resetting daily counter and re-enabling watchdog."
        DAILY_RESTARTS=0
        LAST_DAY_RESET=$current_date
        ENABLED=true
        save_config
    fi
}

# Check VM status
check_and_restart_vm() {
    # Get current VM status FIRST (before any early returns)
    # This ensures state file stays synchronized even when paused/disabled
    local vm_status=$(qm status "$VMID" 2>/dev/null | awk '{print $2}')

    if [[ -z "$vm_status" ]]; then
        log "ERROR: Could not get status for VM $VMID. Does it exist?"
        return
    fi

    # Get previous state
    local previous_state=$(get_previous_state)

    # Save current state immediately (keeps state file in sync during pause/disabled)
    save_state "$vm_status"

    # Check if watchdog is enabled
    if [[ "$ENABLED" != "true" ]]; then
        if [[ "$LAST_LOGGED_STATE" != "disabled" ]]; then
            log "Watchdog disabled. Daily limit reached. Edit $CONFIG_FILE and set ENABLED=true to re-enable."
            LAST_LOGGED_STATE="disabled"
        fi
        return
    fi

    # Check if manually paused
    if [[ -f "$PAUSE_FILE" ]]; then
        if [[ "$LAST_LOGGED_STATE" != "paused" ]]; then
            log "Watchdog paused. Remove $PAUSE_FILE to resume monitoring."
            LAST_LOGGED_STATE="paused"
        fi
        return
    fi

    # Reset logged state if we're active again
    if [[ "$LAST_LOGGED_STATE" == "disabled" || "$LAST_LOGGED_STATE" == "paused" ]]; then
        log "Watchdog resumed monitoring."
        LAST_LOGGED_STATE="active"
    fi
    
    # Only restart if VM was running before and is now stopped (unexpected stop/crash)
    if [[ "$previous_state" == "running" && "$vm_status" == "stopped" ]]; then
        log "VM $VMID crashed (was running, now stopped). Checking restart limits..."
        
        # Check limits
        if [[ $HOURLY_RESTARTS -ge 5 ]]; then
            log "WARNING: Hourly limit (5) reached. Waiting for next hour..."
            return
        fi

        if [[ $DAILY_RESTARTS -ge 20 ]]; then
            log "CRITICAL: Daily limit (20) reached. Disabling watchdog until manual reset."
            ENABLED=false
            save_config
            return
        fi

        # Attempt restart
        log "Attempting to restart VM $VMID (Hourly: $HOURLY_RESTARTS/5, Daily: $DAILY_RESTARTS/20)"

        qm start "$VMID" 2>&1 | tee -a "$LOG_FILE"
        local qm_exit_code=${PIPESTATUS[0]}

        if [[ $qm_exit_code -eq 0 ]]; then
            # Wait briefly and verify VM is actually running
            sleep 5
            local verify_status=$(qm status "$VMID" 2>/dev/null | awk '{print $2}')

            if [[ "$verify_status" == "running" ]]; then
                HOURLY_RESTARTS=$((HOURLY_RESTARTS + 1))
                DAILY_RESTARTS=$((DAILY_RESTARTS + 1))
                save_config
                save_state "running"
                log "SUCCESS: VM $VMID restarted and verified running. Total today: $DAILY_RESTARTS"
            else
                log "WARNING: VM $VMID start command succeeded but VM is not running (status: $verify_status)"
                save_state "$verify_status"
            fi
        else
            log "ERROR: Failed to restart VM $VMID (qm start exit code: $qm_exit_code)"
        fi
    fi
}

# Main monitoring loop
main() {
    log "VM Watchdog started for VM $VMID"
    
    while true; do
        reset_counters_if_needed
        check_and_restart_vm
        sleep 30  # Check every 30 seconds
    done
}

# Run main function
main
