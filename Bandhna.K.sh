#!/bin/bash

compress_audit_files() {
    local raw_ext="${RAW_FILE_EXTENSION:-.audit}"
    local arc_ext="${ARCHIVE_EXTENSION:-.tar.gz}"
    local stamp archive file
    local -a files=()

    if [[ -z "${AUDIT_DIR:-}" || ! -d "$AUDIT_DIR" ]]; then
        log_error "Compression failed: audit directory missing: ${AUDIT_DIR:-unset}"
        return 1
    fi
    if [[ -z "${ARCHIVE_DIR:-}" ]]; then
        log_error "Compression failed: ARCHIVE_DIR is not set"
        return 1
    fi
    if ! mkdir -p -- "$ARCHIVE_DIR" 2>/dev/null; then
        log_error "Compression failed: cannot create archive directory: $ARCHIVE_DIR"
        return 1
    fi


    while IFS= read -r -d '' file; do
        files+=("$(basename -- "$file")")
    done < <(find "$AUDIT_DIR" -maxdepth 1 -type f -name "*${raw_ext}" -print0 2>/dev/null)

    if (( ${#files[@]} == 0 )); then
        log_info "No ${raw_ext} files found to compress in $AUDIT_DIR"
        return 0
    fi

    stamp="$(date '+%Y%m%d_%H%M%S')"
    archive="$ARCHIVE_DIR/audit_${stamp}${arc_ext}"

    # Avoid overwriting an archive created in the same second
    if [[ -e "$archive" ]]; then
        archive="$ARCHIVE_DIR/audit_${stamp}_$$${arc_ext}"
    fi

    if ! tar -czf "$archive" -C "$AUDIT_DIR" -- "${files[@]}" 2>/dev/null; then
        rm -f -- "$archive" 2>/dev/null
        log_error "Compression failed: tar could not create $archive"
        return 1
    fi

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        rm -f -- "$archive" 2>/dev/null
        log_error "Compression failed: archive verification failed: $archive"
        return 1
    fi

    local f removed=0
    for f in "${files[@]}"; do
        if rm -f -- "$AUDIT_DIR/$f" 2>/dev/null; then
            removed=$((removed + 1))
        else
            log_warning "Could not delete raw file after compression: $AUDIT_DIR/$f"
        fi
    done

    log_info "Compressed ${#files[@]} audit file(s) into $archive; removed $removed raw file(s)"
    return 0
}

delete_old_archives() {
    local arc_ext="${ARCHIVE_EXTENSION:-.tar.gz}"
    local days="${RETENTION_DAYS:-14}"
    local file deleted=0 failed=0

    if [[ ! "$days" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Cleanup failed: invalid RETENTION_DAYS: $days"
        return 1
    fi
    if [[ -z "${ARCHIVE_DIR:-}" || ! -d "$ARCHIVE_DIR" ]]; then
        log_error "Cleanup failed: archive directory missing: ${ARCHIVE_DIR:-unset}"
        return 1
    fi

    while IFS= read -r -d '' file; do
        if rm -f -- "$file" 2>/dev/null; then
            deleted=$((deleted + 1))
            log_info "Deleted expired archive (older than ${days} days): $file"
        else
            failed=$((failed + 1))
            log_error "Could not delete expired archive: $file"
        fi
    done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*${arc_ext}" -mtime +"$days" -print0 2>/dev/null)

    log_info "Archive cleanup finished: $deleted deleted, $failed failed"
    (( failed == 0 ))
}

show_archive_statistics() {
    local arc_ext="${ARCHIVE_EXTENSION:-.tar.gz}"
    local file size mtime count=0 max_size=-1 max_file=""

    if [[ -z "${ARCHIVE_DIR:-}" || ! -d "$ARCHIVE_DIR" ]]; then
        log_error "Statistics failed: archive directory missing: ${ARCHIVE_DIR:-unset}"
        return 1
    fi

    while IFS= read -r -d '' file; do
        count=$((count + 1))
        size="$(stat -c '%s' -- "$file" 2>/dev/null)" || continue
        if (( size > max_size )); then
            max_size="$size"
            max_file="$file"
        fi
    done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*${arc_ext}" -print0 2>/dev/null)

    if (( count == 0 )); then
        log_info "Archive statistics: total archives: 0"
        echo "[INFO] Archive statistics: total archives: 0"
        return 0
    fi

    mtime="$(stat -c '%y' -- "$max_file" 2>/dev/null)" || mtime="unknown"

    log_info "Archive statistics: total archives: $count"
    log_info "Archive statistics: largest archive: $(basename -- "$max_file")"
    log_info "Archive statistics: largest archive size: ${max_size} bytes"
    log_info "Archive statistics: largest archive modified: $mtime"

    echo "[INFO] Total archives: $count"
    echo "[INFO] Largest archive: $(basename -- "$max_file") (${max_size} bytes)"
    echo "[INFO] Last modified: $mtime"
    return 0
}