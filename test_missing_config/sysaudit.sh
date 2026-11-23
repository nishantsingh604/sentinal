#!/bin/bash

# CIS 341 - System Administration
# System Health Monitor & Security Auditing Daemon
# Main Script#
# Exit codes
SUCCESS=0
GENERIC_ERROR=1
IDENTITY_VIOLATION=2
CONFIGURATION_MISSING=3
INVALID_WORKSPACE=4
DISK_CEILING_REACHED=5

show_usage() {
    cat <<'EOF'
SYSTEM HEALTH MONITOR & SECURITY AUDITING DAEMON

USAGE:
  ./sysaudit.sh [OPTIONS]

OPTIONS:
  -h, --help               Display detailed help information
  --storage-limit NUMBER    Override storage limit in MB
  --scan-interval NUMBER    Override scan interval in seconds
EXAMPLES:
  ./sysaudit.sh
  ./sysaudit.sh --help
  ./sysaudit.sh --storage-limit 50
  ./sysaudit.sh --scan-interval 30
  ./sysaudit.sh --storage-limit 50 --scan-interval 30
CONFIGURATION:
  File: sysaudit.cfg
  Format: KEY=VALUE (one setting per line)

  AUDIT_DIR              Folder containing audit reports
  ARCHIVE_DIR            Folder containing compressed archives
  LOG_FILE               Daemon activity log file
  RAW_FILE_EXTENSION     Extension for raw audit reports
  ARCHIVE_EXTENSION      Extension for compressed archives
  SCAN_INTERVAL_SECONDS  Time between scans in seconds
  STORAGE_LIMIT_MB       Maximum storage allowed in MB
  ARCHIVE_INTERVAL_DAYS  Number of days between archive runs
  ARCHIVE_HOUR           Hour when archiving starts (0-23)
  RETENTION_DAYS         Number of days to keep archives
  AUTHORIZED_USER        Linux account allowed to run the program

SAMPLE OUTPUTS:
  [2026-11-02 01:00:00] [INFO] Scan started
  [2026-11-02 01:00:01] [INFO] Audit report saved
  [2026-11-02 01:00:02] [INFO] Next scan in 60 seconds
  [2026-11-02 01:00:03] [INFO] Archive count: 3
  [2026-11-02 01:00:03] [INFO] Largest archive: audit_01.tar.gz (2048 bytes)
  [2026-11-02 01:00:04] [WARN] Audit storage exceeded 100 MB
  [2026-11-02 01:00:05] [ERROR] Configuration file missing
EXIT CODES:
  0 - Success
  1 - Generic error
  2 - Identity violation
  3 - Configuration file missing
  4 - Invalid workspace
  5 - Disk ceiling reached
EOF
}

# Display help when no arguments are provided
# or when -h / --help is used.
if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_usage
    exit "$SUCCESS"
fi
# Locate the configuration file beside this script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || {
    echo "[ERROR] Cannot locate script directory" >&2
    exit "$GENERIC_ERROR"
}

CONFIG_FILE="$SCRIPT_DIR/sysaudit.cfg"

# Check whether the configuration file exists and is readable
if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
    echo "[ERROR] Configuration file missing or unreadable: $CONFIG_FILE" >&2
    exit "$CONFIGURATION_MISSING"
fi

# Read configuration safely without executing it as a script
while IFS= read -r line || [[ -n "$line" ]]; do
    # Ignore empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Check the key=value format
    if [[ "$line" != *=* ]]; then
        echo "[ERROR] Invalid configuration line: $line" >&2
        exit "$GENERIC_ERROR"
    fi

    key="${line%%=*}"
    value="${line#*=}"

    # Accept only known configuration settings
    case "$key" in
        AUDIT_DIR|ARCHIVE_DIR|LOG_FILE|RAW_FILE_EXTENSION|ARCHIVE_EXTENSION|SCAN_INTERVAL_SECONDS|STORAGE_LIMIT_MB|ARCHIVE_INTERVAL_DAYS|ARCHIVE_HOUR|RETENTION_DAYS|AUTHORIZED_USER)
            printf -v "$key" '%s' "$value"
            ;;
        *)
            echo "[ERROR] Unknown configuration setting: $key" >&2
            exit "$GENERIC_ERROR"
            ;;
    esac
done < "$CONFIG_FILE"

echo "[INFO] Configuration loaded successfully"

# Check required configuration settings
required_settings=(
    AUDIT_DIR
    ARCHIVE_DIR
    LOG_FILE
    RAW_FILE_EXTENSION
    ARCHIVE_EXTENSION
    SCAN_INTERVAL_SECONDS
    STORAGE_LIMIT_MB
    ARCHIVE_INTERVAL_DAYS
    ARCHIVE_HOUR
    RETENTION_DAYS
    AUTHORIZED_USER
)

for setting in "${required_settings[@]}"; do
    if [[ -z "${!setting:-}" ]]; then
        echo "[ERROR] Missing or empty configuration setting: $setting" >&2
        exit "$GENERIC_ERROR"
    fi
done

# Apply command-line options after loading configuration
while [[ $# -gt 0 ]]; do
    case "$1" in
        --storage-limit)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "[ERROR] --storage-limit requires a positive number" >&2
                exit "$GENERIC_ERROR"
            fi
            STORAGE_LIMIT_MB="$2"
            shift 2
            ;;
        --scan-interval)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "[ERROR] --scan-interval requires a positive number" >&2
                exit "$GENERIC_ERROR"
            fi
            SCAN_INTERVAL_SECONDS="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown option: $1" >&2
            exit "$GENERIC_ERROR"
            ;;
    esac
done
# Validate positive numeric settings
for setting in SCAN_INTERVAL_SECONDS STORAGE_LIMIT_MB ARCHIVE_INTERVAL_DAYS RETENTION_DAYS; do
    value="${!setting}"

if [[ ! "$value" =~ ^[0-9]{1,9}$ || "$value" =~ ^0+$ ]]; then
        echo "[ERROR] $setting must be a positive whole number" >&2
        exit "$GENERIC_ERROR"
    fi
done

# Archive hour must be between 0 and 23
if [[ ! "$ARCHIVE_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
    echo "[ERROR] ARCHIVE_HOUR must be between 0 and 23" >&2
    exit "$GENERIC_ERROR"
fi
