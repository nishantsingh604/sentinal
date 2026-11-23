

ERROR_ALREADY_REPORTED=0

handle_error() {
    local message="$1"
    local exit_code="${2:-1}"

    if [[ ! "$exit_code" =~ ^[1-9][0-9]*$ ]]; then
        exit_code=1
    fi

    echo "[ERROR] $message" >&2

    if declare -F log_error >/dev/null 2>&1; then
        log_error "$message" 2>/dev/null || true
    fi

    ERROR_ALREADY_REPORTED=1
    return "$exit_code"
}

fatal_error() {
    local message="$1"
    local exit_code="${2:-1}"

    handle_error "$message" "$exit_code"
    exit "$exit_code"
}

# this one catches any non-zero exit nobody reported yet
handle_exit() {
    local exit_code=$?

    if (( exit_code != 0 && ERROR_ALREADY_REPORTED == 0 )); then
        echo "[ERROR] Program stopped with exit code: $exit_code" >&2

        if declare -F log_error >/dev/null 2>&1; then
            log_error "Program stopped with exit code: $exit_code" 2>/dev/null || true
        fi
    fi

    ERROR_ALREADY_REPORTED=0
}

handle_signal() {
    local signal_name="$1"
    fatal_error "Program interrupted by $signal_name" 1
}

install_error_traps() {
    trap 'handle_exit' EXIT
    trap 'handle_signal SIGINT' INT
    trap 'handle_signal SIGTERM' TERM
}