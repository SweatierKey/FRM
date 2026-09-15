# shellcheck shell=bash

test_plain_list_does_not_collect_status() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    collect_status() { return 99; }
    FRM_LIST_LONG=false
    FRM_LIST_FORMAT=table
    out="$(list_instances ohs_a)"
    [[ "$out" == 'ohs_a' ]]
)

test_structured_verbose_native_output_stays_on_stderr() (
    source "$FRM"
    local tmp out err
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    err="$tmp/err"
    FRM_STATUS_FORMAT=json
    out="$(emit_native_status_output 'native status output' 2>"$err")"
    [[ -z "$out" ]]
    [[ "$(cat "$err")" == 'native status output' ]]
)

test_opmn_ports_parser() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/bin"
    cat > "$tmp/ohs_a/bin/opmnctl" <<'OPMN'
#!/usr/bin/env bash
cat <<'OUT'
Processes in Instance: ohs_a
ias-component | process-type | pid | status | uid | memused | uptime | ports
ohs1 | OHS | 9293 | Alive | 1 | 2 | 3 | https:10008,https:8452,http:7786
OUT
OPMN
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    out="$(opmn_ports ohs_a)"
    [[ "$out" == 'https:10008,https:8452,http:7786' ]]
)

test_12c_listen_ports_parser() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    mkdir -p "$tmp/ohs_a/config/fmwconfig/components/OHS/ohs_a/moduleconf"
    cat > "$tmp/ohs_a/config/fmwconfig/components/OHS/ohs_a/httpd.conf" <<'CONF'
Listen 7777
  Listen 4443
CONF
    cat > "$tmp/ohs_a/config/fmwconfig/components/OHS/ohs_a/moduleconf/extra.conf" <<'CONF'
Listen 7777
Listen 127.0.0.1:9999
CONF
    out="$(config_listen_ports ohs_a)"
    [[ "$out" == '127.0.0.1:9999,4443,7777' ]]
)

test_force_tty_override() (
    source "$FRM"
    FRM_COLOR=auto
    FORCE_TTY=1
    is_a_tty 1
)

test_debug_status_enables_verbose() (
    source "$FRM"
    local seen=false
    FRM_HANDLERS_FILE=/nonexistent
    debug_info() { return 0; }
    status_instances() {
        if bool_true "$FRM_VERBOSE_STATUS"; then
            seen=true
        fi
        [[ "$seen" == true ]]
    }
    main --debug status >/dev/null 2>&1
)

test_status_debug_option_after_command() (
    source "$FRM"
    local seen_debug=false seen_verbose=false
    FRM_HANDLERS_FILE=/nonexistent
    debug_info() { seen_debug=true; return 0; }
    status_instances() {
        bool_true "$FRM_VERBOSE_STATUS" && seen_verbose=true
        [[ "$seen_debug" == true && "$seen_verbose" == true ]]
    }
    main status --debug >/dev/null 2>&1
)

test_status_exit_code_when_down() (
    source "$FRM"
    local tmp rc
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    FRM_COLOR=never
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    collect_status() {
        STATUS_STATE=DOWN
        STATUS_DETAIL='opmn=Down'
        STATUS_BACKEND=opmn
        STATUS_PID=''
        STATUS_PROCESS_COUNT=''
    }
    status_instances ohs_a >/dev/null 2>&1
    rc=$?
    [[ "$rc" -eq "$EX_STATE" ]]
)

test_opmn_alive() (
    source "$FRM"
    instance_httpd_info() { return 1; }
    reset_status_result
    derive_opmn_status "ohs_test" $'Processes in Instance: ohs_test\nohs1 | OHS | 9293 | Alive' 0
    [[ "$STATUS_STATE" == "RUNNING" ]]
    [[ "$STATUS_PID" == "9293" ]]
    [[ "$STATUS_DETAIL" == "pid=9293 opmn=Alive" ]]
)

test_opmn_down() (
    source "$FRM"
    instance_httpd_info() { return 1; }
    reset_status_result
    derive_opmn_status "ohs_test" $'ohs1 | OHS | N/A | Down' 0
    [[ "$STATUS_STATE" == "DOWN" ]]
    [[ "$STATUS_DETAIL" == "opmn=Down" ]]
)

test_opmn_not_running() (
    source "$FRM"
    instance_httpd_info() { return 1; }
    reset_status_result
    derive_opmn_status "ohs_test" 'opmnctl status: opmn is not running.' 1
    [[ "$STATUS_STATE" == "DOWN" ]]
    [[ "$STATUS_DETAIL" == "opmn not running" ]]
)

test_process_detection_12c() (
    source "$FRM"
    FRM_INSTANCES_DIR=/u01/app/oracle/admin
    ps() {
        cat <<'PS'
3208 1 httpd /u01/app/oracle/product/fmw/ohs/bin/httpd -d /u01/app/oracle/admin/ohs_ais/config/fmwconfig/components/OHS/instances/ohs_ais
3233 3208 httpd /u01/app/oracle/product/fmw/ohs/bin/httpd -d /u01/app/oracle/admin/ohs_ais/config/fmwconfig/components/OHS/instances/ohs_ais
453133 3208 httpd /u01/app/oracle/product/fmw/ohs/bin/httpd -d /u01/app/oracle/admin/ohs_ais/config/fmwconfig/components/OHS/instances/ohs_ais
9999 1 httpd /u01/app/oracle/product/fmw/ohs/bin/httpd -d /u01/app/oracle/admin/ohs_other/config/fmwconfig/components/OHS/instances/ohs_other
PS
    }
    [[ "$(instance_httpd_info ohs_ais)" == "3208 3" ]]
)

test_process_detection_12c_forces_wide_ps() (
    source "$FRM"
    FRM_INSTANCES_DIR=/u01/app/oracle/admin
    ps() {
        local arg wide=false
        for arg in "$@"; do
            [[ "$arg" == "-ww" ]] && wide=true
        done

        if [[ "$wide" == true ]]; then
            cat <<'PS'
7062 1 httpd /u01/app/oracle/product/fmw_12/wlserver/../ohs/bin/httpd -DOHS_MPM_EVENT -d /u01/app/oracle/admin/ohs_cpf_12/config/fmwconfig/components/OHS/instances/ohs_cpf_12 -k start
7070 7062 httpd /u01/app/oracle/product/fmw_12/wlserver/../ohs/bin/httpd -DOHS_MPM_EVENT -d /u01/app/oracle/admin/ohs_cpf_12/config/fmwconfig/components/OHS/instances/ohs_cpf_12 -k start
7078 7062 httpd /u01/app/oracle/product/fmw_12/wlserver/../ohs/bin/httpd -DOHS_MPM_EVENT -d /u01/app/oracle/admin/ohs_cpf_12/config/fmwconfig/components/OHS/instances/ohs_cpf_12 -k start
PS
        else
            # Simulate RHEL7/procps output truncated before the instance path.
            cat <<'PS'
7062 1 httpd /u01/app/oracle/product/fmw_12/wlserver/../ohs/bin/httpd -DOHS_MPM_EVENT -d /u01
7070 7062 httpd /u01/app/oracle/product/fmw_12/wlserver/../ohs/bin/httpd -DOHS_MPM_EVENT -d /u01
7078 7062 httpd /u01/app/oracle/product/fmw_12/wlserver/../ohs/bin/httpd -DOHS_MPM_EVENT -d /u01
PS
        fi
    }
    [[ "$(instance_httpd_info ohs_cpf_12)" == "7062 3" ]]
)

test_process_detection_11g() (
    source "$FRM"
    FRM_INSTANCES_DIR=/u01/app/oracle/admin
    ps() {
        cat <<'PS'
9293 9266 httpd.worker /u01/app/oracle/product/fmw_11119/web/ohs/bin/httpd.worker -DSSL
9299 9293 odl_rotatelogs /u01/app/oracle/product/fmw_11119/web/ohs/bin/odl_rotatelogs /u01/app/oracle/admin/ohs_lfi7_11119/diagnostics/logs/OHS/ohs1/error.log
9302 9293 httpd.worker /u01/app/oracle/product/fmw_11119/web/ohs/bin/httpd.worker -DSSL
9303 9293 httpd.worker /u01/app/oracle/product/fmw_11119/web/ohs/bin/httpd.worker -DSSL
1111 1100 httpd.worker /u01/app/oracle/product/fmw_11119/web/ohs/bin/httpd.worker -DSSL
PS
    }
    [[ "$(instance_httpd_info ohs_lfi7_11119)" == "9293 3" ]]
)


test_uptime_formatting() (
    source "$FRM"
    [[ "$(format_uptime 37)" == "37s" ]]
    [[ "$(format_uptime 277)" == "4m37s" ]]
    [[ "$(format_uptime 11520)" == "3h12m" ]]
    [[ "$(format_uptime 11404800)" == "132d0h" ]]
)

test_process_uptime_uses_master_pid() (
    source "$FRM"
    ps() {
        [[ "$*" == *"-o etimes="* && "$*" == *"-p 4242"* ]] || return 1
        printf '  277\n'
    }
    [[ "$(process_uptime_seconds 4242)" == "277" ]]
)

test_status_table_includes_uptime() (
    source "$FRM"
    local out
    FRM_COLOR=never
    STATUS_STATE=RUNNING
    STATUS_DETAIL='pid=42 opmn=Alive'
    STATUS_UPTIME='4m37s'
    out="$(print_status_table_row ohs_a)"
    [[ "$out" == *"ohs_a"* ]]
    [[ "$out" == *"uptime=4m37s"* ]]
)

test_status_json() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    collect_status() {
        STATUS_STATE=RUNNING
        STATUS_DETAIL='pid=42 opmn=Alive'
        STATUS_BACKEND=opmn
        STATUS_PID=42
        STATUS_PROCESS_COUNT=''
        STATUS_UPTIME='4m37s'
        STATUS_UPTIME_SECONDS=277
    }
    FRM_STATUS_FORMAT=json
    out="$(status_instances ohs_a)"
    [[ "$out" == '[{"instance":"ohs_a","state":"RUNNING","backend":"opmn","pid":"42","httpd_count":"","uptime":"4m37s","uptime_seconds":277,"detail":"pid=42 opmn=Alive"}]' ]]
)

run_test 'plain list avoids status backends' test_plain_list_does_not_collect_status
run_test 'structured verbose output keeps stdout machine-readable' test_structured_verbose_native_output_stays_on_stderr
run_test 'OPMN ports parser' test_opmn_ports_parser
run_test '12c Listen ports parser' test_12c_listen_ports_parser
run_test 'FORCE_TTY override' test_force_tty_override
run_test 'debug status enables verbose native output' test_debug_status_enables_verbose
run_test 'status accepts --debug after command' test_status_debug_option_after_command
run_test 'status returns state exit code for DOWN' test_status_exit_code_when_down
run_test 'OPMN Alive parser' test_opmn_alive
run_test 'OPMN Down parser' test_opmn_down
run_test 'OPMN not-running parser' test_opmn_not_running
run_test '12c httpd process detection' test_process_detection_12c
run_test '12c process detection forces wide ps output' test_process_detection_12c_forces_wide_ps
run_test '11g httpd.worker process detection' test_process_detection_11g
run_test 'uptime formatting' test_uptime_formatting
run_test 'process uptime uses master pid' test_process_uptime_uses_master_pid
run_test 'status table includes uptime' test_status_table_includes_uptime
run_test 'JSON status output' test_status_json
