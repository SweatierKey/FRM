list_instances() {
    local instance
    local family
    local backend

    build_selection "$@" || return $?

    if [[ "$FRM_LIST_FORMAT" == "json" ]]; then
        printf '['
    fi

    local first=true
    for instance in "${SELECTED_INSTANCES[@]}"; do
        family="$(instance_family "$instance")"

        # A plain `frm list` is discovery-only and must not invoke runtime
        # status backends. Long/JSON output includes backend information and
        # therefore performs status resolution.
        backend=""
        if bool_true "$FRM_LIST_LONG" || [[ "$FRM_LIST_FORMAT" == "json" ]]; then
            collect_status "$instance" false
            backend="$STATUS_BACKEND"
        fi

        case "$FRM_LIST_FORMAT" in
            json)
                "$first" || printf ','
                printf '{"instance":"%s","family":"%s","status_backend":"%s","path":"%s"}' \
                    "$(json_escape "$instance")" \
                    "$(json_escape "$family")" \
                    "$(json_escape "$backend")" \
                    "$(json_escape "$FRM_INSTANCES_DIR/$instance")"
                first=false
                ;;
            *)
                if bool_true "$FRM_LIST_LONG"; then
                    printf '%-24s %-12s %-10s %s\n' \
                        "$instance" "$family" "$backend" "$FRM_INSTANCES_DIR/$instance"
                else
                    printf '%s\n' "$instance"
                fi
                ;;
        esac
    done

    if [[ "$FRM_LIST_FORMAT" == "json" ]]; then
        printf ']\n'
    fi
}

status_instances() {
    local instance
    local bad=0
    local running=0
    local down=0
    local warning=0
    local unknown=0
    local first=true

    build_selection "$@" || return $?
    log debug "Checking status of ${#SELECTED_INSTANCES[@]} selected instance(s)"

    [[ "$FRM_STATUS_FORMAT" == "json" ]] && printf '['
    [[ "$FRM_STATUS_FORMAT" == "tsv" ]] && printf 'instance\tstate\tbackend\tpid\thttpd_count\tdetail\n'

    for instance in "${SELECTED_INSTANCES[@]}"; do
        collect_status "$instance" "$FRM_VERBOSE_STATUS"

        case "$STATUS_STATE" in
            RUNNING) ((running++)) ;;
            DOWN) ((down++)); bad=1 ;;
            WARNING) ((warning++)); bad=1 ;;
            *) ((unknown++)); bad=1 ;;
        esac

        case "$FRM_STATUS_FORMAT" in
            table)
                if ! bool_true "$FRM_VERBOSE_STATUS" || ! bool_true "$FRM_DEBUG"; then
                    print_status_table_row "$instance"
                fi
                ;;
            tsv)
                print_status_tsv_row "$instance"
                ;;
            json)
                "$first" || printf ','
                print_status_json_object "$instance"
                first=false
                ;;
        esac
    done

    [[ "$FRM_STATUS_FORMAT" == "json" ]] && printf ']\n'

    if bool_true "$FRM_STATUS_SUMMARY" && [[ "$FRM_STATUS_FORMAT" == "table" ]]; then
        printf '\n'
        printf 'Summary: total=%d running=%d down=%d warning=%d unknown=%d\n' \
            "${#SELECTED_INSTANCES[@]}" "$running" "$down" "$warning" "$unknown"
    fi

    (( bad == 0 )) && return 0
    return "$EX_STATE"
}

start_instances() {
    local instance
    local rc=0
    local action_rc=0
    local index=0
    local total=0

    build_selection "$@" || return $?
    if (( ${#SELECTED_INSTANCES[@]} == 0 )); then
        log info "No selected instances match the requested state filter; nothing to do"
        return 0
    fi
    acquire_lifecycle_lock || return $?
    confirm_lifecycle_batch start "${SELECTED_INSTANCES[@]}" || return $?

    total=${#SELECTED_INSTANCES[@]}
    for instance in "${SELECTED_INSTANCES[@]}"; do
        index=$((index + 1))
        if ! confirm_lifecycle_instance start "$instance" "$index" "$total"; then
            log warning "Start cancelled before instance: $instance"
            return "$EX_CANCELLED"
        fi

        start_one "$instance"
        action_rc=$?
        if (( action_rc > rc )); then
            rc="$action_rc"
        fi
    done

    return "$rc"
}

stop_instances() {
    local instance
    local rc=0
    local action_rc=0
    local index=0
    local total=0

    build_selection "$@" || return $?
    if (( ${#SELECTED_INSTANCES[@]} == 0 )); then
        log info "No selected instances match the requested state filter; nothing to do"
        return 0
    fi
    acquire_lifecycle_lock || return $?
    confirm_lifecycle_batch stop "${SELECTED_INSTANCES[@]}" || return $?

    total=${#SELECTED_INSTANCES[@]}
    for instance in "${SELECTED_INSTANCES[@]}"; do
        index=$((index + 1))
        if ! confirm_lifecycle_instance stop "$instance" "$index" "$total"; then
            log warning "Stop cancelled before instance: $instance"
            return "$EX_CANCELLED"
        fi

        stop_one "$instance"
        action_rc=$?
        if (( action_rc > rc )); then
            rc="$action_rc"
        fi
    done

    return "$rc"
}

restart_instances() {
    local instance
    local rc=0
    local action_rc=0
    local index=0
    local total=0
    local -a stopped=()

    build_selection "$@" || return $?
    if (( ${#SELECTED_INSTANCES[@]} == 0 )); then
        log info "No selected instances match the requested state filter; nothing to do"
        return 0
    fi

    case "$FRM_RESTART_STRATEGY" in
        rolling|all-at-once) ;;
        *)
            log error "Unknown restart strategy: $FRM_RESTART_STRATEGY"
            return "$EX_GENERAL"
            ;;
    esac

    acquire_lifecycle_lock || return $?
    confirm_lifecycle_batch "restart ($FRM_RESTART_STRATEGY)" "${SELECTED_INSTANCES[@]}" || return $?
    total=${#SELECTED_INSTANCES[@]}

    if bool_true "$FRM_DRY_RUN"; then
        for instance in "${SELECTED_INSTANCES[@]}"; do
            index=$((index + 1))
            if ! confirm_lifecycle_instance restart "$instance" "$index" "$total"; then
                log warning "Restart cancelled before instance: $instance"
                return "$EX_CANCELLED"
            fi

            log info "DRY-RUN restart instance: $instance"

            execute_action "$instance" stop
            action_rc=$?
            if (( action_rc > rc )); then
                rc="$action_rc"
            fi

            execute_action "$instance" start
            action_rc=$?
            if (( action_rc > rc )); then
                rc="$action_rc"
            fi
        done
        return "$rc"
    fi

    case "$FRM_RESTART_STRATEGY" in
        rolling)
            for instance in "${SELECTED_INSTANCES[@]}"; do
                index=$((index + 1))
                if ! confirm_lifecycle_instance restart "$instance" "$index" "$total"; then
                    log warning "Rolling restart cancelled before instance: $instance"
                    return "$EX_CANCELLED"
                fi

                log info "Rolling restart [$index/$total]: $instance"
                stop_one "$instance"
                action_rc=$?

                if (( action_rc == 0 )); then
                    start_one "$instance"
                    action_rc=$?
                    if (( action_rc > rc )); then
                        rc="$action_rc"
                    fi
                else
                    log error "Not starting $instance because stop failed"
                    if (( action_rc > rc )); then
                        rc="$action_rc"
                    fi
                fi
            done
            ;;

        all-at-once)
            # Step-confirmation is preflighted for the whole selection before
            # changing any state. This prevents a cancellation half-way through
            # the stop phase from leaving an accidental partial outage.
            if bool_true "$FRM_CONFIRM_EACH" && ! bool_true "$FRM_ASSUME_YES"; then
                index=0
                for instance in "${SELECTED_INSTANCES[@]}"; do
                    index=$((index + 1))
                    if ! confirm_lifecycle_instance "all-at-once restart" "$instance" "$index" "$total"; then
                        log warning "All-at-once restart cancelled during preflight before any state change"
                        return "$EX_CANCELLED"
                    fi
                done
            fi

            for instance in "${SELECTED_INSTANCES[@]}"; do
                stop_one "$instance"
                action_rc=$?

                if (( action_rc == 0 )); then
                    stopped+=("$instance")
                elif (( action_rc > rc )); then
                    rc="$action_rc"
                fi
            done

            for instance in "${stopped[@]}"; do
                start_one "$instance"
                action_rc=$?
                if (( action_rc > rc )); then
                    rc="$action_rc"
                fi
            done
            ;;
    esac

    return "$rc"
}

plan_instances() {
    local action="$1"
    shift
    local instance
    local rc=0

    case "$action" in
        start|stop) ;;
        restart) ;;
        *)
            log error "plan expects start, stop, or restart"
            return "$EX_GENERAL"
            ;;
    esac

    build_selection "$@" || return $?

    printf '%-24s %-10s %s\n' "INSTANCE" "BACKEND" "COMMAND"
    printf '%-24s %-10s %s\n' "------------------------" "----------" "----------------------------------------"

    for instance in "${SELECTED_INSTANCES[@]}"; do
        if [[ "$action" == "restart" ]]; then
            if resolve_action_backend "$instance" stop; then
                printf '%-24s %-10s %s\n' "$instance" "$ACTION_BACKEND" "$ACTION_DESCRIPTION"
            else
                printf '%-24s %-10s %s\n' "$instance" "NONE" "stop unavailable"
                rc="$EX_UNAVAILABLE"
            fi
            if resolve_action_backend "$instance" start; then
                printf '%-24s %-10s %s\n' "" "$ACTION_BACKEND" "$ACTION_DESCRIPTION"
            else
                printf '%-24s %-10s %s\n' "" "NONE" "start unavailable"
                rc="$EX_UNAVAILABLE"
            fi
        else
            if resolve_action_backend "$instance" "$action"; then
                printf '%-24s %-10s %s\n' "$instance" "$ACTION_BACKEND" "$ACTION_DESCRIPTION"
            else
                printf '%-24s %-10s %s\n' "$instance" "NONE" "$action unavailable"
                rc="$EX_UNAVAILABLE"
            fi
        fi
    done

    return "$rc"
}
