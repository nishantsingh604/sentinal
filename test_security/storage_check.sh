#!/bin/bash

check_storage() {

    if [[ ! -d "$AUDIT_DIR" ]]; then
        log_error "Audit directory does not exist: $AUDIT_DIR"
        return 1
    fi

    if [[ ! "${STORAGE_LIMIT_MB:-}" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Invalid storage limit: ${STORAGE_LIMIT_MB:-unset}"
        return 1
    fi

    local used_kb
    local limit_kb

    used_kb=$(du -sk "$AUDIT_DIR" 2>/dev/null | awk '{print $1}')

    if [[ ! "$used_kb" =~ ^[0-9]+$ ]]; then
        log_error "Unable to calculate audit directory size"
        return 1
    fi

    limit_kb=$((STORAGE_LIMIT_MB * 1024))

    if (( used_kb >= limit_kb )); then
        log_warning "Audit storage reached or exceeded ${STORAGE_LIMIT_MB} MB. Current usage: $((used_kb / 1024)) MB"
        echo "[WARNING] Audit storage limit reached: ${STORAGE_LIMIT_MB} MB" >&2
    else
        log_info "Audit storage is within limit. Current usage: $((used_kb / 1024)) MB"
    fi

    return 0
}
