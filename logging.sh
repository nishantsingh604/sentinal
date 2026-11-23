
#!/bin/bash
# CIS 341 - Fall 2026
# Project Logging Functions

# Write a message to the configured log file
_write_log() {
    local level="$1"
    local message="$2"
    local timestamp

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -z "${LOG_FILE:-}" ]]; then
        echo "[ERROR] LOG_FILE is not configured." >&2
        return 1
    fi

    # Create the log directory if needed
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    if ! mkdir -p "$log_dir"; then
        echo "[ERROR] Cannot create log directory: $log_dir" >&2
        return 1
    fi

    # Append the log entry
    if ! printf '[%s] [%s] %s\n' \
        "$timestamp" "$level" "$message" >> "$LOG_FILE"; then
        echo "[ERROR] Cannot write to log file: $LOG_FILE" >&2
        return 1
    fi
}

# Information message
log_info() {
    _write_log "INFO" "$1"
}

# Warning message
log_warning() {
    _write_log "WARNING" "$1"
}

# Short warning alias
log_warn() {
    log_warning "$1"
}

# Error message
log_error() {
    _write_log "ERROR" "$1"
}
