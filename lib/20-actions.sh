# Lifecycle backend resolution / execution
###############################################################################

resolve_action_backend() {
    local instance="$1"
    local action="$2"
    local handler="${instance}_${action}"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local unit="${instance}.service"
    local sysv=""

    ACTION_BACKEND="none"
    ACTION_DESCRIPTION=""

    if custom_handler_exists "$handler"; then
        ACTION_BACKEND="handler"
        ACTION_DESCRIPTION="$handler"
        return 0
    fi

    if [[ -x "$opmnctl" ]]; then
        ACTION_BACKEND="opmn"
        ACTION_DESCRIPTION="$opmnctl $([[ "$action" == stop ]] && printf stop || printf start)"
        return 0
    fi

    if systemd_unit_exists "$unit"; then
        ACTION_BACKEND="systemd"
        ACTION_DESCRIPTION="systemctl $action $unit"
        return 0
    fi

    if sysv="$(sysv_script_path "$instance")"; then
        ACTION_BACKEND="sysv"
        ACTION_DESCRIPTION="$sysv $action"
        return 0
    fi

    return 1
}

run_privileged() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
        return $?
    fi

    case "$FRM_SUDO" in
        always)
            command -v sudo >/dev/null 2>&1 || {
                log error "sudo requested but not installed"
                return "$EX_UNAVAILABLE"
            }
            sudo "$@"
            ;;
        never)
            "$@"
            ;;
        auto)
            if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
                sudo -n "$@"
            else
                "$@"
            fi
            ;;
        *)
            log error "Invalid sudo mode: $FRM_SUDO"
            return "$EX_GENERAL"
            ;;
    esac
}

execute_action() {
    local instance="$1"
    local action="$2"
    local handler="${instance}_${action}"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local unit="${instance}.service"
    local sysv=""

    resolve_action_backend "$instance" "$action" || {
        log error "No $action backend found for $instance"
        return "$EX_UNAVAILABLE"
    }

    if bool_true "$FRM_DRY_RUN"; then
        log info "DRY-RUN  $instance  $ACTION_BACKEND  $ACTION_DESCRIPTION"
        return 0
    fi

    case "$ACTION_BACKEND" in
        handler)
            "$handler"
            ;;
        opmn)
            if [[ "$action" == "stop" ]]; then
                "$opmnctl" stop
            else
                "$opmnctl" start
            fi
            ;;
        systemd)
            run_privileged systemctl "$action" "$unit"
            ;;
        sysv)
            sysv="$(sysv_script_path "$instance")" || return "$EX_UNAVAILABLE"
            run_privileged "$sysv" "$action"
            ;;
        *)
            return "$EX_UNAVAILABLE"
            ;;
    esac
}

wait_for_state() {
    local instance="$1"
    local wanted="$2"
    local timeout="${3:-$FRM_TIMEOUT}"
    local started="$SECONDS"
    local elapsed=0

    bool_true "$FRM_WAIT" || return 0

    while :; do
        collect_status "$instance" false

        case "$wanted" in
            RUNNING)
                [[ "$STATUS_STATE" == "RUNNING" ]] && return 0
                ;;
            DOWN)
                [[ "$STATUS_STATE" == "DOWN" ]] && return 0
                ;;
        esac

        elapsed=$(( SECONDS - started ))
        if (( elapsed >= timeout )); then
            log error "Timeout waiting for $instance to become $wanted (last=$STATUS_STATE)"
            return "$EX_STATE"
        fi

        sleep "$FRM_POLL_INTERVAL"
    done
}

###############################################################################
# Lifecycle confirmations
###############################################################################

ask_confirmation() {
    local prompt="$1"
    local answer=""

    bool_true "$FRM_DRY_RUN" && return 0
    bool_true "$FRM_ASSUME_YES" && return 0

    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
        log error "Confirmation requested but no interactive terminal is available; use --yes for non-interactive execution"
        return "$EX_CANCELLED"
    fi

    printf '%s [y/N] ' "$prompt" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""

    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return "$EX_CANCELLED" ;;
    esac
}

confirm_lifecycle_batch() {
    local action="$1"
    shift
    local count="$#"

    bool_true "$FRM_DRY_RUN" && return 0
    bool_true "$FRM_ASSUME_YES" && return 0
    bool_true "$FRM_CONFIRM" || return 0

    ask_confirmation "Proceed with $action on $count selected instance(s)?"
}

confirm_lifecycle_instance() {
    local action="$1"
    local instance="$2"
    local index="$3"
    local total="$4"

    bool_true "$FRM_DRY_RUN" && return 0
    bool_true "$FRM_ASSUME_YES" && return 0
    bool_true "$FRM_CONFIRM_EACH" || return 0

    ask_confirmation "[$index/$total] Proceed with $action on $instance?"
}

acquire_lifecycle_lock() {
    command -v flock >/dev/null 2>&1 || {
        log warning "flock not available; lifecycle concurrency protection disabled"
        return 0
    }

    exec 9>"$FRM_LOCK_FILE"
    if ! flock -n 9; then
        log error "Another FRM lifecycle operation holds lock: $FRM_LOCK_FILE"
        return "$EX_LOCKED"
    fi
}

start_one() {
    local instance="$1"

    collect_status "$instance" false
    if [[ "$STATUS_STATE" == "RUNNING" ]]; then
        log success "Starting instance: $instance (already RUNNING)"
        return 0
    fi

    log start "Starting instance: $instance"
    execute_action "$instance" start || return $?

    if ! bool_true "$FRM_DRY_RUN"; then
        wait_for_state "$instance" RUNNING || return $?
        collect_status "$instance" false
        log success "$instance is RUNNING${STATUS_PID:+ pid=$STATUS_PID}"
    fi
}

stop_one() {
    local instance="$1"

    collect_status "$instance" false
    if [[ "$STATUS_STATE" == "DOWN" ]]; then
        log success "Stopping instance: $instance (already DOWN)"
        return 0
    fi

    log shutdown "Stopping instance: $instance"
    execute_action "$instance" stop || return $?

    if ! bool_true "$FRM_DRY_RUN"; then
        wait_for_state "$instance" DOWN || return $?
        log success "$instance is DOWN"
    fi
}

###############################################################################
# Command implementations
###############################################################################
