SANDBOX_USER=""

readonly EX_GENERIC_ERROR=1
readonly EX_IDENTITY_VIOLATION=2
readonly EX_CONFIGURATION_MISSING=3
readonly EX_INVALID_WORKSPACE=4
readonly EX_DELEGATE_USER_NOT_FOUND=10  
readonly EX_DELEGATE_INVALID_TARGET=11   
readonly EX_DELEGATE_ACL_FAILED=12       
readonly EX_ACL_TOOL_MISSING=13

_m4_log() {
    local level="$1"; shift
    local fn
    case "$level" in
        WARN|WARNING) fn=log_warning ;;
        ERROR)        fn=log_error ;;
        *)            fn=log_info ;;
    esac
    if declare -F "$fn" >/dev/null 2>&1 && [[ -n "${LOG_FILE:-}" ]]; then
        "$fn" "$*" 2>/dev/null || true
    fi
    return 0
}
_m4_die() {
    local code="$1"; shift
    printf '[ERROR] %s (exit code %s)\n' "$*" "$code" >&2
    _m4_log "ERROR" "$*"
    exit "$code"
}

enforce_identity() {
    local cfg="${1:-}" current

    if [[ -z "$cfg" || ! -r "$cfg" ]]; then
        printf '[ERROR] Configuration file missing or unreadable: %s (exit code %s)\n' \
            "$cfg" "$EX_CONFIGURATION_MISSING" >&2
        exit "$EX_CONFIGURATION_MISSING"
    fi
    SANDBOX_USER="$(grep -E '^AUTHORIZED_USER=' "$cfg" 2>/dev/null | tail -n1 \
                    | cut -d= -f2- | tr -d '[:space:]"'"'"'')"
    if [[ -z "$SANDBOX_USER" ]]; then
        printf '[ERROR] AUTHORIZED_USER not set in %s (exit code %s)\n' \
            "$cfg" "$EX_CONFIGURATION_MISSING" >&2
        exit "$EX_CONFIGURATION_MISSING"
    fi

    LOG_FILE="$(grep -E '^LOG_FILE=' "$cfg" 2>/dev/null | tail -n1 | cut -d= -f2-)"

    current="$(id -un 2>/dev/null)" || {
        printf '[ERROR] Unable to determine the effective user (exit code %s)\n' \
            "$EX_GENERIC_ERROR" >&2
        exit "$EX_GENERIC_ERROR"
    }

    if [[ "$current" != "$SANDBOX_USER" ]]; then
        printf '[ERROR] Security violation: user "%s" is not permitted. Only "%s" may run sysaudit. (exit code %s)\n' \
            "$current" "$SANDBOX_USER" "$EX_IDENTITY_VIOLATION" >&2
        command -v logger >/dev/null 2>&1 && \
            logger -t sysaudit -p auth.warning \
            "IDENTITY_VIOLATION: user '${current}' attempted to run sysaudit" 2>/dev/null
        _m4_log "ERROR" "IDENTITY_VIOLATION: user '${current}' attempted to run sysaudit"
        exit "$EX_IDENTITY_VIOLATION"
    fi
    _m4_log "INFO" "Identity check passed: running as '${current}'"
}


_m4_validate_target() {
    local target="$1" ws="${AUDIT_DIR:-}"

    [[ -n "$target" ]] || _m4_die "$EX_DELEGATE_INVALID_TARGET" "No username supplied for delegation"
    [[ "$target" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || \
        _m4_die "$EX_DELEGATE_INVALID_TARGET" "Invalid username format: '${target}'"
    [[ "$target" != "$(id -un)" ]] || \
        _m4_die "$EX_DELEGATE_INVALID_TARGET" "Cannot delegate to yourself ('${target}')"
    [[ "$target" != "root" ]] || \
        _m4_die "$EX_DELEGATE_INVALID_TARGET" "Delegation to root is refused"
    id "$target" >/dev/null 2>&1 || \
        _m4_die "$EX_DELEGATE_USER_NOT_FOUND" "Delegate user '${target}' does not exist on this system"
    [[ -n "$ws" && -d "$ws" ]] || \
        _m4_die "$EX_INVALID_WORKSPACE" "Workspace '${ws}' is missing or not a directory"
    command -v setfacl >/dev/null 2>&1 || \
        _m4_die "$EX_ACL_TOOL_MISSING" "setfacl not found (install package 'acl')"
}
_m4_parents() {  
    local mode="$1" target="$2" dir
    dir="$(dirname -- "${AUDIT_DIR%/}")"
    while [[ "$dir" != "/" && "$dir" != "." && -O "$dir" ]]; do
        if [[ "$mode" == "grant" ]]; then
            setfacl -m "u:${target}:--x" "$dir" 2>/dev/null || return 1
        else
            setfacl -x "u:${target}" "$dir" 2>/dev/null || return 1
        fi
        dir="$(dirname -- "$dir")"
    done
    return 0
}

delegate_access() {
    local target="${1:-}" ws="${AUDIT_DIR:-}"
    _m4_validate_target "$target"

   
    local me; me="$(id -un)"
    if ! find "$ws" -user "$me" -exec setfacl -m "u:${target}:rwX" {} + 2>/dev/null || \
       ! find "$ws" -type d -user "$me" -exec setfacl -d -m "u:${target}:rwX,u:${me}:rwX" {} + 2>/dev/null || \
       ! _m4_parents grant "$target"; then
        _m4_die "$EX_DELEGATE_ACL_FAILED" "Failed to apply ACL for '${target}' on '${ws}'"
    fi
    _m4_log "INFO" "Delegated rwX access on '${ws}' to user '${target}'"
    echo "[OK] Access to ${ws} delegated to '${target}'."
}

revoke_access() {
    local target="${1:-}" ws="${AUDIT_DIR:-}"
    _m4_validate_target "$target"
    local me; me="$(id -un)"
    if ! find "$ws" -user "$me" -exec setfacl -x "u:${target}" {} + 2>/dev/null || \
       ! find "$ws" -type d -user "$me" -exec setfacl -d -x "u:${target}" {} + 2>/dev/null || \
       ! _m4_parents revoke "$target"; then
        _m4_die "$EX_DELEGATE_ACL_FAILED" "Failed to revoke ACL for '${target}' on '${ws}'"
    fi
    _m4_log "INFO" "Revoked delegated access on '${ws}' from user '${target}'"
    echo "[OK] Access for '${target}' revoked."
}

list_delegates() {
    local ws="${AUDIT_DIR:-}"
    [[ -d "$ws" ]] || _m4_die "$EX_INVALID_WORKSPACE" "Workspace '${ws}' is missing or not a directory"
    command -v getfacl >/dev/null 2>&1 || _m4_die "$EX_ACL_TOOL_MISSING" "getfacl not found"
    getfacl -p "$ws" 2>/dev/null | grep '^user:[^:]\+:' || echo "(no delegates)"
    _m4_log "INFO" "Listed delegates for '${ws}'"
}