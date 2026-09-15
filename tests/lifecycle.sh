# shellcheck shell=bash

test_lifecycle_confirmation_flags_parse() (
    source "$FRM"
    parse_global_options --confirm-each --yes restart ohs_a
    [[ "$FRM_CONFIRM_EACH" == true ]]
    [[ "$FRM_ASSUME_YES" == true ]]
    [[ "${GLOBAL_REST[*]}" == 'restart ohs_a' ]]

    FRM_CONFIRM=false
    FRM_CONFIRM_EACH=false
    FRM_ASSUME_YES=false
    parse_lifecycle_args --confirm --step -y ohs_a
    [[ "$FRM_CONFIRM" == true ]]
    [[ "$FRM_CONFIRM_EACH" == true ]]
    [[ "$FRM_ASSUME_YES" == true ]]
    [[ "${LIFECYCLE_SELECTORS[*]}" == 'ohs_a' ]]
)

test_rolling_confirm_each_order() (
    source "$FRM"
    FRM_RESTART_STRATEGY=rolling
    FRM_CONFIRM_EACH=true
    FRM_CONFIRM=false
    FRM_ASSUME_YES=false
    FRM_DRY_RUN=false
    local events=""

    build_selection() { SELECTED_INSTANCES=(ohs_a ohs_b); return 0; }
    acquire_lifecycle_lock() { return 0; }
    confirm_lifecycle_batch() { return 0; }
    confirm_lifecycle_instance() {
        events+="confirm:$1:$2;"
        return 0
    }
    stop_one() { events+="stop:$1;"; return 0; }
    start_one() { events+="start:$1;"; return 0; }

    restart_instances >/dev/null 2>&1
    [[ "$events" == 'confirm:restart:ohs_a;stop:ohs_a;start:ohs_a;confirm:restart:ohs_b;stop:ohs_b;start:ohs_b;' ]]
)

test_rolling_cancel_before_next_instance() (
    source "$FRM"
    FRM_RESTART_STRATEGY=rolling
    FRM_CONFIRM_EACH=true
    FRM_CONFIRM=false
    FRM_ASSUME_YES=false
    FRM_DRY_RUN=false
    local events=""
    local confirmations=0
    local rc=0

    build_selection() { SELECTED_INSTANCES=(ohs_a ohs_b); return 0; }
    acquire_lifecycle_lock() { return 0; }
    confirm_lifecycle_batch() { return 0; }
    confirm_lifecycle_instance() {
        confirmations=$((confirmations + 1))
        events+="confirm:$2;"
        (( confirmations == 1 )) && return 0
        return "$EX_CANCELLED"
    }
    stop_one() { events+="stop:$1;"; return 0; }
    start_one() { events+="start:$1;"; return 0; }

    restart_instances >/dev/null 2>&1
    rc=$?
    [[ "$rc" -eq "$EX_CANCELLED" ]]
    [[ "$events" == 'confirm:ohs_a;stop:ohs_a;start:ohs_a;confirm:ohs_b;' ]]
)

test_all_at_once_confirmation_is_preflight() (
    source "$FRM"
    FRM_RESTART_STRATEGY=all-at-once
    FRM_CONFIRM_EACH=true
    FRM_CONFIRM=false
    FRM_ASSUME_YES=false
    FRM_DRY_RUN=false
    local events=""
    local confirmations=0
    local rc=0

    build_selection() { SELECTED_INSTANCES=(ohs_a ohs_b); return 0; }
    acquire_lifecycle_lock() { return 0; }
    confirm_lifecycle_batch() { return 0; }
    confirm_lifecycle_instance() {
        confirmations=$((confirmations + 1))
        events+="confirm:$2;"
        (( confirmations == 1 )) && return 0
        return "$EX_CANCELLED"
    }
    stop_one() { events+="stop:$1;"; return 0; }
    start_one() { events+="start:$1;"; return 0; }

    restart_instances >/dev/null 2>&1
    rc=$?
    [[ "$rc" -eq "$EX_CANCELLED" ]]
    [[ "$events" == 'confirm:ohs_a;confirm:ohs_b;' ]]
)

test_yes_bypasses_confirmation() (
    source "$FRM"
    FRM_CONFIRM=true
    FRM_CONFIRM_EACH=true
    FRM_ASSUME_YES=true
    FRM_DRY_RUN=false
    ask_confirmation() { return 99; }
    confirm_lifecycle_batch restart ohs_a ohs_b
    confirm_lifecycle_instance restart ohs_a 1 2
)

test_lifecycle_preserves_unavailable_exit_code() (
    source "$FRM"
    build_selection() { SELECTED_INSTANCES=(ohs_a); return 0; }
    acquire_lifecycle_lock() { return 0; }
    start_one() { return "$EX_UNAVAILABLE"; }
    start_instances >/dev/null 2>&1
    [[ $? -eq "$EX_UNAVAILABLE" ]]
)

test_invalid_restart_strategy_fails_even_in_dry_run() (
    source "$FRM"
    FRM_RESTART_STRATEGY=invalid
    FRM_DRY_RUN=true
    build_selection() { SELECTED_INSTANCES=(ohs_a); return 0; }
    acquire_lifecycle_lock() { return 0; }
    restart_instances >/dev/null 2>&1
    [[ $? -eq "$EX_GENERAL" ]]
)

test_zero_poll_interval_rejected() (
    source "$FRM"
    parse_global_options --poll-interval 0 status >/dev/null 2>&1
    [[ $? -eq "$EX_GENERAL" ]]
)

test_systemd_action_backend() (
    source "$FRM"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/startNodeManager.sh"
    systemd_unit_exists() { [[ "$1" == "ohs_a.service" ]]; }
    resolve_action_backend ohs_a stop
    [[ "$ACTION_BACKEND" == systemd ]]
    [[ "$ACTION_DESCRIPTION" == 'systemctl stop ohs_a.service' ]]
)

test_action_backend_opmn() (
    source "$FRM"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    resolve_action_backend ohs_a start
    [[ "$ACTION_BACKEND" == opmn ]]
    [[ "$ACTION_DESCRIPTION" == "$tmp/ohs_a/bin/opmnctl start" ]]
)

test_action_handler_precedence() (
    source "$FRM"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    ohs_a_start() { :; }
    resolve_action_backend ohs_a start
    [[ "$ACTION_BACKEND" == handler ]]
)

test_restart_dry_run_shows_stop_and_start() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    FRM_DRY_RUN=true
    FRM_COLOR=never
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    acquire_lifecycle_lock() { return 0; }
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    out="$(restart_instances ohs_a)"
    [[ "$out" == *"opmnctl stop"* ]]
    [[ "$out" == *"opmnctl start"* ]]
)

run_test 'lifecycle confirmation flags parse' test_lifecycle_confirmation_flags_parse
run_test 'rolling confirm-each preserves instance atomicity' test_rolling_confirm_each_order
run_test 'rolling cancellation occurs between instances' test_rolling_cancel_before_next_instance
run_test 'all-at-once confirmation preflights before state changes' test_all_at_once_confirmation_is_preflight
run_test '--yes bypasses lifecycle confirmations' test_yes_bypasses_confirmation
run_test 'lifecycle preserves unavailable exit code' test_lifecycle_preserves_unavailable_exit_code
run_test 'invalid restart strategy fails in dry-run' test_invalid_restart_strategy_fails_even_in_dry_run
run_test 'zero poll interval is rejected' test_zero_poll_interval_rejected
run_test 'systemd lifecycle backend resolution' test_systemd_action_backend
run_test 'OPMN lifecycle backend resolution' test_action_backend_opmn
run_test 'custom handler precedence' test_action_handler_precedence
run_test 'restart dry-run shows stop and start' test_restart_dry_run_shows_stop_and_start
