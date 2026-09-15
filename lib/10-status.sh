# Process detection
###############################################################################

instance_httpd_info() {
    local instance="$1"
    local instance_path="$FRM_INSTANCES_DIR/$instance/"

    ps -eo pid=,ppid=,comm=,args= 2>/dev/null |
        awk -v instance_path="$instance_path" '
            {
                pid=$1
                ppid=$2
                comm=$3

                if (comm == "httpd" || comm == "httpd.worker") {
                    httpd[pid]=1
                    parent[pid]=ppid

                    if (index($0, instance_path)) {
                        direct[pid]=1
                    }
                }

                if (index($0, instance_path)) {
                    path_parent[ppid]=1
                }
            }

            END {
                master=""
                count=0

                for (pid in direct) {
                    if (parent[pid] == 1) {
                        master=pid
                        break
                    }
                }

                if (master == "") {
                    for (pid in direct) {
                        master=pid
                        break
                    }
                }

                if (master == "") {
                    for (pid in path_parent) {
                        if (pid in httpd) {
                            master=pid
                            break
                        }
                    }
                }

                if (master == "") {
                    exit 1
                }

                for (pid in httpd) {
                    if (pid == master || parent[pid] == master) {
                        count++
                    }
                }

                if (count == 0) {
                    count=1
                }

                printf "%s %d\n", master, count
            }
        '
}

set_process_status() {
    local instance="$1"
    local info=""

    if info="$(instance_httpd_info "$instance")"; then
        read -r STATUS_PID STATUS_PROCESS_COUNT <<< "$info"
        STATUS_STATE="RUNNING"
        STATUS_DETAIL="pid=$STATUS_PID httpd=$STATUS_PROCESS_COUNT"
        return 0
    fi

    return 1
}

###############################################################################
# Status parsing
###############################################################################

reset_status_result() {
    STATUS_STATE="UNKNOWN"
    STATUS_DETAIL=""
    STATUS_BACKEND="none"
    STATUS_PID=""
    STATUS_PROCESS_COUNT=""
    STATUS_RAW=""
    STATUS_RC=0
}

derive_opmn_status() {
    local instance="$1"
    local output="$2"
    local rc="$3"
    local parsed=""
    local opmn_pid=""
    local opmn_state=""
    local process_info=""
    local process_pid=""
    local process_count=""

    parsed="$(
        printf '%s\n' "$output" |
            awk -F'|' '
                function trim(s) {
                    gsub(/^[[:space:]]+/, "", s)
                    gsub(/[[:space:]]+$/, "", s)
                    return s
                }

                tolower($2) ~ /^[[:space:]]*ohs[[:space:]]*$/ {
                    print trim($3) "\t" trim($4)
                    exit
                }
            '
    )"

    if [[ -n "$parsed" ]]; then
        IFS=$'\t' read -r opmn_pid opmn_state <<< "$parsed"

        case "${opmn_state,,}" in
            alive)
                STATUS_STATE="RUNNING"
                STATUS_PID="$opmn_pid"
                if [[ -n "$opmn_pid" && "$opmn_pid" != "N/A" ]]; then
                    STATUS_DETAIL="pid=$opmn_pid opmn=Alive"
                else
                    STATUS_DETAIL="opmn=Alive"
                fi
                return 0
                ;;
            down)
                if process_info="$(instance_httpd_info "$instance")"; then
                    read -r process_pid process_count <<< "$process_info"
                    STATUS_STATE="WARNING"
                    STATUS_PID="$process_pid"
                    STATUS_PROCESS_COUNT="$process_count"
                    STATUS_DETAIL="opmn=Down but httpd pid=$process_pid"
                else
                    STATUS_STATE="DOWN"
                    STATUS_DETAIL="opmn=Down"
                fi
                return 0
                ;;
            *)
                STATUS_STATE="UNKNOWN"
                STATUS_DETAIL="opmn=$opmn_state"
                return 0
                ;;
        esac
    fi

    if grep -qi 'opmn is not running' <<< "$output"; then
        if process_info="$(instance_httpd_info "$instance")"; then
            read -r process_pid process_count <<< "$process_info"
            STATUS_STATE="WARNING"
            STATUS_PID="$process_pid"
            STATUS_PROCESS_COUNT="$process_count"
            STATUS_DETAIL="opmn not running, httpd pid=$process_pid"
        else
            STATUS_STATE="DOWN"
            STATUS_DETAIL="opmn not running"
        fi
        return 0
    fi

    if set_process_status "$instance"; then
        STATUS_DETAIL="$STATUS_DETAIL process-fallback"
        return 0
    fi

    STATUS_STATE="UNKNOWN"
    if (( rc != 0 )); then
        STATUS_DETAIL="opmnctl rc=$rc"
    else
        STATUS_DETAIL="unable to parse opmnctl status"
    fi
}

derive_service_status() {
    local instance="$1"
    local output="$2"
    local rc="$3"
    local source="$4"

    if set_process_status "$instance"; then
        if (( rc == 0 )); then
            return 0
        fi

        STATUS_STATE="WARNING"
        STATUS_DETAIL="$STATUS_DETAIL ${source}-rc=$rc"
        return 0
    fi

    if grep -Eqi 'Active:[[:space:]]+active([[:space:]]|\()' <<< "$output"; then
        STATUS_STATE="WARNING"
        STATUS_DETAIL="$source active but httpd not found"
        return 0
    fi

    if grep -Eqi 'Active:[[:space:]]+(inactive|failed|deactivating|dead)' <<< "$output"; then
        STATUS_STATE="DOWN"
        STATUS_DETAIL="$source not active"
        return 0
    fi

    if (( rc != 0 )); then
        STATUS_STATE="DOWN"
        STATUS_DETAIL="$source rc=$rc"
        return 0
    fi

    STATUS_STATE="UNKNOWN"
    STATUS_DETAIL="$source OK, httpd not found"
}

emit_native_status_output() {
    local output="${1:-}"

    [[ -n "$output" ]] || return 0

    # Keep machine-readable stdout valid. In JSON/TSV mode native backend
    # diagnostics are deliberately routed to stderr.
    case "$FRM_STATUS_FORMAT" in
        json|tsv)
            printf '%s\n' "$output" >&2
            ;;
        *)
            printf '%s\n' "$output"
            ;;
    esac
}

collect_status() {
    local instance="$1"
    local verbose="${2:-false}"
    local handler="${instance}_status"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"
    local systemd_unit="${instance}.service"
    local sysv=""
    local output=""
    local rc=0

    reset_status_result

    log debug "Checking status of instance: $instance"

    if custom_handler_exists "$handler"; then
        STATUS_BACKEND="handler"
        log debug "Using custom status handler for $instance: $handler"
        output="$("$handler" 2>&1)"
        rc=$?
        STATUS_RAW="$output"
        STATUS_RC=$rc
        bool_true "$verbose" && emit_native_status_output "$output"
        derive_service_status "$instance" "$output" "$rc" "status-handler"

    elif [[ -x "$opmnctl" ]]; then
        STATUS_BACKEND="opmn"
        log debug "Using opmnctl to check status of $instance: $opmnctl"
        output="$("$opmnctl" status 2>&1)"
        rc=$?
        STATUS_RAW="$output"
        STATUS_RC=$rc
        bool_true "$verbose" && emit_native_status_output "$output"
        derive_opmn_status "$instance" "$output" "$rc"

    elif systemd_unit_exists "$systemd_unit"; then
        STATUS_BACKEND="systemd"
        log debug "Using systemd unit to check status of $instance: $systemd_unit"
        output="$(systemctl status "$systemd_unit" --no-pager --full 2>&1)"
        rc=$?
        STATUS_RAW="$output"
        STATUS_RC=$rc
        bool_true "$verbose" && emit_native_status_output "$output"
        derive_service_status "$instance" "$output" "$rc" "systemd"

    elif sysv="$(sysv_script_path "$instance")"; then
        STATUS_BACKEND="sysv"
        log debug "Using SysV status for $instance: $sysv"
        output="$("$sysv" status 2>&1)"
        rc=$?
        STATUS_RAW="$output"
        STATUS_RC=$rc
        bool_true "$verbose" && emit_native_status_output "$output"
        derive_service_status "$instance" "$output" "$rc" "sysv"

    else
        STATUS_BACKEND="process"
        log debug "No explicit status backend for $instance; using httpd process detection"
        if ! set_process_status "$instance"; then
            STATUS_STATE="DOWN"
            STATUS_DETAIL="httpd not found"
        fi
    fi

    log debug "Derived status for $instance: $STATUS_STATE${STATUS_DETAIL:+ ($STATUS_DETAIL)}"
}

###############################################################################
# Status output
###############################################################################

status_level() {
    case "$1" in
        RUNNING) printf '%s' success ;;
        DOWN) printf '%s' error ;;
        WARNING|UNKNOWN) printf '%s' warning ;;
        *) printf '%s' status ;;
    esac
}

print_status_table_row() {
    local instance="$1"
    local level
    local line

    level="$(status_level "$STATUS_STATE")"
    printf -v line '%-24s %-8s %s' "$instance" "$STATUS_STATE" "$STATUS_DETAIL"
    log "$level" "$line"
}

print_status_tsv_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "$STATUS_STATE" "$STATUS_BACKEND" "$STATUS_PID" \
        "$STATUS_PROCESS_COUNT" "$STATUS_DETAIL"
}

print_status_json_object() {
    local instance="$1"
    printf '{"instance":"%s","state":"%s","backend":"%s","pid":"%s","httpd_count":"%s","detail":"%s"}' \
        "$(json_escape "$instance")" \
        "$(json_escape "$STATUS_STATE")" \
        "$(json_escape "$STATUS_BACKEND")" \
        "$(json_escape "$STATUS_PID")" \
        "$(json_escape "$STATUS_PROCESS_COUNT")" \
        "$(json_escape "$STATUS_DETAIL")"
}

###############################################################################
