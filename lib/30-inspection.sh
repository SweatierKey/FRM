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

ports_instances() {
    local instance
    local ports=""
    local source=""
    local rc=0

    build_selection "$@" || return $?

    printf '%-24s %-10s %s\n' "INSTANCE" "SOURCE" "PORTS/LISTENERS"
    printf '%-24s %-10s %s\n' "------------------------" "----------" "----------------------------------------"

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

        printf '%-24s %-10s %s\n' "$instance" "$source" "$ports"
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
