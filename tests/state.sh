# shellcheck shell=bash

test_state_filter_aliases() (
    source "$FRM"
    STATE_FILTERS=()
    add_state_filter active
    add_state_filter stopped
    [[ "${STATE_FILTERS[*]}" == 'RUNNING DOWN' ]]
)

test_state_filter_after_inspection_command() (
    source "$FRM"
    STATE_FILTERS=()
    parse_selector_args --state DOWN 'ohs_*'
    [[ "${STATE_FILTERS[*]}" == DOWN ]]
    [[ "${SELECTOR_ARGS[*]}" == 'ohs_*' ]]
)

test_plan_state_filter_parser() (
    source "$FRM"
    STATE_FILTERS=()
    parse_plan_args restart --state ACTIVE 'ohs_*'
    [[ "$PLAN_ACTION" == restart ]]
    [[ "${STATE_FILTERS[*]}" == RUNNING ]]
    [[ "${PLAN_SELECTORS[*]}" == 'ohs_*' ]]
)

test_state_filter_selection_snapshot() (
    source "$FRM"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    local n
    for n in ohs_a ohs_b ohs_c; do
        mkdir -p "$tmp/$n/bin"
        : > "$tmp/$n/bin/opmnctl"
        chmod +x "$tmp/$n/bin/opmnctl"
    done
    collect_status() {
        case "$1" in
            ohs_a|ohs_c) STATUS_STATE=RUNNING ;;
            ohs_b) STATUS_STATE=DOWN ;;
        esac
    }
    STATE_FILTERS=(RUNNING)
    build_selection 'ohs_*'
    [[ "${SELECTED_INSTANCES[*]}" == 'ohs_a ohs_c' ]]
)

test_state_filter_unhealthy() (
    source "$FRM"
    STATE_FILTERS=(UNHEALTHY)
    state_matches_filters DOWN
    state_matches_filters WARNING
    state_matches_filters UNKNOWN
    ! state_matches_filters RUNNING
)

test_empty_state_filter_lifecycle_is_noop() (
    source "$FRM"
    build_selection() { SELECTED_INSTANCES=(); return 0; }
    acquire_lifecycle_lock() { return 99; }
    start_instances >/dev/null 2>&1
    [[ $? -eq 0 ]]
)

test_restart_preserve_state_cli() (
    source "$FRM"
    FRM_HANDLERS_FILE=/nonexistent
    debug_info() { return 0; }
    local captured=""
    restart_instances() {
        captured="${STATE_FILTERS[*]}"
        [[ "$captured" == RUNNING ]]
    }
    main restart --preserve-state 'ohs_*' >/dev/null 2>&1
)

test_state_filter_after_lifecycle_command() (
    source "$FRM"
    STATE_FILTERS=()
    parse_lifecycle_args --state ACTIVE 'ohs_*'
    [[ "${STATE_FILTERS[*]}" == RUNNING ]]
    [[ "${LIFECYCLE_SELECTORS[*]}" == 'ohs_*' ]]
)

run_test 'state filter aliases' test_state_filter_aliases
run_test 'state filter accepted after inspection command' test_state_filter_after_inspection_command
run_test 'plan accepts state filter' test_plan_state_filter_parser
run_test 'state filter selection snapshot' test_state_filter_selection_snapshot
run_test 'UNHEALTHY state filter' test_state_filter_unhealthy
run_test 'empty state-filter lifecycle is a no-op' test_empty_state_filter_lifecycle_is_noop
run_test 'restart --preserve-state maps to RUNNING snapshot' test_restart_preserve_state_cli
run_test 'state filter accepted after lifecycle command' test_state_filter_after_lifecycle_command
