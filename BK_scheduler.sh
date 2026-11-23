#!/bin/bash


set -u



SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"



if [[ ! -f "$SCRIPT_DIR/sysaudit.cfg" ]]; then
    echo "[ERROR] Configuration file not found."
    exit 1
fi

source "$SCRIPT_DIR/sysaudit.cfg"



if [[ ! -f "$SCRIPT_DIR/logging.sh" ]]; then
    echo "[ERROR] Logging script not found."
    exit 1
fi

source "$SCRIPT_DIR/logging.sh"



if [[ ! -f "$SCRIPT_DIR/Bandhna.K.sh" ]]; then
    echo "[ERROR] Bandhna.K.sh not found."
    log_error "Bandhna.K.sh not found."
    exit 1
fi

source "$SCRIPT_DIR/Bandhna.K.sh"



if [[ "${TEST_MODE:-0}" == "1" ]]; then
    AUDIT_DIR="$SCRIPT_DIR/test_audit/raw"
    ARCHIVE_DIR="$SCRIPT_DIR/test_audit/archive"
    LOG_FILE="$SCRIPT_DIR/member2_cron.log"
fi



if ! [[ "${ARCHIVE_INTERVAL_DAYS:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] Invalid archive interval."
    log_error "Invalid ARCHIVE_INTERVAL_DAYS setting."
    exit 1
fi

# ==========================================
# SCHEDULER STATE
# ==========================================

STATE_FILE="$SCRIPT_DIR/.last_archive_run"

TODAY=$(date +%s)
INTERVAL=$((ARCHIVE_INTERVAL_DAYS * 86400))

if [[ -f "$STATE_FILE" ]]; then

    LAST_RUN=$(cat "$STATE_FILE")

    if ! [[ "$LAST_RUN" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Invalid scheduler state file."
        log_error "Invalid scheduler state file."
        exit 1
    fi

else
    LAST_RUN=0
fi



if (( TODAY - LAST_RUN >= INTERVAL )); then

    echo "===================================="
    echo "   SCHEDULED AUDIT MAINTENANCE"
    echo "===================================="

    log_info "Scheduled audit maintenance started."

    # Requirement 3: Compress audit files
    echo "[INFO] Starting audit compression."

    if ! compress_audit_files; then
        echo "[ERROR] Compression failed."
        log_error "Audit compression failed."
        exit 1
    fi

    # Requirement 6: Delete old archives
    echo "[INFO] Starting archive cleanup."

    if ! delete_old_archives; then
        echo "[ERROR] Archive cleanup failed."
        log_error "Archive cleanup failed."
        exit 1
    fi

    # Requirement 7: Generate and log archive statistics
    echo "[INFO] Generating archive statistics."

    if ! show_archive_statistics; then
        echo "[ERROR] Statistics generation failed."
        log_error "Archive statistics generation failed."
        exit 1
    fi

    # Save successful maintenance execution time
    if ! date +%s > "$STATE_FILE"; then
        echo "[ERROR] Could not update scheduler state."
        log_error "Could not update scheduler state."
        exit 1
    fi

    log_info "Scheduled audit maintenance completed successfully."

    echo "[SUCCESS] All scheduled maintenance tasks completed."
    echo "===================================="

else

    REMAINING=$((INTERVAL - (TODAY - LAST_RUN)))

    echo "[INFO] Three-day interval has not passed."
    echo "[INFO] Remaining seconds: $REMAINING"

    log_info "Scheduled maintenance skipped. Remaining seconds: $REMAINING"

fi

exit 0