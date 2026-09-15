set -o pipefail

FRM_VERSION="0.1.1"

###############################################################################
# Defaults / environment
###############################################################################

FRM_INSTANCES_DIR="${FRM_INSTANCES_DIR:-/u01/app/oracle/admin}"
FRM_DEBUG="${FRM_DEBUG:-false}"
FRM_QUIET="${FRM_QUIET:-false}"
FRM_COLOR="${FRM_COLOR:-auto}"              # auto|always|never
FRM_DRY_RUN="${FRM_DRY_RUN:-false}"
FRM_WAIT="${FRM_WAIT:-true}"
FRM_TIMEOUT="${FRM_TIMEOUT:-60}"
FRM_POLL_INTERVAL="${FRM_POLL_INTERVAL:-2}"
FRM_SUDO="${FRM_SUDO:-auto}"                # auto|always|never
FRM_INCLUDE_SKIPPED="${FRM_INCLUDE_SKIPPED:-false}"
FRM_LOCK_FILE="${FRM_LOCK_FILE:-/tmp/frm-${UID}.lock}"
FRM_HANDLERS_FILE="${FRM_HANDLERS_FILE:-${HOME:-}/.config/frm/handlers.sh}"
FRM_VERBOSE_STATUS="false"
FRM_STATUS_FORMAT="table"                    # table|json|tsv
FRM_STATUS_SUMMARY="false"
FRM_LIST_LONG="false"
FRM_LIST_FORMAT="table"
FRM_WATCH_INTERVAL="${FRM_WATCH_INTERVAL:-5}"
FRM_WATCH_CLEAR="true"
FRM_RESTART_STRATEGY="rolling"               # rolling|all-at-once
FRM_CONFIRM="${FRM_CONFIRM:-false}"
FRM_CONFIRM_EACH="${FRM_CONFIRM_EACH:-false}"
FRM_ASSUME_YES="${FRM_ASSUME_YES:-false}"
FRM_PRESERVE_STATE="${FRM_PRESERVE_STATE:-false}"

# Backwards compatibility with the earlier script.
FORCE_TTY="${FORCE_TTY:-false}"

DEFAULT_SKIP_WORDS=(
    "old"
    "ritm"
    "bck"
    "backup"
    "bk"
    "bkp"
    "bckup"
    "bckp"
    "bkup"
    "spenta"
)

SKIP_WORDS=("${DEFAULT_SKIP_WORDS[@]}")
if [[ -n "${FRM_SKIP_WORDS:-}" ]]; then
    # Space-delimited override, intentionally simple for Bash 4.x portability.
    read -r -a SKIP_WORDS <<< "$FRM_SKIP_WORDS"
fi
EXCLUDE_PATTERNS=()
STATE_FILTERS=()
SELECTED_INSTANCES=()

# Status result globals.
STATUS_STATE=""
STATUS_DETAIL=""
STATUS_BACKEND=""
STATUS_PID=""
STATUS_PROCESS_COUNT=""
STATUS_RAW=""
STATUS_RC=0

# Action backend result globals.
ACTION_BACKEND=""
ACTION_DESCRIPTION=""

# Exit codes.
EX_OK=0
EX_GENERAL=1
EX_STATE=2
EX_SELECTION=3
EX_UNAVAILABLE=4
EX_LOCKED=5
EX_CANCELLED=6

###############################################################################
# Generic helpers
###############################################################################

bool_true() {
    case "${1:-false}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

is_non_negative_number() {
    [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_positive_number() {
    local value="${1:-}"
    is_non_negative_number "$value" || return 1
    awk -v value="$value" 'BEGIN { exit !(value > 0) }'
}

is_positive_integer() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

is_real_tty() {
    local fd="${1:-1}"
    [[ -t "$fd" ]]
}

force_tty_enabled() {
    bool_true "$FORCE_TTY"
}

is_a_tty() {
    local fd="${1:-1}"

    case "$FRM_COLOR" in
        always) return 0 ;;
        never)  return 1 ;;
        auto)
            force_tty_enabled || is_real_tty "$fd"
            ;;
        *)
            return 1
            ;;
    esac
}

json_escape() {
    local s="${1:-}"
    local out=""
    local ch=""
    local i=0

    # Character-by-character escaping is intentionally used instead of nested
    # parameter substitutions because Bash 4.2 compatibility mode handles
    # backslashes differently from newer Bash releases.
    for (( i=0; i<${#s}; i++ )); do
        ch="${s:i:1}"
        # SC1003 is a false positive here: the single-quoted Bash literal
        # intentionally appends two backslashes for JSON escaping.
        # shellcheck disable=SC1003
        case "$ch" in
            '"') out+='\"' ;;
            \\) out+='\\' ;;
            $'\n') out+='\n' ;;
            $'\r') out+='\r' ;;
            $'\t') out+='\t' ;;
            *) out+="$ch" ;;
        esac
    done

    printf '%s' "$out"
}

###############################################################################
# Logging
###############################################################################

log() {
    local level="${1:-info}"
    local message="${2:-}"
    local color=""
    local reset='\033[0m'
    local fd=1

    case "$level" in
        shutdown) color='\033[35m' ;;
        start)    color='\033[34m' ;;
        status)   color='\033[37m' ;;
        error)    color='\033[31m' ;;
        warning)  color='\033[33m' ;;
        success)  color='\033[32m' ;;
        info)     color='\033[36m' ;;
        debug)
            bool_true "$FRM_DEBUG" || return 0
            color='\033[90m'
            ;;
        *)
            printf 'Unknown log level: %s\n' "$level" >&2
            return 1
            ;;
    esac

    case "$level" in
        debug|error|warning) fd=2 ;;
    esac

    if bool_true "$FRM_QUIET"; then
        case "$level" in
            error|warning) ;;
            *) return 0 ;;
        esac
    fi

    if is_a_tty "$fd"; then
        if (( fd == 2 )); then
            printf '%b%s%b\n' "$color" "$message" "$reset" >&2
        else
            printf '%b%s%b\n' "$color" "$message" "$reset"
        fi
    else
        if (( fd == 2 )); then
            printf '%s\n' "$message" >&2
        else
            printf '%s\n' "$message"
        fi
    fi
}

###############################################################################
# Optional handler file
###############################################################################

load_handlers_file() {
    if [[ -n "$FRM_HANDLERS_FILE" && -f "$FRM_HANDLERS_FILE" ]]; then
        log debug "Loading handlers file: $FRM_HANDLERS_FILE"
        # shellcheck disable=SC1090
        . "$FRM_HANDLERS_FILE"
    else
        log debug "No handlers file loaded: $FRM_HANDLERS_FILE"
    fi
}

custom_handler_exists() {
    command -v "$1" >/dev/null 2>&1
}

###############################################################################
# Discovery
###############################################################################

validate_instances_dir() {
    if [[ ! -d "$FRM_INSTANCES_DIR" ]]; then
        log error "Instances directory does not exist: $FRM_INSTANCES_DIR"
        return "$EX_UNAVAILABLE"
    fi
}

systemd_unit_exists() {
    local unit="$1"
    local load_state=""

    command -v systemctl >/dev/null 2>&1 || return 1

    load_state="$(systemctl show -p LoadState "$unit" 2>/dev/null)" || return 1
    [[ -n "$load_state" && "$load_state" != "LoadState=not-found" ]]
}

sysv_script_path() {
    local instance="$1"

    if [[ -x "/etc/init.d/$instance" ]]; then
        printf '%s\n' "/etc/init.d/$instance"
        return 0
    fi

    if [[ -x "/etc/rc.d/init.d/$instance" ]]; then
        printf '%s\n' "/etc/rc.d/init.d/$instance"
        return 0
    fi

    return 1
}

instance_is_candidate() {
    local path="$1"
    local instance="${path##*/}"

    [[ -d "$path" ]] || return 1

    [[ -x "$path/bin/opmnctl" ]] && return 0
    [[ -f "$path/bin/startNodeManager.sh" ]] && return 0
    [[ -d "$path/config/OHS" ]] && return 0
    [[ -d "$path/config/fmwconfig/components/OHS" ]] && return 0
    [[ -d "$path/config/fmwconfig/components/OHS/instances" ]] && return 0
    systemd_unit_exists "${instance}.service" && return 0
    sysv_script_path "$instance" >/dev/null 2>&1 && return 0

    return 1
}

should_skip_instance() {
    local instance="$1"
    local word
    local instance_lower="${instance,,}"

    bool_true "$FRM_INCLUDE_SKIPPED" && return 1

    for word in "${SKIP_WORDS[@]}"; do
        if [[ "$instance_lower" == *"${word,,}"* ]]; then
            log debug "Skipping instance $instance due to skip word: $word"
            return 0
        fi
    done

    return 1
}

instance_family() {
    local instance="$1"
    local root="$FRM_INSTANCES_DIR/$instance"

    if [[ -x "$root/bin/opmnctl" ]]; then
        printf '%s\n' "11g-opmn"
    elif [[ -d "$root/config/fmwconfig/components/OHS" || -f "$root/bin/startNodeManager.sh" ]]; then
        printf '%s\n' "12c"
    else
        printf '%s\n' "unknown"
    fi
}

instance_list() {
    local path
    local instance

    validate_instances_dir || return $?

    log debug "Generating instance list from $FRM_INSTANCES_DIR"

    for path in "$FRM_INSTANCES_DIR"/*; do
        [[ -d "$path" ]] || continue

        instance="${path##*/}"

        if ! instance_is_candidate "$path"; then
            log debug "Ignoring non-OHS directory: $instance"
            continue
        fi

        should_skip_instance "$instance" && continue

        log debug "Adding instance to list: $instance"
        printf '%s\n' "$instance"
    done
}

###############################################################################
# Selection
###############################################################################

matches_exclusion() {
    local instance="$1"
    local pattern

    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        # Intentional shell-pattern matching for --exclude.
        # shellcheck disable=SC2053
        if [[ "$instance" == $pattern ]]; then
            return 0
        fi
    done

    return 1
}

normalize_state_filter() {
    local state="${1^^}"
    state="${state//_/-}"

    case "$state" in
        RUNNING|ACTIVE|UP) printf '%s\n' RUNNING ;;
        DOWN|STOPPED|INACTIVE|OFFLINE) printf '%s\n' DOWN ;;
        WARNING|WARN) printf '%s\n' WARNING ;;
        UNKNOWN) printf '%s\n' UNKNOWN ;;
        HEALTHY) printf '%s\n' RUNNING ;;
        UNHEALTHY|NOT-RUNNING) printf '%s\n' UNHEALTHY ;;
        *) return 1 ;;
    esac
}

add_state_filter() {
    local value="$1"
    local item normalized
    local -a items=()

    IFS=',' read -r -a items <<< "$value"
    for item in "${items[@]}"; do
        [[ -n "$item" ]] || continue
        normalized="$(normalize_state_filter "$item")" || {
            log error "Invalid state filter: $item (use RUNNING, DOWN, WARNING, UNKNOWN, HEALTHY, UNHEALTHY)"
            return "$EX_GENERAL"
        }
        STATE_FILTERS+=("$normalized")
    done
}

state_matches_filters() {
    local state="$1"
    local filter

    (( ${#STATE_FILTERS[@]} == 0 )) && return 0

    for filter in "${STATE_FILTERS[@]}"; do
        case "$filter" in
            UNHEALTHY)
                [[ "$state" != RUNNING ]] && return 0
                ;;
            *)
                [[ "$state" == "$filter" ]] && return 0
                ;;
        esac
    done

    return 1
}

apply_state_filters_to_selection() {
    local instance
    local -a filtered=()

    (( ${#STATE_FILTERS[@]} == 0 )) && return 0

    log debug "Applying state filter snapshot: ${STATE_FILTERS[*]}"

    for instance in "${SELECTED_INSTANCES[@]}"; do
        collect_status "$instance" false
        log debug "State-filter snapshot: $instance=$STATUS_STATE"
        if state_matches_filters "$STATUS_STATE"; then
            filtered+=("$instance")
        fi
    done

    SELECTED_INSTANCES=("${filtered[@]}")
    log debug "State-filtered instance count: ${#SELECTED_INSTANCES[@]}"
}

build_selection() {
    local -a detected_instances=()
    local -a selectors=("$@")
    local -A seen=()
    local selector
    local instance
    local matched
    local rc=0

    SELECTED_INSTANCES=()

    validate_instances_dir || return $?
    mapfile -t detected_instances < <(instance_list)

    if (( ${#detected_instances[@]} == 0 )); then
        log warning "No OHS instances detected in $FRM_INSTANCES_DIR"
        return "$EX_SELECTION"
    fi

    if (( ${#selectors[@]} == 0 )); then
        selectors=("*")
        log debug "No instance selectors specified: selecting all detected instances"
    fi

    if [[ "${selectors[0]}" == "--all" ]]; then
        if (( ${#selectors[@]} != 1 )); then
            log error "--all cannot be combined with other instance selectors"
            return "$EX_SELECTION"
        fi
        selectors=("*")
    fi

    for selector in "${selectors[@]}"; do
        matched=false

        for instance in "${detected_instances[@]}"; do
            # Intentional shell-pattern matching for instance selectors.
            # shellcheck disable=SC2053
            if [[ "$instance" == $selector ]]; then
                matched=true

                if matches_exclusion "$instance"; then
                    log debug "Excluded instance by pattern: $instance"
                    continue
                fi

                if [[ -z "${seen[$instance]+x}" ]]; then
                    SELECTED_INSTANCES+=("$instance")
                    seen["$instance"]=1
                fi
            fi
        done

        if [[ "$matched" == false && "$selector" != "*" ]]; then
            log error "No detected instance matches selector: $selector"
            rc="$EX_SELECTION"
        fi
    done

    if (( rc != 0 )); then
        SELECTED_INSTANCES=()
        log error "Instance selection failed. No operation will be performed."
        return "$rc"
    fi

    if (( ${#SELECTED_INSTANCES[@]} == 0 )); then
        log warning "Selection is empty after exclusions"
        return "$EX_SELECTION"
    fi

    apply_state_filters_to_selection || return $?

    log debug "Selected instance count: ${#SELECTED_INSTANCES[@]}"
    for instance in "${SELECTED_INSTANCES[@]}"; do
        log debug "Selected instance: $instance"
    done
}

###############################################################################
