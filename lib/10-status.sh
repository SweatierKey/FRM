# Process detection
###############################################################################

instance_httpd_info() {
    local instance="$1"
    local instance_path="$FRM_INSTANCES_DIR/$instance/"

    # RHEL7/procps may truncate args to the display width when stdout is a pipe.
    # The OHS instance path can appear after column 80, so force unlimited width.
    ps -ww -eo pid=,ppid=,comm=,args= 2>/dev/null |
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

parse_ps_etime_seconds() {
    local value="${1:-}"
    local days=0
    local hours=0
    local minutes=0
    local seconds=0
    local rest=""
    local -a parts=()

    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    [[ -n "$value" ]] || return 1

    if [[ "$value" == *-* ]]; then
        days="${value%%-*}"
        rest="${value#*-}"
        [[ "$days" =~ ^[0-9]+$ ]] || return 1
    else
        rest="$value"
    fi

    IFS=':' read -r -a parts <<< "$rest"

    case "${#parts[@]}" in
        2)
            minutes="${parts[0]}"
            seconds="${parts[1]}"
            ;;
        3)
            hours="${parts[0]}"
            minutes="${parts[1]}"
            seconds="${parts[2]}"
            ;;
        *)
            return 1
            ;;
    esac

    [[ "$hours" =~ ^[0-9]+$ ]] || return 1
    [[ "$minutes" =~ ^[0-9]+$ ]] || return 1
    [[ "$seconds" =~ ^[0-9]+$ ]] || return 1

    printf '%d\n' "$((10#$days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))"
}

process_uptime_seconds_procfs() {
    local pid="$1"
    local proc_root="${FRM_PROC_ROOT:-/proc}"
    local stat_line=""
    local stat_tail=""
    local start_ticks=""
    local hz=""
    local host_uptime=""
    local start_seconds=""
    local elapsed=""
    local -a fields=()

    [[ -r "$proc_root/$pid/stat" && -r "$proc_root/uptime" ]] || return 1

    stat_line="$(<"$proc_root/$pid/stat")" || return 1
    stat_tail="${stat_line##*) }"
    read -r -a fields <<< "$stat_tail"

    # /proc/<pid>/stat field 22 is starttime. After stripping pid + comm,
    # the remaining array begins at field 3, so starttime is index 19.
    start_ticks="${fields[19]:-}"
    [[ "$start_ticks" =~ ^[0-9]+$ ]] || return 1

    hz="$(getconf CLK_TCK 2>/dev/null)"
    [[ "$hz" =~ ^[0-9]+$ && "$hz" -gt 0 ]] || return 1

    host_uptime="$(awk 'NR == 1 { print int($1); exit }' "$proc_root/uptime" 2>/dev/null)"
    [[ "$host_uptime" =~ ^[0-9]+$ ]] || return 1

    start_seconds=$((start_ticks / hz))
    elapsed=$((host_uptime - start_seconds))
    (( elapsed >= 0 )) || return 1

    printf '%s\n' "$elapsed"
}

process_uptime_seconds() {
    local pid="$1"
    local value=""

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    # procps-ng supports etimes on newer hosts, but older RHEL/procps builds
    # may not. Prefer the numeric field when available, then fall back to the
    # portable elapsed-time string, and finally Linux /proc timing data.
    value="$(ps -o etimes= -p "$pid" 2>/dev/null | awk 'NR == 1 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit }')"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    value="$(ps -o etime= -p "$pid" 2>/dev/null | awk 'NR == 1 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit }')"
    if parse_ps_etime_seconds "$value"; then
        return 0
    fi

    process_uptime_seconds_procfs "$pid"
}

format_uptime() {
    local total="${1:-}"
    local days hours minutes seconds

    [[ "$total" =~ ^[0-9]+$ ]] || return 1

    days=$((total / 86400))
    hours=$(((total % 86400) / 3600))
    minutes=$(((total % 3600) / 60))
    seconds=$((total % 60))

    if (( days > 0 )); then
        printf '%dd%dh' "$days" "$hours"
    elif (( hours > 0 )); then
        printf '%dh%dm' "$hours" "$minutes"
    elif (( minutes > 0 )); then
        printf '%dm%ds' "$minutes" "$seconds"
    else
        printf '%ds' "$seconds"
    fi
}

enrich_status_uptime() {
    local seconds=""

    STATUS_UPTIME_SECONDS=""
    STATUS_UPTIME=""

    case "$STATUS_STATE" in
        RUNNING|WARNING) ;;
        *) return 0 ;;
    esac

    [[ "$STATUS_PID" =~ ^[0-9]+$ ]] || return 0

    if seconds="$(process_uptime_seconds "$STATUS_PID")"; then
        STATUS_UPTIME_SECONDS="$seconds"
        STATUS_UPTIME="$(format_uptime "$seconds")"
    fi
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
    STATUS_UPTIME_SECONDS=""
    STATUS_UPTIME=""
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

    elif sysv="$(sysv_script_path "$instance")" && [[ -x "$sysv" ]]; then
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

    enrich_status_uptime
    log debug "Derived status for $instance: $STATUS_STATE${STATUS_DETAIL:+ ($STATUS_DETAIL)}${STATUS_UPTIME:+ uptime=$STATUS_UPTIME}"
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

    local detail="$STATUS_DETAIL"

    level="$(status_level "$STATUS_STATE")"
    if [[ -n "$STATUS_UPTIME" ]]; then
        detail="${detail}${detail:+ }uptime=$STATUS_UPTIME"
    fi
    printf -v line '%-24s %-8s %s' "$instance" "$STATUS_STATE" "$detail"
    log "$level" "$line"
}

print_status_tsv_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "$STATUS_STATE" "$STATUS_BACKEND" "$STATUS_PID" \
        "$STATUS_PROCESS_COUNT" "$STATUS_UPTIME" "$STATUS_UPTIME_SECONDS" "$STATUS_DETAIL"
}

print_status_json_object() {
    local instance="$1"
    local uptime_seconds_json=null

    if [[ "$STATUS_UPTIME_SECONDS" =~ ^[0-9]+$ ]]; then
        uptime_seconds_json="$STATUS_UPTIME_SECONDS"
    fi

    printf '{"instance":"%s","state":"%s","backend":"%s","pid":"%s","httpd_count":"%s","uptime":"%s","uptime_seconds":%s,"detail":"%s"}' \
        "$(json_escape "$instance")" \
        "$(json_escape "$STATUS_STATE")" \
        "$(json_escape "$STATUS_BACKEND")" \
        "$(json_escape "$STATUS_PID")" \
        "$(json_escape "$STATUS_PROCESS_COUNT")" \
        "$(json_escape "$STATUS_UPTIME")" \
        "$uptime_seconds_json" \
        "$(json_escape "$STATUS_DETAIL")"
}

###############################################################################
