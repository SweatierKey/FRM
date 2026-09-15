# Lifecycle backend resolution / execution
###############################################################################

systemctl_path() {
    local found=""
    local canonical=""

    found="$(command -v systemctl 2>/dev/null)" || return 1
    [[ -n "$found" ]] || return 1

    # Resolve /bin -> /usr/bin style symlinks when possible so the command path
    # matches canonical sudoers entries, while still respecting PATH-injected
    # test/mocked systemctl binaries.
    if command -v readlink >/dev/null 2>&1; then
        canonical="$(readlink -f "$found" 2>/dev/null || true)"
    fi

    printf '%s\n' "${canonical:-$found}"
}

sudo_allows_noninteractive() {
    local sudo_bin=""

    sudo_bin="$(command -v sudo 2>/dev/null)" || return 1
    [[ -n "$sudo_bin" ]] || return 1

    # Check the exact command, not `sudo -n true`.  Production sudoers often
    # grants NOPASSWD only for specific systemctl/init-script invocations.
    "$sudo_bin" -n -l "$@" >/dev/null 2>&1
}

opmn_process_types() {
    local opmnctl="$1"

    "$opmnctl" status 2>/dev/null |
        awk -F'|' '
            function trim(s) {
                gsub(/^[[:space:]]+/, "", s)
                gsub(/[[:space:]]+$/, "", s)
                return s
            }

            NF >= 4 {
                type = trim($2)
                if (type == "" || tolower(type) == "process-type" || type ~ /^-+$/) {
                    next
                }
                print type
            }
        '
}

opmn_instance_is_ohs_only() {
    local opmnctl="$1"
    local type=""
    local seen=false

    while IFS= read -r type; do
        [[ -n "$type" ]] || continue
        seen=true
        [[ "${type,,}" == "ohs" ]] || return 1
    done < <(opmn_process_types "$opmnctl")

    bool_true "$seen"
}

resolve_opmn_mode() {
    local instance="$1"
    local action="$2"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local mode="${OPMN_MODE_CACHE[$instance]:-}"

    OPMN_RESOLVED_MODE=""

    if [[ -n "$mode" ]]; then
        OPMN_RESOLVED_MODE="$mode"
        return 0
    fi

    case "$FRM_OPMN_MODE" in
        all|ohs)
            mode="$FRM_OPMN_MODE"
            ;;
        auto)
            # In auto mode we use the site-friendly startall/stopall path only
            # when the running OPMN instance can be proven to manage OHS only.
            # If OPMN is down, a standalone start stays conservative because
            # there is no live inventory proving that no other process type is
            # configured in this Oracle Instance.
            if opmn_is_running "$opmnctl" && opmn_instance_is_ohs_only "$opmnctl"; then
                mode="all"
            else
                mode="ohs"
            fi
            ;;
        *)
            log error "Invalid OPMN mode: $FRM_OPMN_MODE"
            return "$EX_GENERAL"
            ;;
    esac

    OPMN_MODE_CACHE["$instance"]="$mode"
    OPMN_RESOLVED_MODE="$mode"
    return 0
}

set_opmn_action_description() {
    local instance="$1"
    local action="$2"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local mode=""

    resolve_opmn_mode "$instance" "$action" || return $?
    mode="$OPMN_RESOLVED_MODE"

    case "$mode:$action" in
        all:stop) ACTION_DESCRIPTION="$opmnctl stopall" ;;
        all:start) ACTION_DESCRIPTION="$opmnctl startall" ;;
        ohs:stop) ACTION_DESCRIPTION="$opmnctl stopproc process-type=OHS" ;;
        ohs:start)
            if opmn_is_running "$opmnctl"; then
                ACTION_DESCRIPTION="$opmnctl startproc process-type=OHS"
            else
                ACTION_DESCRIPTION="$opmnctl start && $opmnctl startproc process-type=OHS"
            fi
            ;;
        *)
            return "$EX_GENERAL"
            ;;
    esac
}

resolve_action_backend() {
    local instance="$1"
    local action="$2"
    local handler="${instance}_${action}"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local unit="${instance}.service"
    local systemctl_bin=""
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
        set_opmn_action_description "$instance" "$action" || return $?
        return 0
    fi

    if systemd_unit_exists "$unit"; then
        systemctl_bin="$(systemctl_path)" || return 1
        ACTION_BACKEND="systemd"
        # Use the bare unit name.  Besides being accepted by systemctl, this
        # matches common command-specific sudoers rules such as:
        #   /usr/bin/systemctl stop ohs_foo
        ACTION_DESCRIPTION="$systemctl_bin $action $instance"
        return 0
    fi

    if sysv="$(sysv_script_path "$instance")"; then
        ACTION_BACKEND="sysv"
        ACTION_DESCRIPTION="$sysv $action"
        return 0
    fi

    return 1
}

is_effective_root() {
    [[ "$EUID" -eq 0 ]]
}

run_privileged() {
    local command_path="$1"
    local original_command="$1"
    shift

    # Resolve PATH commands to a canonical executable before checking sudoers.
    if [[ "$command_path" != /* ]]; then
        command_path="$(command -v "$command_path" 2>/dev/null)" || {
            log error "Command not found: $original_command"
            return "$EX_UNAVAILABLE"
        }
    fi

    if is_effective_root; then
        "$command_path" "$@"
        return $?
    fi

    case "$FRM_SUDO" in
        always)
            command -v sudo >/dev/null 2>&1 || {
                log error "sudo requested but not installed"
                return "$EX_UNAVAILABLE"
            }
            sudo "$command_path" "$@"
            ;;
        never)
            "$command_path" "$@"
            ;;
        auto)
            if sudo_allows_noninteractive "$command_path" "$@"; then
                sudo -n "$command_path" "$@"
            else
                "$command_path" "$@"
            fi
            ;;
        *)
            log error "Invalid sudo mode: $FRM_SUDO"
            return "$EX_GENERAL"
            ;;
    esac
}

opmn_is_running() {
    local opmnctl="$1"
    local output=""
    local rc=0

    output="$("$opmnctl" status 2>&1)"
    rc=$?

    if grep -qi 'opmn is not running' <<< "$output"; then
        return 1
    fi

    # A normal status response (including OHS Down) means the OPMN daemon is
    # reachable.  Preserve compatibility with older opmnctl variants whose
    # status command can return non-zero for component state reasons.
    (( rc == 0 )) && return 0
    grep -qi 'Processes in Instance:' <<< "$output" && return 0
    return 1
}

execute_opmn_action() {
    local instance="$1"
    local action="$2"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local mode=""

    resolve_opmn_mode "$instance" "$action" || return $?
    mode="$OPMN_RESOLVED_MODE"

    case "$mode:$action" in
        all:stop)
            "$opmnctl" stopall
            ;;
        all:start)
            "$opmnctl" startall
            ;;
        ohs:stop)
            "$opmnctl" stopproc process-type=OHS
            ;;
        ohs:start)
            if ! opmn_is_running "$opmnctl"; then
                log info "Starting OPMN for instance: $instance"
                "$opmnctl" start || return $?
            fi
            "$opmnctl" startproc process-type=OHS
            ;;
        *)
            log error "Unsupported OPMN lifecycle mode/action: $mode/$action"
            return "$EX_GENERAL"
            ;;
    esac
}

execute_action() {
    local instance="$1"
    local action="$2"
    local handler="${instance}_${action}"
    local systemctl_bin=""
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
            execute_opmn_action "$instance" "$action"
            ;;
        systemd)
            systemctl_bin="$(systemctl_path)" || return "$EX_UNAVAILABLE"
            run_privileged "$systemctl_bin" "$action" "$instance"
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
