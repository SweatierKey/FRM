inspect_instances() {
    local instance
    local family
    local sysv
    local nm_info=""
    local nm_pid=""
    local nm_uptime=""

    build_selection "$@" || return $?

    for instance in "${SELECTED_INSTANCES[@]}"; do
        family="$(instance_family "$instance")"
        collect_status "$instance" false
        sysv="$(sysv_script_path "$instance" 2>/dev/null || true)"

        printf 'Instance: %s\n' "$instance"
        printf '  path:            %s\n' "$FRM_INSTANCES_DIR/$instance"
        printf '  family:          %s\n' "$family"
        printf '  state:           %s\n' "$STATUS_STATE"
        printf '  detail:          %s\n' "$STATUS_DETAIL"
        printf '  uptime:          %s\n' "${STATUS_UPTIME:-n/a}"
        printf '  started at:      %s\n' "${STATUS_STARTED_AT:-n/a}"
        printf '  status backend:  %s\n' "$STATUS_BACKEND"
        printf '  opmnctl:         %s\n' "$([[ -x "$FRM_INSTANCES_DIR/$instance/bin/opmnctl" ]] && printf yes || printf no)"
        printf '  systemd unit:    %s\n' "$(systemd_unit_exists "${instance}.service" && printf '%s' "${instance}.service" || printf none)"
        printf '  sysv script:     %s\n' "${sysv:-none}"
        if nm_info="$(instance_nodemanager_info "$instance" 2>/dev/null)"; then
            read -r nm_pid nm_uptime <<< "$nm_info"
            printf '  nodemanager:     pid=%s%s\n' "$nm_pid" "${nm_uptime:+ uptime=$nm_uptime}"
        else
            printf '  nodemanager:     not detected\n'
        fi
        printf '  start handler:   %s\n' "$(custom_handler_exists "${instance}_start" && printf yes || printf no)"
        printf '  stop handler:    %s\n' "$(custom_handler_exists "${instance}_stop" && printf yes || printf no)"
        printf '  status handler:  %s\n' "$(custom_handler_exists "${instance}_status" && printf yes || printf no)"
        printf '  configtest handler: %s\n' "$(custom_handler_exists "${instance}_configtest" && printf yes || printf no)"
        printf '\n'
    done
}

doctor() {
    local failures=0
    local cmd
    local instance
    local -a instances=()

    printf 'FRM doctor\n'
    printf '==========\n\n'
    printf 'version:          %s\n' "$FRM_VERSION"
    printf 'bash:             %s\n' "${BASH_VERSION:-unknown}"
    printf 'instances dir:    %s\n' "$FRM_INSTANCES_DIR"
    printf 'handlers file:    %s%s\n' "$FRM_HANDLERS_FILE" "$([[ -f "$FRM_HANDLERS_FILE" ]] && printf ' (loaded)' || printf ' (not present)')"
    printf 'color:            %s\n' "$FRM_COLOR"
    printf 'sudo mode:        %s\n' "$FRM_SUDO"
    printf 'OPMN mode:        %s\n' "$FRM_OPMN_MODE"
    printf 'on error:         %s\n' "$FRM_ON_ERROR"
    printf 'lifecycle summary: %s\n' "$FRM_LIFECYCLE_SUMMARY"
    printf 'config preflight: %s\n' "$FRM_PREFLIGHT_CONFIGTEST"
    printf 'wait:             %s\n' "$FRM_WAIT"
    printf 'timeout:          %ss\n' "$FRM_TIMEOUT"
    printf 'poll interval:    %ss\n' "$FRM_POLL_INTERVAL"
    printf '\nDependencies:\n'

    for cmd in bash awk ps grep sort sleep date systemctl flock; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  %-12s OK  %s\n' "$cmd" "$(command -v "$cmd")"
        else
            case "$cmd" in
                systemctl|flock)
                    printf '  %-12s OPTIONAL/MISSING\n' "$cmd"
                    ;;
                *)
                    printf '  %-12s MISSING\n' "$cmd"
                    failures=1
                    ;;
            esac
        fi
    done

    printf '\nDiscovery:\n'
    if validate_instances_dir; then
        mapfile -t instances < <(instance_list)
        printf '  detected:       %d\n' "${#instances[@]}"
        for instance in "${instances[@]}"; do
            collect_status "$instance" false
            printf '  %-22s %-8s backend=%s family=%s\n' \
                "$instance" "$STATUS_STATE" "$STATUS_BACKEND" "$(instance_family "$instance")"
        done
    else
        failures=1
    fi

    local stdout_real=false
    local stderr_real=false
    local stdout_color=false
    local stderr_color=false

    is_real_tty 1 && stdout_real=true
    is_real_tty 2 && stderr_real=true
    is_a_tty 1 && stdout_color=true
    is_a_tty 2 && stderr_color=true

    printf '\nTTY:\n'
    printf '  stdout real:    %s\n' "$stdout_real"
    printf '  stderr real:    %s\n' "$stderr_real"
    printf '  stdout color:   %s\n' "$stdout_color"
    printf '  stderr color:   %s\n' "$stderr_color"

    (( failures == 0 ))
}

watch_status() {
    local -a selectors=("$@")

    while :; do
        if bool_true "$FRM_WATCH_CLEAR" && is_real_tty 1; then
            printf '\033[H\033[2J'
        fi

        printf 'FRM watch - %s - interval %ss\n\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$FRM_WATCH_INTERVAL"
        status_instances "${selectors[@]}" || true
        sleep "$FRM_WATCH_INTERVAL"
    done
}

###############################################################################
