
#!/bin/bash

# CIS 341 - System Audit
# Member 3 - Logging Module

log_info() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if ! printf '[%s] [INFO] %s\n' "$timestamp" "$message" >> "$LOG_FILE"; then
        echo "[ERROR] Cannot write to log file: $LOG_FILE" >&2
        return 1
    fi
}

log_warning() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if ! printf '[%s] [WARNING] %s\n' "$timestamp" "$message" >> "$LOG_FILE"; then
        echo "[ERROR] Cannot write to log file: $LOG_FILE" >&2
        return 1
    fi
}

log_error() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if ! printf '[%s] [ERROR] %s\n' "$timestamp" "$message" >> "$LOG_FILE"; then
        echo "[ERROR] Cannot write to log file: $LOG_FILE" >&2
        return 1
    fi
}
