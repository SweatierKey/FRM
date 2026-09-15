# CLI parsing
###############################################################################

parse_global_options() {
    GLOBAL_REST=()

    while (( $# )); do
        case "$1" in
            --debug|-d)
                FRM_DEBUG=true
                shift
                ;;
            --quiet|-q)
                FRM_QUIET=true
                shift
                ;;
            --color)
                [[ $# -ge 2 ]] || { log error "--color requires auto|always|never"; return "$EX_GENERAL"; }
                FRM_COLOR="$2"
                shift 2
                ;;
            --color=*)
                FRM_COLOR="${1#*=}"
                shift
                ;;
            --no-color)
                FRM_COLOR=never
                shift
                ;;
            --force-tty)
                FRM_COLOR=always
                shift
                ;;
            --instances-dir)
                [[ $# -ge 2 ]] || { log error "--instances-dir requires a path"; return "$EX_GENERAL"; }
                FRM_INSTANCES_DIR="$2"
                shift 2
                ;;
            --instances-dir=*)
                FRM_INSTANCES_DIR="${1#*=}"
                shift
                ;;
            --exclude)
                [[ $# -ge 2 ]] || { log error "--exclude requires a pattern"; return "$EX_GENERAL"; }
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            --exclude=*)
                EXCLUDE_PATTERNS+=("${1#*=}")
                shift
                ;;
            --state)
                [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }
                add_state_filter "$2" || return $?
                shift 2
                ;;
            --state=*)
                add_state_filter "${1#*=}" || return $?
                shift
                ;;
            --include-skipped)
                FRM_INCLUDE_SKIPPED=true
                shift
                ;;
            --dry-run|-n)
                FRM_DRY_RUN=true
                shift
                ;;
            --confirm)
                FRM_CONFIRM=true
                shift
                ;;
            --confirm-each|--step)
                FRM_CONFIRM_EACH=true
                shift
                ;;
            --yes|-y)
                FRM_ASSUME_YES=true
                shift
                ;;
            --wait)
                FRM_WAIT=true
                shift
                ;;
            --no-wait)
                FRM_WAIT=false
                shift
                ;;
            --timeout)
                [[ $# -ge 2 ]] || { log error "--timeout requires seconds"; return "$EX_GENERAL"; }
                is_positive_integer "$2" || { log error "Invalid timeout: $2"; return "$EX_GENERAL"; }
                FRM_TIMEOUT="$2"
                shift 2
                ;;
            --timeout=*)
                FRM_TIMEOUT="${1#*=}"
                is_positive_integer "$FRM_TIMEOUT" || { log error "Invalid timeout: $FRM_TIMEOUT"; return "$EX_GENERAL"; }
                shift
                ;;
            --poll-interval)
                [[ $# -ge 2 ]] || { log error "--poll-interval requires seconds"; return "$EX_GENERAL"; }
                is_positive_number "$2" || { log error "Invalid poll interval: $2"; return "$EX_GENERAL"; }
                FRM_POLL_INTERVAL="$2"
                shift 2
                ;;
            --poll-interval=*)
                FRM_POLL_INTERVAL="${1#*=}"
                is_positive_number "$FRM_POLL_INTERVAL" || { log error "Invalid poll interval: $FRM_POLL_INTERVAL"; return "$EX_GENERAL"; }
                shift
                ;;
            --sudo)
                FRM_SUDO=always
                shift
                ;;
            --no-sudo)
                FRM_SUDO=never
                shift
                ;;
            --sudo=*)
                FRM_SUDO="${1#*=}"
                shift
                ;;
            --handlers)
                [[ $# -ge 2 ]] || { log error "--handlers requires a path"; return "$EX_GENERAL"; }
                FRM_HANDLERS_FILE="$2"
                shift 2
                ;;
            --handlers=*)
                FRM_HANDLERS_FILE="${1#*=}"
                shift
                ;;
            --help)
                GLOBAL_REST=(help "${2:-overview}")
                [[ $# -ge 2 ]] && shift 2 || shift
                GLOBAL_REST+=("$@")
                return 0
                ;;
            --help=*)
                GLOBAL_REST=(help "${1#*=}")
                shift
                GLOBAL_REST+=("$@")
                return 0
                ;;
            --version|-V)
                GLOBAL_REST=(version)
                shift
                GLOBAL_REST+=("$@")
                return 0
                ;;
            --)
                shift
                GLOBAL_REST+=("$@")
                return 0
                ;;
            -* )
                log error "Unknown global option: $1"
                return "$EX_GENERAL"
                ;;
            *)
                GLOBAL_REST+=("$@")
                return 0
                ;;
        esac
    done
}

parse_status_args() {
    STATUS_SELECTORS=()

    while (( $# )); do
        case "$1" in
            --json) FRM_STATUS_FORMAT=json ;;
            --tsv) FRM_STATUS_FORMAT=tsv ;;
            --summary) FRM_STATUS_SUMMARY=true ;;
            --verbose|-v) FRM_VERBOSE_STATUS=true ;;
            --state) [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }; add_state_filter "$2" || return $?; shift ;;
            --state=*) add_state_filter "${1#*=}" || return $? ;;
            --all) STATUS_SELECTORS=(--all) ;;
            --help|-h)
                show_help status
                return 10
                ;;
            --) shift; STATUS_SELECTORS+=("$@"); break ;;
            -*) log error "Unknown status option: $1"; return "$EX_GENERAL" ;;
            *) STATUS_SELECTORS+=("$1") ;;
        esac
        shift
    done
}

parse_list_args() {
    LIST_SELECTORS=()

    while (( $# )); do
        case "$1" in
            --long|-l) FRM_LIST_LONG=true ;;
            --json) FRM_LIST_FORMAT=json ;;
            --state) [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }; add_state_filter "$2" || return $?; shift ;;
            --state=*) add_state_filter "${1#*=}" || return $? ;;
            --all) LIST_SELECTORS=(--all) ;;
            --help|-h)
                show_help commands
                return 10
                ;;
            --) shift; LIST_SELECTORS+=("$@"); break ;;
            -*) log error "Unknown list option: $1"; return "$EX_GENERAL" ;;
            *) LIST_SELECTORS+=("$1") ;;
        esac
        shift
    done
}

parse_lifecycle_args() {
    LIFECYCLE_SELECTORS=()

    while (( $# )); do
        case "$1" in
            --strategy)
                [[ $# -ge 2 ]] || { log error "--strategy requires rolling|all-at-once"; return "$EX_GENERAL"; }
                FRM_RESTART_STRATEGY="$2"
                shift
                ;;
            --strategy=*)
                FRM_RESTART_STRATEGY="${1#*=}"
                ;;
            --confirm)
                FRM_CONFIRM=true
                ;;
            --confirm-each|--step)
                FRM_CONFIRM_EACH=true
                ;;
            --yes|-y)
                FRM_ASSUME_YES=true
                ;;
            --state)
                [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }
                add_state_filter "$2" || return $?
                shift
                ;;
            --state=*)
                add_state_filter "${1#*=}" || return $?
                ;;
            --preserve-state)
                FRM_PRESERVE_STATE=true
                ;;
            --all) LIFECYCLE_SELECTORS=(--all) ;;
            --help|-h)
                show_help lifecycle
                return 10
                ;;
            --) shift; LIFECYCLE_SELECTORS+=("$@"); break ;;
            -*) log error "Unknown lifecycle option: $1"; return "$EX_GENERAL" ;;
            *) LIFECYCLE_SELECTORS+=("$1") ;;
        esac
        shift
    done
}

parse_watch_args() {
    WATCH_SELECTORS=()

    while (( $# )); do
        case "$1" in
            --interval)
                [[ $# -ge 2 ]] || { log error "--interval requires seconds"; return "$EX_GENERAL"; }
                is_positive_number "$2" || { log error "Invalid watch interval: $2"; return "$EX_GENERAL"; }
                FRM_WATCH_INTERVAL="$2"
                shift
                ;;
            --interval=*)
                FRM_WATCH_INTERVAL="${1#*=}"
                is_positive_number "$FRM_WATCH_INTERVAL" || { log error "Invalid watch interval: $FRM_WATCH_INTERVAL"; return "$EX_GENERAL"; }
                ;;
            --no-clear) FRM_WATCH_CLEAR=false ;;
            --state) [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }; add_state_filter "$2" || return $?; shift ;;
            --state=*) add_state_filter "${1#*=}" || return $? ;;
            --all) WATCH_SELECTORS=(--all) ;;
            --help|-h)
                show_help monitoring
                return 10
                ;;
            --) shift; WATCH_SELECTORS+=("$@"); break ;;
            -*) log error "Unknown watch option: $1"; return "$EX_GENERAL" ;;
            *) WATCH_SELECTORS+=("$1") ;;
        esac
        shift
    done
}

parse_selector_args() {
    SELECTOR_ARGS=()

    while (( $# )); do
        case "$1" in
            --state)
                [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }
                add_state_filter "$2" || return $?
                shift
                ;;
            --state=*)
                add_state_filter "${1#*=}" || return $?
                ;;
            --all) SELECTOR_ARGS=(--all) ;;
            --) shift; SELECTOR_ARGS+=("$@"); break ;;
            -*) log error "Unknown selector option: $1"; return "$EX_GENERAL" ;;
            *) SELECTOR_ARGS+=("$1") ;;
        esac
        shift
    done
}

parse_plan_args() {
    PLAN_ACTION="${1:-}"
    [[ -n "$PLAN_ACTION" ]] || { log error "plan requires start|stop|restart"; return "$EX_GENERAL"; }
    shift
    PLAN_SELECTORS=()

    while (( $# )); do
        case "$1" in
            --state)
                [[ $# -ge 2 ]] || { log error "--state requires a state"; return "$EX_GENERAL"; }
                add_state_filter "$2" || return $?
                shift
                ;;
            --state=*) add_state_filter "${1#*=}" || return $? ;;
            --all) PLAN_SELECTORS=(--all) ;;
            --) shift; PLAN_SELECTORS+=("$@"); break ;;
            -*) log error "Unknown plan option: $1"; return "$EX_GENERAL" ;;
            *) PLAN_SELECTORS+=("$1") ;;
        esac
        shift
    done
}

###############################################################################
# Main
###############################################################################

main() {
    local command
    local rc=0

    # Compatibility syntax: frm debug status ...
    if [[ "${1:-}" == "debug" ]]; then
        FRM_DEBUG=true
        shift
    fi

    parse_global_options "$@" || return $?
    set -- "${GLOBAL_REST[@]}"

    case "$FRM_COLOR" in
        auto|always|never) ;;
        *) log error "Invalid color mode: $FRM_COLOR"; return "$EX_GENERAL" ;;
    esac

    case "$FRM_SUDO" in
        auto|always|never) ;;
        *) log error "Invalid sudo mode: $FRM_SUDO"; return "$EX_GENERAL" ;;
    esac

    load_handlers_file

    if bool_true "$FRM_DEBUG"; then
        debug_info || return $?
    fi

    command="${1:-}"
    (( $# > 0 )) && shift

    case "$command" in
        list)
            parse_list_args "$@"; rc=$?
            (( rc == 10 )) && return 0
            (( rc != 0 )) && return "$rc"
            list_instances "${LIST_SELECTORS[@]}"
            ;;

        status)
            if bool_true "$FRM_DEBUG"; then
                FRM_VERBOSE_STATUS=true
            fi
            parse_status_args "$@"; rc=$?
            (( rc == 10 )) && return 0
            (( rc != 0 )) && return "$rc"
            status_instances "${STATUS_SELECTORS[@]}"
            ;;

        start)
            parse_lifecycle_args "$@"; rc=$?
            (( rc == 10 )) && return 0
            (( rc != 0 )) && return "$rc"
            start_instances "${LIFECYCLE_SELECTORS[@]}"
            ;;

        stop|shutdown)
            parse_lifecycle_args "$@"; rc=$?
            (( rc == 10 )) && return 0
            (( rc != 0 )) && return "$rc"
            stop_instances "${LIFECYCLE_SELECTORS[@]}"
            ;;

        restart)
            parse_lifecycle_args "$@"; rc=$?
            (( rc == 10 )) && return 0
            (( rc != 0 )) && return "$rc"
            if bool_true "$FRM_PRESERVE_STATE"; then
                if (( ${#STATE_FILTERS[@]} > 0 )); then
                    log error "--preserve-state cannot be combined with --state"
                    return "$EX_GENERAL"
                fi
                add_state_filter RUNNING || return $?
            fi
            restart_instances "${LIFECYCLE_SELECTORS[@]}"
            ;;

        watch)
            parse_watch_args "$@"; rc=$?
            (( rc == 10 )) && return 0
            (( rc != 0 )) && return "$rc"
            watch_status "${WATCH_SELECTORS[@]}"
            ;;

        inspect)
            if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
                show_help inspection
            else
                parse_selector_args "$@" || return $?
                inspect_instances "${SELECTOR_ARGS[@]}"
            fi
            ;;

        processes|ps)
            if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
                show_help inspection
            else
                parse_selector_args "$@" || return $?
                processes_instances "${SELECTOR_ARGS[@]}"
            fi
            ;;

        ports)
            if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
                show_help inspection
            else
                parse_selector_args "$@" || return $?
                ports_instances "${SELECTOR_ARGS[@]}"
            fi
            ;;

        plan)
            if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
                show_help safety
            else
                parse_plan_args "$@" || return $?
                plan_instances "$PLAN_ACTION" "${PLAN_SELECTORS[@]}"
            fi
            ;;

        doctor)
            if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
                show_help inspection
            else
                doctor
            fi
            ;;

        help)
            show_help "${1:-overview}"
            ;;

        version)
            printf 'FRM %s\n' "$FRM_VERSION"
            ;;

        "")
            show_help overview
            ;;

        *)
            log error "Unknown command: $command"
            printf '\n' >&2
            show_help overview >&2
            return "$EX_GENERAL"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
