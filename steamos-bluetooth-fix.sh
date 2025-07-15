#!/bin/bash

# Configuration
readonly INTERVAL=5                # seconds between checks
readonly MAX_TIME=600              # maximum time to run in seconds (10 minutes)
readonly STEAM_CHECK_INTERVAL=1    # seconds between Steam checks
readonly STEAM_WAIT_TIME=10        # seconds to wait after Steam is detected
readonly SCRIPT_NAME="steamos_bluetooth_fix"

# Global variables
elapsed=0
commands_available=()

# Logging function with error handling
log_message() {
    local level="$1"
    local message="$2"
    
    # Try logger first, fallback to echo
    if command -v logger >/dev/null 2>&1; then
        logger -t "$SCRIPT_NAME" "[$level] $message" || echo "[$level] $message" >&2
    else
        echo "[$level] $message" >&2
    fi
}

# Check and cache available commands
check_commands() {
    local cmd
    for cmd in bluetoothctl dbus-send rfkill; do
        if command -v "$cmd" >/dev/null 2>&1; then
            commands_available+=("$cmd")
        fi
    done
    
    if [ ${#commands_available[@]} -eq 0 ]; then
        log_message "ERROR" "No Bluetooth management commands available (bluetoothctl, dbus-send, rfkill)"
        exit 1
    fi
    
    log_message "INFO" "Available commands: ${commands_available[*]}"
}

# Validate configuration
validate_config() {
    if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
        log_message "ERROR" "Invalid INTERVAL value: $INTERVAL"
        exit 1
    fi
    
    if ! [[ "$MAX_TIME" =~ ^[0-9]+$ ]] || [ "$MAX_TIME" -lt 1 ]; then
        log_message "ERROR" "Invalid MAX_TIME value: $MAX_TIME"
        exit 1
    fi
    
    if ! [[ "$STEAM_CHECK_INTERVAL" =~ ^[0-9]+$ ]] || [ "$STEAM_CHECK_INTERVAL" -lt 1 ]; then
        log_message "ERROR" "Invalid STEAM_CHECK_INTERVAL value: $STEAM_CHECK_INTERVAL"
        exit 1
    fi
    
    if ! [[ "$STEAM_WAIT_TIME" =~ ^[0-9]+$ ]] || [ "$STEAM_WAIT_TIME" -lt 1 ]; then
        log_message "ERROR" "Invalid STEAM_WAIT_TIME value: $STEAM_WAIT_TIME"
        exit 1
    fi
}

# Check if Steam is running with -steamos3 flag
is_steam_running() {
    if pgrep -f "steam.*-steamos3" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Wait for Steam to be running with -steamos3 flag
wait_for_steam() {
    log_message "INFO" "Waiting for Steam to start with -steamos3 flag..."
    
    while [ "$elapsed" -lt "$MAX_TIME" ]; do
        if is_steam_running; then
            log_message "INFO" "Steam detected with -steamos3 flag at ${elapsed}s"
            log_message "INFO" "Waiting ${STEAM_WAIT_TIME} seconds for Steam to initialize..."
            
            # Wait for Steam to initialize, but respect MAX_TIME
            local remaining_time=$((MAX_TIME - elapsed))
            local wait_time=$((STEAM_WAIT_TIME < remaining_time ? STEAM_WAIT_TIME : remaining_time))
            
            sleep "$wait_time"
            elapsed=$((elapsed + wait_time))
            
            if [ "$elapsed" -ge "$MAX_TIME" ]; then
                log_message "ERROR" "Maximum time reached while waiting for Steam initialization"
                exit 1
            fi
            
            log_message "INFO" "Steam initialization wait complete, proceeding with Bluetooth fix"
            return 0
        fi
        
        sleep "$STEAM_CHECK_INTERVAL"
        elapsed=$((elapsed + STEAM_CHECK_INTERVAL))
    done
    
    log_message "ERROR" "Maximum time reached while waiting for Steam to start"
    exit 1
}

# Check if Bluetooth is already enabled
is_bluetooth_enabled() {
    # Try multiple methods to check status
    local powered
    
    # Method 1: bluetoothctl
    if [[ " ${commands_available[*]} " == *" bluetoothctl "* ]]; then
        powered=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
        if [[ "$powered" == "yes" ]]; then
            return 0
        fi
    fi
    
    # Method 2: dbus
    if [[ " ${commands_available[*]} " == *" dbus-send "* ]]; then
        local adapter
        adapter=$(dbus-send --system --dest=org.bluez --print-reply / org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | grep -m1 -o '/org/bluez/hci[0-9]*')
        if [[ -n "$adapter" ]]; then
            powered=$(dbus-send --system --print-reply --dest=org.bluez "$adapter" org.freedesktop.DBus.Properties.Get string:"org.bluez.Adapter1" string:"Powered" 2>/dev/null | grep "boolean" | awk '{print $2}')
            if [[ "$powered" == "true" ]]; then
                return 0
            fi
        fi
    fi
    
    # Method 3: rfkill
    if [[ " ${commands_available[*]} " == *" rfkill "* ]]; then
        if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"; then
            if rfkill list bluetooth 2>/dev/null | grep -q "Hard blocked: no"; then
                return 0
            fi
        fi
    fi
    
    return 1
}

enable_bluetooth_bluetoothctl() {
    local powered
    
    powered=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    case "$powered" in
        "yes")
            return 0
            ;;
        "no")
            if bluetoothctl power on >/dev/null 2>&1; then
                log_message "INFO" "Bluetooth enabled via bluetoothctl"
                return 0
            else
                log_message "WARN" "Failed to enable Bluetooth via bluetoothctl"
                return 1
            fi
            ;;
        *)
            log_message "WARN" "Could not determine Bluetooth status via bluetoothctl"
            return 2
            ;;
    esac
}

enable_bluetooth_dbus() {
    local adapter powered
    
    # Securely discover adapter name
    adapter=$(dbus-send --system --dest=org.bluez --print-reply / org.freedesktop.DBus.ObjectManager.GetManagedObjects 2>/dev/null | grep -m1 -o '/org/bluez/hci[0-9]*')
    
    if [[ -z "$adapter" ]]; then
        log_message "WARN" "No Bluetooth adapter found via dbus"
        return 2
    fi
    
    # Validate adapter path to prevent injection
    if [[ ! "$adapter" =~ ^/org/bluez/hci[0-9]+$ ]]; then
        log_message "WARN" "Invalid adapter path: $adapter"
        return 2
    fi
    
    powered=$(dbus-send --system --print-reply --dest=org.bluez "$adapter" org.freedesktop.DBus.Properties.Get string:"org.bluez.Adapter1" string:"Powered" 2>/dev/null | grep "boolean" | awk '{print $2}')
    
    case "$powered" in
        "true")
            return 0
            ;;
        "false")
            if dbus-send --system --dest=org.bluez "$adapter" org.freedesktop.DBus.Properties.Set string:"org.bluez.Adapter1" string:"Powered" variant:boolean:true >/dev/null 2>&1; then
                log_message "INFO" "Bluetooth enabled via dbus"
                return 0
            else
                log_message "WARN" "Failed to enable Bluetooth via dbus"
                return 1
            fi
            ;;
        *)
            log_message "WARN" "Could not determine Bluetooth status via dbus"
            return 2
            ;;
    esac
}

enable_bluetooth_rfkill() {
    local bluetooth_info soft_blocked hard_blocked
    
    # Get bluetooth rfkill info once
    bluetooth_info=$(rfkill list bluetooth 2>/dev/null)
    if [[ -z "$bluetooth_info" ]]; then
        log_message "WARN" "No Bluetooth devices found via rfkill"
        return 2
    fi
    
    # Check blocking status
    soft_blocked=$(echo "$bluetooth_info" | grep -q "Soft blocked: yes" && echo "yes" || echo "no")
    hard_blocked=$(echo "$bluetooth_info" | grep -q "Hard blocked: yes" && echo "yes" || echo "no")
    
    # If hard blocked, can't enable
    if [[ "$hard_blocked" == "yes" ]]; then
        log_message "WARN" "Bluetooth is hard blocked and cannot be enabled"
        return 2
    fi
    
    # If soft blocked, try to unblock
    if [[ "$soft_blocked" == "yes" ]]; then
        if rfkill unblock bluetooth 2>/dev/null; then
            log_message "INFO" "Bluetooth enabled via rfkill"
            return 0
        else
            log_message "WARN" "Failed to enable Bluetooth via rfkill"
            return 1
        fi
    fi
    
    # Not blocked, should be enabled
    return 0
}

# Main execution
main() {
    log_message "INFO" "Starting SteamOS Bluetooth fix script"
    
    # Validate configuration
    validate_config
    
    # Check available commands
    check_commands
    
    # Wait for Steam to be running with -steamos3 flag
    wait_for_steam
    
    # Quick check if already enabled
    if is_bluetooth_enabled; then
        log_message "INFO" "Bluetooth is already enabled"
        exit 0
    fi
    
    # Main loop
    while [ "$elapsed" -lt "$MAX_TIME" ]; do
        log_message "INFO" "Attempt at ${elapsed}s - trying to enable Bluetooth"
        
        # Try each available method
        for cmd in "${commands_available[@]}"; do
            case "$cmd" in
                "bluetoothctl")
                    enable_bluetooth_bluetoothctl
                    result=$?
                    ;;
                "dbus-send")
                    enable_bluetooth_dbus
                    result=$?
                    ;;
                "rfkill")
                    enable_bluetooth_rfkill
                    result=$?
                    ;;
                *)
                    continue
                    ;;
            esac
            
            case $result in
                0)
                    log_message "INFO" "Bluetooth successfully enabled via $cmd"
                    exit 0
                    ;;
                1)
                    log_message "WARN" "$cmd failed to enable Bluetooth"
                    ;;
                2)
                    log_message "WARN" "$cmd cannot be used to enable Bluetooth"
                    ;;
            esac
        done
        
        # Wait before retry
        sleep "$INTERVAL"
        elapsed=$((elapsed + INTERVAL))
    done
    
    log_message "ERROR" "Failed to enable Bluetooth after ${MAX_TIME}s using all available methods"
    exit 1
}

# Run main function
main "$@"