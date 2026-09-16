# shellcheck shell=bash

test_lifecycle_confirmation_flags_parse() (
    source "$FRM"
    parse_global_options --confirm-each --yes --opmn-mode all restart ohs_a
    [[ "$FRM_CONFIRM_EACH" == true ]]
    [[ "$FRM_ASSUME_YES" == true ]]
    [[ "$FRM_OPMN_MODE" == all ]]
    [[ "${GLOBAL_REST[*]}" == 'restart ohs_a' ]]

    FRM_CONFIRM=false
    FRM_CONFIRM_EACH=false
    FRM_ASSUME_YES=false
    parse_lifecycle_args --confirm --step -y --opmn-mode ohs ohs_a
    [[ "$FRM_CONFIRM" == true ]]
    [[ "$FRM_CONFIRM_EACH" == true ]]
    [[ "$FRM_ASSUME_YES" == true ]]
    [[ "$FRM_OPMN_MODE" == ohs ]]
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
    [[ "$ACTION_DESCRIPTION" == '/usr/bin/systemctl stop ohs_a' || "$ACTION_DESCRIPTION" == '/bin/systemctl stop ohs_a' ]]
)

test_action_backend_opmn() (
    FRM_OPMN_MODE=ohs
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
    [[ "$ACTION_DESCRIPTION" == "$tmp/ohs_a/bin/opmnctl startproc process-type=OHS" ]]
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
    FRM_OPMN_MODE=ohs
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
    [[ "$out" == *"opmnctl stopproc process-type=OHS"* ]]
    [[ "$out" == *"opmnctl startproc process-type=OHS"* ]]
)


test_auto_sudo_checks_exact_command() (
    source "$FRM"
    FRM_SUDO=auto
    local events=""

    is_effective_root() { return 1; }
    sudo() {
        events+="sudo:$*;"
        if [[ "$1" == -n && "$2" == -l ]]; then
            [[ "$3 $4 $5" == '/usr/bin/systemctl stop ohs_a' ]]
            return $?
        fi
        if [[ "$1" == -n ]]; then
            return 0
        fi
        return 99
    }

    run_privileged /usr/bin/systemctl stop ohs_a
    [[ "$events" == 'sudo:-n -l /usr/bin/systemctl stop ohs_a;sudo:-n /usr/bin/systemctl stop ohs_a;' ]]
)

test_auto_sudo_falls_back_to_direct_when_not_allowed() (
    source "$FRM"
    FRM_SUDO=auto
    local tmp log cmd
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    cmd="$tmp/cmd"

    cat > "$cmd" <<EOF
#!/usr/bin/env bash
printf 'direct:%s\n' "\$*" >> "$log"
EOF
    chmod +x "$cmd"

    is_effective_root() { return 1; }
    sudo() {
        if [[ "$1" == -n && "$2" == -l ]]; then
            return 1
        fi
        return 99
    }

    run_privileged "$cmd" alpha beta
    [[ "$(cat "$log")" == 'direct:alpha beta' ]]
)

test_systemd_execute_uses_sudoers_compatible_command() (
    source "$FRM"
    FRM_DRY_RUN=false
    local captured=""

    systemd_unit_exists() { [[ "$1" == 'ohs_a.service' ]]; }
    systemctl_path() { printf '%s\n' /usr/bin/systemctl; }
    run_privileged() { captured="$*"; return 0; }

    execute_action ohs_a stop
    [[ "$captured" == '/usr/bin/systemctl stop ohs_a' ]]
)

test_opmn_stop_uses_stopproc_ohs() (
    FRM_OPMN_MODE=ohs
    source "$FRM"
    local tmp log
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/bin"

    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
exit 0
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a stop
    [[ "$(cat "$log")" == 'stopproc process-type=OHS' ]]
)

test_opmn_start_starts_daemon_when_needed() (
    FRM_OPMN_MODE=ohs
    source "$FRM"
    local tmp log state
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    state="$tmp/state"
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/bin"

    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\$1" in
    status)
        if [[ ! -f "$state" ]]; then
            echo 'opmnctl status: opmn is not running.'
            exit 1
        fi
        echo 'Processes in Instance: ohs_a'
        echo 'ohs1 | OHS | N/A | Down'
        ;;
    start)
        : > "$state"
        ;;
    startproc)
        ;;
esac
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a start
    [[ "$(cat "$log")" == $'status\nstatus\nstart\nstartproc process-type=OHS' ]]
)



test_opmn_auto_uses_all_for_ohs_only_and_persists_across_restart() (
    source "$FRM"
    local tmp log
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    FRM_INSTANCES_DIR="$tmp"
    FRM_OPMN_MODE=auto
    mkdir -p "$tmp/ohs_a/bin"

    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\${1:-}" in
    status)
        echo 'Processes in Instance: ohs_a'
        echo 'ias-component | process-type | pid | status'
        echo 'ohs1 | OHS | 1234 | Alive'
        ;;
    stopall|startall) ;;
esac
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a stop
    [[ "${OPMN_MODE_CACHE[ohs_a]}" == all ]]
    # Simulate the daemon becoming unavailable after stopall.  The cached mode
    # must keep the matching start on startall rather than changing strategy.
    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\${1:-}" in
    status) echo 'opmnctl status: opmn is not running.'; exit 1 ;;
    startall) ;;
esac
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a start
    [[ "$(tail -n 2 "$log")" == $'stopall\nstartall' ]]
)

test_opmn_auto_uses_ohs_scope_for_mixed_instance() (
    source "$FRM"
    local tmp log
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    FRM_INSTANCES_DIR="$tmp"
    FRM_OPMN_MODE=auto
    mkdir -p "$tmp/ohs_a/bin"

    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\${1:-}" in
    status)
        echo 'Processes in Instance: ohs_a'
        echo 'ias-component | process-type | pid | status'
        echo 'ohs1 | OHS | 1234 | Alive'
        echo 'other1 | OID | 5678 | Alive'
        ;;
    stopproc|startproc) ;;
esac
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a stop
    [[ "${OPMN_MODE_CACHE[ohs_a]}" == ohs ]]
    [[ "$(tail -n 1 "$log")" == 'stopproc process-type=OHS' ]]
)

test_opmn_auto_start_is_conservative_when_daemon_down() (
    source "$FRM"
    local tmp log state
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    state="$tmp/state"
    FRM_INSTANCES_DIR="$tmp"
    FRM_OPMN_MODE=auto
    mkdir -p "$tmp/ohs_a/bin"

    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\${1:-}" in
    status)
        if [[ ! -f "$state" ]]; then
            echo 'opmnctl status: opmn is not running.'
            exit 1
        fi
        echo 'Processes in Instance: ohs_a'
        echo 'ohs1 | OHS | N/A | Down'
        ;;
    start) : > "$state" ;;
    startproc) ;;
esac
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a start
    [[ "${OPMN_MODE_CACHE[ohs_a]}" == ohs ]]
    [[ "$(tail -n 3 "$log")" == $'status\nstart\nstartproc process-type=OHS' ]]
)

test_opmn_forced_all_mode() (
    source "$FRM"
    local tmp log
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log="$tmp/log"
    FRM_INSTANCES_DIR="$tmp"
    FRM_OPMN_MODE=all
    mkdir -p "$tmp/ohs_a/bin"

    cat > "$tmp/ohs_a/bin/opmnctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
exit 0
EOF
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    execute_action ohs_a stop
    execute_action ohs_a start
    [[ "$(cat "$log")" == $'stopall\nstartall' ]]
)



test_rolling_restart_fail_fast_by_default() (
    source "$FRM"
    FRM_RESTART_STRATEGY=rolling
    FRM_ON_ERROR=auto
    FRM_DRY_RUN=false
    FRM_LIFECYCLE_SUMMARY=false
    local events=""
    local rc=0

    build_selection() { SELECTED_INSTANCES=(ohs_a ohs_b); return 0; }
    acquire_lifecycle_lock() { return 0; }
    preflight_configtest_instances() { return 0; }
    confirm_lifecycle_batch() { return 0; }
    confirm_lifecycle_instance() { return 0; }
    lifecycle_report_begin() { events+="begin:$1;"; }
    lifecycle_report_finish() { events+="finish:$1:$2;"; }
    lifecycle_report_skip() { events+="skip:$1;"; }
    print_lifecycle_report() { :; }
    stop_one() { events+="stop:$1;"; return 0; }
    start_one() {
        events+="start:$1;"
        [[ "$1" == ohs_a ]] && return "$EX_STATE"
        return 0
    }

    restart_instances >/dev/null 2>&1
    rc=$?
    [[ "$rc" -eq "$EX_STATE" ]]
    [[ "$events" == 'begin:ohs_a;stop:ohs_a;start:ohs_a;finish:ohs_a:FAILED;skip:ohs_b;' ]]
)


test_rolling_restart_can_continue_on_error() (
    source "$FRM"
    FRM_RESTART_STRATEGY=rolling
    FRM_ON_ERROR="continue"
    FRM_DRY_RUN=false
    FRM_LIFECYCLE_SUMMARY=false
    local events=""
    local rc=0

    build_selection() { SELECTED_INSTANCES=(ohs_a ohs_b); return 0; }
    acquire_lifecycle_lock() { return 0; }
    preflight_configtest_instances() { return 0; }
    confirm_lifecycle_batch() { return 0; }
    confirm_lifecycle_instance() { return 0; }
    lifecycle_report_begin() { :; }
    lifecycle_report_finish() { :; }
    lifecycle_report_skip() { :; }
    print_lifecycle_report() { :; }
    stop_one() { events+="stop:$1;"; return 0; }
    start_one() {
        events+="start:$1;"
        [[ "$1" == ohs_a ]] && return "$EX_STATE"
        return 0
    }

    restart_instances >/dev/null 2>&1
    rc=$?
    [[ "$rc" -eq "$EX_STATE" ]]
    [[ "$events" == 'stop:ohs_a;start:ohs_a;stop:ohs_b;start:ohs_b;' ]]
)


test_lifecycle_summary_contains_restart_evidence() (
    source "$FRM"
    FRM_LIFECYCLE_SUMMARY=true
    FRM_DRY_RUN=false
    LIFECYCLE_REPORT_ORDER=(ohs_a)
    LIFECYCLE_RESULT[ohs_a]=OK
    LIFECYCLE_OLD_STATE[ohs_a]=RUNNING
    LIFECYCLE_NEW_STATE[ohs_a]=RUNNING
    LIFECYCLE_OLD_PID[ohs_a]=111
    LIFECYCLE_NEW_PID[ohs_a]=222
    LIFECYCLE_FINAL_UPTIME[ohs_a]=8s
    LIFECYCLE_DURATION[ohs_a]=19
    LIFECYCLE_NOTE[ohs_a]=''
    local out

    out="$(print_lifecycle_report restart)"
    [[ "$out" == *'Lifecycle summary (restart):'* ]]
    [[ "$out" == *'ohs_a'* ]]
    [[ "$out" == *'111'* ]]
    [[ "$out" == *'222'* ]]
    [[ "$out" == *'8s'* ]]
    [[ "$out" == *'total=1 ok=1 failed=0 skipped=0'* ]]
)


test_lifecycle_new_flags_parse() (
    source "$FRM"
    parse_lifecycle_args --on-error continue --no-lifecycle-summary --preflight-configtest ohs_a
    [[ "$FRM_ON_ERROR" == continue ]]
    [[ "$FRM_LIFECYCLE_SUMMARY" == false ]]
    [[ "$FRM_PREFLIGHT_CONFIGTEST" == true ]]
    [[ "${LIFECYCLE_SELECTORS[*]}" == ohs_a ]]
)


test_preflight_configtest_aborts_before_start() (
    source "$FRM"
    FRM_PREFLIGHT_CONFIGTEST=true
    local started=false

    build_selection() { SELECTED_INSTANCES=(ohs_a); return 0; }
    acquire_lifecycle_lock() { return 0; }
    preflight_configtest_instances() { return "$EX_STATE"; }
    confirm_lifecycle_batch() { return 0; }
    start_one() { started=true; return 0; }

    start_instances >/dev/null 2>&1
    [[ $? -eq "$EX_STATE" ]]
    [[ "$started" == false ]]
)

run_test 'rolling restart fail-fast is default' test_rolling_restart_fail_fast_by_default
run_test 'rolling restart can continue on error' test_rolling_restart_can_continue_on_error
run_test 'lifecycle summary includes restart evidence' test_lifecycle_summary_contains_restart_evidence
run_test 'new lifecycle safety flags parse' test_lifecycle_new_flags_parse
run_test 'configtest preflight aborts before lifecycle' test_preflight_configtest_aborts_before_start
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
run_test 'auto sudo checks exact command-specific rule' test_auto_sudo_checks_exact_command
run_test 'auto sudo falls back to direct execution when command is not allowed' test_auto_sudo_falls_back_to_direct_when_not_allowed
run_test 'systemd lifecycle uses sudoers-compatible bare unit command' test_systemd_execute_uses_sudoers_compatible_command
run_test 'OPMN stop uses stopproc process-type=OHS' test_opmn_stop_uses_stopproc_ohs
run_test 'OPMN start starts daemon when needed then startproc OHS' test_opmn_start_starts_daemon_when_needed
run_test 'OPMN auto uses stopall/startall for OHS-only instances and preserves mode' test_opmn_auto_uses_all_for_ohs_only_and_persists_across_restart
run_test 'OPMN auto scopes to OHS for mixed-process instances' test_opmn_auto_uses_ohs_scope_for_mixed_instance
run_test 'OPMN auto standalone start is conservative when daemon is down' test_opmn_auto_start_is_conservative_when_daemon_down
run_test 'OPMN all mode forces stopall/startall' test_opmn_forced_all_mode
