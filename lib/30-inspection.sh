# Process and port inspection
###############################################################################

processes_instances() {
    local instance
    local info=""
    local master=""
    local count=""
    local path=""

    build_selection "$@" || return $?

    for instance in "${SELECTED_INSTANCES[@]}"; do
        path="$FRM_INSTANCES_DIR/$instance/"

        printf 'Instance: %s\n' "$instance"

        if ! info="$(instance_httpd_info "$instance")"; then
            printf '  no matching httpd/httpd.worker runtime found\n\n'
            continue
        fi

        read -r master count <<< "$info"
        printf '  master pid: %s\n' "$master"
        printf '  httpd count: %s\n' "$count"
        printf '\n'
        printf '  %-10s %-8s %-8s %-12s %s\n' "USER" "PID" "PPID" "ELAPSED" "COMMAND"

        ps -ww -eo user=,pid=,ppid=,etime=,args= 2>/dev/null |
            awk -v master="$master" -v instance_path="$path" '
                {
                    user=$1
                    pid=$2
                    ppid=$3
                    etime=$4

                    if (pid == master || ppid == master || index($0, instance_path)) {
                        printf "  %-10s %-8s %-8s %-12s ", user, pid, ppid, etime
                        for (i=5; i<=NF; i++) {
                            printf "%s%s", $i, (i < NF ? OFS : ORS)
                        }
                    }
                }
            '

        printf '\n'
    done
}



instance_nodemanager_info() {
    local instance="$1"
    local instance_path="$FRM_INSTANCES_DIR/$instance"
    local pid=""
    local uptime_seconds=""
    local uptime=""

    pid="$({
        ps -ww -eo pid=,comm=,args= 2>/dev/null || true
    } | awk -v root="$instance_path" '
        $2 == "java" && index($0, "weblogic.NodeManager") && index($0, "-Dweblogic.RootDirectory=" root) {
            print $1
            exit
        }
    ')"

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    uptime_seconds="$(process_uptime_seconds "$pid" 2>/dev/null || true)"
    if [[ "$uptime_seconds" =~ ^[0-9]+$ ]]; then
        uptime="$(format_uptime "$uptime_seconds")"
    fi

    printf '%s %s\n' "$pid" "$uptime"
}

opmn_ports() {
    local instance="$1"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"

    [[ -x "$opmnctl" ]] || return 1

    "$opmnctl" status -l 2>/dev/null |
        awk -F'|' '
            function trim(s) {
                gsub(/^[[:space:]]+/, "", s)
                gsub(/[[:space:]]+$/, "", s)
                return s
            }

            tolower($2) ~ /^[[:space:]]*ohs[[:space:]]*$/ {
                value=trim($NF)
                if (value != "" && tolower(value) != "ports") {
                    print value
                    exit
                }
            }
        '
}

config_listen_ports() {
    local instance="$1"
    local config_root="$FRM_INSTANCES_DIR/$instance/config/fmwconfig/components/OHS"

    [[ -d "$config_root" ]] || return 1

    grep -RhsE '^[[:space:]]*Listen[[:space:]]+' "$config_root" 2>/dev/null |
        awk '{print $2}' |
        sort -u |
        awk '
            NF {
                values[++n]=$0
            }

            END {
                for (i=1; i<=n; i++) {
                    printf "%s%s", values[i], (i < n ? "," : ORS)
                }
                if (n == 0) {
                    exit 1
                }
            }
        '
}


listener_snapshot() {
    if command -v ss >/dev/null 2>&1; then
        if ss -lntp 2>/dev/null; then
            return 0
        fi
    fi

    if command -v netstat >/dev/null 2>&1; then
        if netstat -lntp 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

configured_port_numbers() {
    local values="$1"

    printf '%s\n' "$values" |
        tr ',' '\n' |
        awk '
            {
                value=$0
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                if (value == "") next

                n=split(value, parts, ":")
                port=parts[n]
                gsub(/[^0-9].*$/, "", port)
                if (port ~ /^[0-9]+$/) print port
            }
        ' |
        sort -n -u
}

instance_httpd_pids() {
    local instance="$1"
    local info=""
    local master=""
    local count=""

    info="$(instance_httpd_info "$instance")" || return 1
    read -r master count <<< "$info"

    ps -eo pid=,ppid=,comm= 2>/dev/null |
        awk -v master="$master" '
            ($1 == master) || ($2 == master && ($3 == "httpd" || $3 == "httpd.worker")) {
                print $1
            }
        '
}

listener_info_for_port() {
    local port="$1"
    local snapshot="$2"
    local lines=""
    local pids=""

    lines="$(printf '%s\n' "$snapshot" | awk -v port="$port" '
        {
            for (i=1; i<=NF; i++) {
                if ($i ~ (":" port "$") || $i ~ (":" port "[^0-9]")) {
                    print
                    break
                }
            }
        }
    ')"

    [[ -n "$lines" ]] || return 1

    pids="$(printf '%s\n' "$lines" |
        grep -Eo 'pid=[0-9]+|[0-9]+/[[:alnum:]_.-]+' 2>/dev/null |
        sed -E 's/^pid=//; s#/.*$##' |
        sort -n -u |
        paste -sd, - 2>/dev/null || true)"

    printf '%s\t%s\n' "LISTEN" "${pids:-unknown}"
}

verify_instance_ports() {
    local instance="$1"
    local values="$2"
    local snapshot="$3"
    local port=""
    local listener=""
    local state=""
    local owners=""
    local match=""
    local expected_pids=""
    local expected_csv=""
    local owner=""
    local rc=0

    expected_pids="$(instance_httpd_pids "$instance" 2>/dev/null || true)"
    expected_csv="$(printf '%s\n' "$expected_pids" | awk 'NF' | paste -sd, - 2>/dev/null || true)"

    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        listener="$(listener_info_for_port "$port" "$snapshot" 2>/dev/null || true)"

        if [[ -z "$listener" ]]; then
            state="MISSING"
            owners="-"
            match="NO"
            rc="$EX_STATE"
        else
            IFS=$'\t' read -r state owners <<< "$listener"
            if [[ "$owners" == unknown || -z "$expected_pids" ]]; then
                match="UNKNOWN"
            else
                match="NO"
                IFS=',' read -r -a owner_list <<< "$owners"
                for owner in "${owner_list[@]}"; do
                    if grep -qx "$owner" <<< "$expected_pids"; then
                        match="YES"
                        break
                    fi
                done
                [[ "$match" == YES ]] || rc="$EX_STATE"
            fi
        fi

        printf '%-24s %-7s %-8s %-14s %-8s %s\n' \
            "$instance" "$port" "$state" "$owners" "$match" "${expected_csv:-unknown}"
    done < <(configured_port_numbers "$values")

    return "$rc"
}

ports_instances() {
    local instance
    local ports=""
    local source=""
    local snapshot=""
    local rc=0
    local verify_rc=0

    build_selection "$@" || return $?

    if bool_true "$FRM_PORTS_VERIFY"; then
        snapshot="$(listener_snapshot)" || {
            log error "Neither ss nor netstat is available for listener verification"
            return "$EX_UNAVAILABLE"
        }
        printf '%-24s %-7s %-8s %-14s %-8s %s\n' \
            "INSTANCE" "PORT" "SOCKET" "OWNER_PIDS" "MATCH" "OHS_PIDS"
        printf '%-24s %-7s %-8s %-14s %-8s %s\n' \
            "------------------------" "-------" "--------" "--------------" "--------" "----------------"
    else
        printf '%-24s %-10s %s\n' "INSTANCE" "SOURCE" "PORTS/LISTENERS"
        printf '%-24s %-10s %s\n' "------------------------" "----------" "----------------------------------------"
    fi

    for instance in "${SELECTED_INSTANCES[@]}"; do
        ports=""
        source=""

        if ports="$(opmn_ports "$instance")" && [[ -n "$ports" ]]; then
            source="opmn"
        elif ports="$(config_listen_ports "$instance")" && [[ -n "$ports" ]]; then
            source="config"
        else
            source="unknown"
            ports="not discovered"
            rc="$EX_STATE"
        fi

        if bool_true "$FRM_PORTS_VERIFY"; then
            if [[ "$source" == unknown ]]; then
                printf '%-24s %-7s %-8s %-14s %-8s %s\n' "$instance" "-" "UNKNOWN" "-" "-" "-"
                continue
            fi
            verify_instance_ports "$instance" "$ports" "$snapshot"
            verify_rc=$?
            (( verify_rc > rc )) && rc="$verify_rc"
        else
            printf '%-24s %-10s %s\n' "$instance" "$source" "$ports"
        fi
    done

    return "$rc"
}

###############################################################################
# Configuration syntax validation
###############################################################################

CONFIGTEST_COMMAND=()
CONFIGTEST_DESCRIPTION=""

instance_httpd_args() {
    local instance="$1"
    local info=""
    local master=""
    local count=""

    info="$(instance_httpd_info "$instance")" || return 1
    read -r master count <<< "$info"
    [[ "$master" =~ ^[0-9]+$ ]] || return 1

    ps -ww -eo pid=,args= 2>/dev/null |
        awk -v wanted="$master" '
            $1 == wanted {
                $1=""
                sub(/^[[:space:]]+/, "")
                print
                exit
            }
        '
}

opmn_ohs_component() {
    local instance="$1"
    local opmnctl="$FRM_INSTANCES_DIR/$instance/bin/opmnctl"

    [[ -x "$opmnctl" ]] || return 1

    "$opmnctl" status 2>/dev/null |
        awk -F'|' '
            function trim(s) {
                gsub(/^[[:space:]]+/, "", s)
                gsub(/[[:space:]]+$/, "", s)
                return s
            }

            tolower($2) ~ /^[[:space:]]*ohs[[:space:]]*$/ {
                print trim($1)
                exit
            }
        '
}

find_instance_httpd_conf() {
    local instance="$1"
    local root="$FRM_INSTANCES_DIR/$instance/config"
    local component=""
    local candidate=""
    local -a matches=()

    [[ -d "$root" ]] || return 1

    component="$(opmn_ohs_component "$instance" 2>/dev/null || true)"

    for candidate in \
        "$root/fmwconfig/components/OHS/instances/$instance/httpd.conf" \
        "$root/fmwconfig/components/OHS/$instance/httpd.conf" \
        "$root/OHS/$component/httpd.conf"
    do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    while IFS= read -r candidate; do
        matches+=("$candidate")
    done < <(find "$root" -type f -name httpd.conf 2>/dev/null | sort)

    if (( ${#matches[@]} == 1 )); then
        printf '%s\n' "${matches[0]}"
        return 0
    fi

    return 1
}

shell_join_quoted() {
    local part
    local out=""
    local quoted=""

    for part in "$@"; do
        printf -v quoted '%q' "$part"
        out="${out}${out:+ }$quoted"
    done

    printf '%s\n' "$out"
}

resolve_configtest_command() {
    local instance="$1"
    local args=""
    local exe=""
    local config=""
    local token=""
    local next=""
    local i=0
    local have_d=false
    local have_f=false
    local -a words=()
    local -a cmd=()

    CONFIGTEST_COMMAND=()
    CONFIGTEST_DESCRIPTION=""

    args="$(instance_httpd_args "$instance")" || return "$EX_UNAVAILABLE"
    read -r -a words <<< "$args"
    (( ${#words[@]} > 0 )) || return "$EX_UNAVAILABLE"

    exe="${words[0]}"
    [[ -x "$exe" ]] || return "$EX_UNAVAILABLE"
    cmd+=("$exe")

    # Reuse only syntax-affecting startup flags from the live OHS master.
    # Lifecycle flags such as -k start are deliberately omitted.
    i=1
    while (( i < ${#words[@]} )); do
        token="${words[$i]}"
        case "$token" in
            -D*)
                cmd+=("$token")
                ;;
            -d|-f)
                if (( i + 1 < ${#words[@]} )); then
                    next="${words[$((i + 1))]}"
                    cmd+=("$token" "$next")
                    [[ "$token" == -d ]] && have_d=true
                    [[ "$token" == -f ]] && have_f=true
                    i=$((i + 1))
                fi
                ;;
        esac
        i=$((i + 1))
    done

    if ! $have_d || ! $have_f; then
        config="$(find_instance_httpd_conf "$instance")" || return "$EX_UNAVAILABLE"
        if ! $have_d; then
            cmd+=("-d" "$(dirname "$config")")
        fi
        if ! $have_f; then
            cmd+=("-f" "$config")
        fi
    fi

    cmd+=("-t")
    CONFIGTEST_COMMAND=("${cmd[@]}")
    CONFIGTEST_DESCRIPTION="$(shell_join_quoted "${cmd[@]}")"
    return 0
}

configtest_one() {
    local instance="$1"
    local handler="${instance}_configtest"
    local output=""
    local rc=0

    if custom_handler_exists "$handler"; then
        log info "Configtest: $instance"
        log debug "Using custom configtest handler: $handler"
        if bool_true "$FRM_DRY_RUN"; then
            log info "DRY-RUN  $instance  configtest  $handler"
            return 0
        fi
        output="$("$handler" 2>&1)"
        rc=$?
    else
        if ! resolve_configtest_command "$instance"; then
            log error "No reliable configtest command could be resolved for $instance"
            return "$EX_UNAVAILABLE"
        fi

        log info "Configtest: $instance"
        log debug "Configtest command: $CONFIGTEST_DESCRIPTION"

        if bool_true "$FRM_DRY_RUN"; then
            log info "DRY-RUN  $instance  configtest  $CONFIGTEST_DESCRIPTION"
            return 0
        fi

        output="$("${CONFIGTEST_COMMAND[@]}" 2>&1)"
        rc=$?
    fi

    if (( rc == 0 )); then
        log success "$instance configtest OK${output:+: $output}"
        return 0
    fi

    log error "$instance configtest FAILED rc=$rc"
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return "$EX_STATE"
}

configtest_instances() {
    local instance
    local rc=0
    local item_rc=0

    build_selection "$@" || return $?

    for instance in "${SELECTED_INSTANCES[@]}"; do
        configtest_one "$instance"
        item_rc=$?
        (( item_rc > rc )) && rc="$item_rc"
    done

    return "$rc"
}

preflight_configtest_instances() {
    local instance
    local rc=0

    bool_true "$FRM_PREFLIGHT_CONFIGTEST" || return 0

    log info "Running configuration preflight for ${#SELECTED_INSTANCES[@]} selected instance(s)"
    for instance in "${SELECTED_INSTANCES[@]}"; do
        configtest_one "$instance" || rc=$?
        if (( rc != 0 )); then
            log error "Lifecycle aborted: configtest preflight failed for $instance"
            return "$rc"
        fi
    done

    return 0
}


###############################################################################
# Log discovery / read-only navigation
###############################################################################

discover_log_files() {
    local instance="$1"
    local kind="${2:-all}"
    local base="$FRM_INSTANCES_DIR/$instance"
    local root=""
    local file=""
    local lower=""
    local -a roots=()

    for root in \
        "$base/servers/$instance/logs" \
        "$base/diagnostics/logs/OHS" \
        "$base/auditlogs/OHS" \
        "$base/logs"
    do
        [[ -d "$root" ]] && roots+=("$root")
    done

    (( ${#roots[@]} > 0 )) || return 1

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        lower="${file,,}"
        case "$kind" in
            all) ;;
            error)
                [[ "$lower" == *error* || "$lower" == */diagnostics/logs/ohs/*/*.log ]] || continue
                ;;
            access)
                [[ "$lower" == *access* ]] || continue
                ;;
            admin)
                [[ "$lower" == *admin* ]] || continue
                ;;
            audit)
                [[ "$lower" == *audit* ]] || continue
                ;;
            *) return "$EX_GENERAL" ;;
        esac
        printf '%s\n' "$file"
    done < <(find "${roots[@]}" -type f 2>/dev/null | sort)
}

latest_log_file() {
    local instance="$1"
    local kind="$2"
    local file=""
    local ts=""
    local best=""
    local best_ts=-1

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        ts="$(stat -c %Y "$file" 2>/dev/null || printf '0')"
        [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
        if (( ts > best_ts )); then
            best_ts="$ts"
            best="$file"
        fi
    done < <(discover_log_files "$instance" "$kind" 2>/dev/null || true)

    [[ -n "$best" ]] || return 1
    printf '%s\n' "$best"
}

logs_instances() {
    local instance=""
    local file=""
    local found=false
    local rc=0

    build_selection "$@" || return $?

    for instance in "${SELECTED_INSTANCES[@]}"; do
        printf 'Instance: %s\n' "$instance"
        found=false

        if [[ -n "$FRM_LOG_TAIL" ]]; then
            if file="$(latest_log_file "$instance" "$FRM_LOG_TYPE")"; then
                found=true
                printf '  latest %s log: %s\n' "$FRM_LOG_TYPE" "$file"
                printf '%s\n' '------------------------------------------------------------'
                tail -n "$FRM_LOG_TAIL" "$file"
            fi
        else
            while IFS= read -r file; do
                [[ -n "$file" ]] || continue
                found=true
                printf '  %s\n' "$file"
            done < <(discover_log_files "$instance" "$FRM_LOG_TYPE" 2>/dev/null || true)
        fi

        if [[ "$found" == false ]]; then
            printf '  no matching logs discovered\n'
            rc="$EX_STATE"
        fi
        printf '\n'
    done

    return "$rc"
}

###############################################################################
# Debug info
###############################################################################

debug_info() {
    local instance
    local -a instances=()
    local stdout_real_tty=false
    local stderr_real_tty=false
    local stdout_effective_tty=false
    local stderr_effective_tty=false

    validate_instances_dir || return $?
    mapfile -t instances < <(instance_list)

    is_real_tty 1 && stdout_real_tty=true
    is_real_tty 2 && stderr_real_tty=true
    is_a_tty 1 && stdout_effective_tty=true
    is_a_tty 2 && stderr_effective_tty=true

    log debug "DEBUG: $FRM_DEBUG"
    log debug "FORCE_TTY: $FORCE_TTY"
    log debug "FRM_COLOR: $FRM_COLOR"
    log debug "stdout_real_tty: $stdout_real_tty"
    log debug "stderr_real_tty: $stderr_real_tty"
    log debug "stdout_effective_tty: $stdout_effective_tty"
    log debug "stderr_effective_tty: $stderr_effective_tty"
    log debug "instances_dir: $FRM_INSTANCES_DIR"
    log debug "handlers_file: $FRM_HANDLERS_FILE"
    log debug "skip_words: ${SKIP_WORDS[*]}"
    log debug "instance_number: ${#instances[@]}"
    log debug "instance_list:"

    for instance in "${instances[@]}"; do
        log debug "- $instance"
    done
}

###############################################################################
