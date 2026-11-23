#!/bin/bash
SUCCESS=0
GENERIC_ERROR=1          
IDENTITY_VIOLATION=2
CONFIGURATION_MISSING=3
INVALID_WORKSPACE=4
DISK_CEILING_REACHED=5
LOG_UNWRITABLE=6
MODULE_MISSING=7
REPORT_FAILED=8

show_usage() {
    cat <<'EOF'
SYSTEM HEALTH MONITOR & SECURITY AUDITING DAEMON

USAGE:
  ./sysaudit.sh [OPTIONS]

OPTIONS:
  -h, --help                Display this help information
  --storage-limit NUMBER    Override storage limit in MB (replaces sysaudit.cfg value)
  --scan-interval NUMBER    Override scan interval in seconds (replaces sysaudit.cfg value)
  --daemon                  Run the scan loop continuously (used by sysaudit.service)
  --delegate USER           Grant USER read/write access to the audit workspace
  --revoke USER             Remove USER's delegated access
  --list-delegates          Show users who currently have delegated access

  With only --storage-limit / --scan-interval (no --daemon), one scan is
  performed and the program exits.

EXAMPLES:
  ./sysaudit.sh
  ./sysaudit.sh --help
  ./sysaudit.sh --storage-limit 50
  ./sysaudit.sh --scan-interval 30
  ./sysaudit.sh --storage-limit 50 --scan-interval 30
  ./sysaudit.sh --daemon
  ./sysaudit.sh --delegate auditor1
  ./sysaudit.sh --revoke auditor1
  ./sysaudit.sh --list-delegates

CONFIGURATION:
  File: sysaudit.cfg
  Format: KEY=VALUE (one setting per line, no spaces around =)
  Command-line options override the file for that run only.

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
  [2026-11-02 01:00:01] [INFO] Audit report saved: /course_project/audit/scan_20261102_010001.audit
  [2026-11-02 01:00:01] [INFO] Audit storage is within limit. Current usage: 2 MB
  [2026-11-02 01:00:02] [INFO] Next scan in 60 seconds
  [2026-11-02 01:00:03] [INFO] Archive count: 3
  [2026-11-02 01:00:03] [INFO] Largest archive: audit_01.tar.gz (2048 bytes)
  [2026-11-02 01:00:04] [WARNING] Audit storage reached or exceeded 100 MB. Current usage: 101 MB
  [2026-11-02 01:00:05] [ERROR] Configuration file missing

EXIT CODES:
  0  - Success
  1  - Generic error (invalid option or invalid configuration value)
  2  - Identity violation (user is not the authorized user)
  3  - Configuration file missing
  4  - Invalid workspace (missing, not a directory, or not writable)
  5  - Disk ceiling reached (storage limit hit during a single scan)
  6  - Log file cannot be written
  7  - Required script module missing
  8  - Audit report could not be written
  10 - Delegate user does not exist
  11 - Invalid delegate target (bad name, yourself, or root)
  12 - Failed to apply or revoke ACL
  13 - ACL tools (setfacl/getfacl) not installed
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

# Load modules
for module in logging.sh error_handler.sh security.sh storage_check.sh; do
    if [[ ! -r "$SCRIPT_DIR/$module" ]]; then
        echo "[ERROR] Required module missing: $SCRIPT_DIR/$module" >&2
        exit "$MODULE_MISSING"
    fi
    source "$SCRIPT_DIR/$module"
done

enforce_identity "$CONFIG_FILE"

install_error_traps

if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
    fatal_error "Configuration file missing or unreadable: $CONFIG_FILE" "$CONFIGURATION_MISSING"
fi

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" != *=* ]]; then
        fatal_error "Invalid configuration line: $line" "$GENERIC_ERROR"
    fi

    key="${line%%=*}"
    value="${line#*=}"

    case "$key" in
        AUDIT_DIR|ARCHIVE_DIR|LOG_FILE|RAW_FILE_EXTENSION|ARCHIVE_EXTENSION|SCAN_INTERVAL_SECONDS|STORAGE_LIMIT_MB|ARCHIVE_INTERVAL_DAYS|ARCHIVE_HOUR|RETENTION_DAYS|AUTHORIZED_USER)
            printf -v "$key" '%s' "$value"
            ;;
        *)
            fatal_error "Unknown configuration setting: $key" "$GENERIC_ERROR"
            ;;
    esac
done < "$CONFIG_FILE"

echo "[INFO] Configuration loaded successfully"

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
        fatal_error "Missing or empty configuration setting: $setting" "$GENERIC_ERROR"
    fi
done

ACTION=""
DELEGATE_USER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --storage-limit)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                fatal_error "--storage-limit requires a positive number" "$GENERIC_ERROR"
            fi
            STORAGE_LIMIT_MB="$2"
            shift 2
            ;;
        --scan-interval)
            if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                fatal_error "--scan-interval requires a positive number" "$GENERIC_ERROR"
            fi
            SCAN_INTERVAL_SECONDS="$2"
            shift 2
            ;;
        --daemon)
            ACTION="daemon"
            shift
            ;;
        --list-delegates)
            ACTION="list"
            shift
            ;;
        --delegate|--revoke)
            if [[ $# -lt 2 || -z "$2" ]]; then
                fatal_error "$1 requires a username" "$GENERIC_ERROR"
            fi
            ACTION="${1#--}"
            DELEGATE_USER="$2"
            shift 2
            ;;
        *)
            fatal_error "Unknown option: $1" "$GENERIC_ERROR"
            ;;
    esac
done

# Validate positive numeric settings
for setting in SCAN_INTERVAL_SECONDS STORAGE_LIMIT_MB ARCHIVE_INTERVAL_DAYS RETENTION_DAYS; do
    value="${!setting}"

    if [[ ! "$value" =~ ^[0-9]{1,9}$ || "$value" =~ ^0+$ ]]; then
        fatal_error "$setting must be a positive whole number" "$GENERIC_ERROR"
    fi
done

if [[ ! "$ARCHIVE_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
    fatal_error "ARCHIVE_HOUR must be between 0 and 23" "$GENERIC_ERROR"
fi

# ---------------- [M3] scanning helpers ----------------

prepare_runtime() {
    if [[ ! -d "$AUDIT_DIR" ]]; then
        fatal_error "Workspace missing or not a directory: $AUDIT_DIR" "$INVALID_WORKSPACE"
    fi
    if [[ ! -w "$AUDIT_DIR" ]]; then
        fatal_error "Workspace is not writable: $AUDIT_DIR" "$INVALID_WORKSPACE"
    fi
    if ! touch -- "$LOG_FILE" 2>/dev/null; then
        fatal_error "Cannot write to log file: $LOG_FILE" "$LOG_UNWRITABLE"
    fi
}

write_audit_report() {
    local stamp report
    stamp="$(date '+%Y%m%d_%H%M%S')"
    report="$AUDIT_DIR/scan_${stamp}${RAW_FILE_EXTENSION}"

    if ! {
        echo "SYSAUDIT HEALTH REPORT"
        echo "Generated : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host      : $(hostname 2>/dev/null || echo unknown)"
        echo "User      : $(id -un 2>/dev/null || echo unknown)"
        echo "Uptime    : $(uptime -p 2>/dev/null || echo unavailable)"
        echo "Load avg  : $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unavailable)"
        echo "Sessions  : $(who 2>/dev/null | wc -l)"
        echo
        echo "MEMORY (MB)"
        free -m 2>/dev/null || echo "  unavailable"
        echo
        echo "DISK (/)"
        df -h / 2>/dev/null || echo "  unavailable"
    } 2>/dev/null > "$report"; then
        rm -f -- "$report" 2>/dev/null
        log_error "Failed to write audit report: $report"
        return 1
    fi

    log_info "Audit report saved: $report"
    return 0
}

run_scan() {
    local rc=0
    log_info "Scan started"

    if ! write_audit_report; then
        handle_error "Scan failed: could not write audit report" "$REPORT_FAILED" || true
        rc="$REPORT_FAILED"
    fi

    if ! check_storage; then
        log_error "Storage check failed"
        (( rc == 0 )) && rc="$GENERIC_ERROR"
    fi

    if [[ "${STORAGE_LIMIT_EXCEEDED:-0}" == "1" ]] && (( rc == 0 )); then
        rc="$DISK_CEILING_REACHED"
    fi

    return "$rc"
}

case "$ACTION" in
    delegate) delegate_access "$DELEGATE_USER"; exit "$SUCCESS" ;;
    revoke)   revoke_access "$DELEGATE_USER";   exit "$SUCCESS" ;;
    list)     list_delegates;                   exit "$SUCCESS" ;;
    daemon)
        prepare_runtime
        trap 'log_info "Daemon stopping (signal received)"; exit 0' TERM INT
        log_info "Daemon started (scan interval ${SCAN_INTERVAL_SECONDS}s)"
        while true; do
            run_scan || true    
            log_info "Next scan in ${SCAN_INTERVAL_SECONDS} seconds"
            sleep "$SCAN_INTERVAL_SECONDS" & wait $!
        done
        ;;
    *)
        prepare_runtime
        run_scan
        scan_rc=$?
        log_info "Scan finished with exit code $scan_rc"
        (( scan_rc != 0 )) && ERROR_ALREADY_REPORTED=1
        exit "$scan_rc"
        ;;
esac