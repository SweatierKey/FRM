# shellcheck shell=bash

test_configtest_resolves_live_12c_httpd_command() (
    source "$FRM"
    local tmp exe conf dir TEST_EXE
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    exe="$tmp/httpd"
    TEST_EXE="$exe"
    dir="$tmp/config"
    conf="$dir/httpd.conf"
    mkdir -p "$dir"
    : > "$conf"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$exe"
    chmod +x "$exe"

    instance_httpd_args() {
        printf '%s\n' "$TEST_EXE -DOHS_MPM_EVENT -d $dir -k start -f $conf"
    }

    resolve_configtest_command ohs_a
    [[ "${CONFIGTEST_COMMAND[*]}" == "$exe -DOHS_MPM_EVENT -d $dir -f $conf -t" ]]
)


test_configtest_resolves_11g_config_from_instance_tree() (
    source "$FRM"
    local tmp exe conf dir TEST_EXE
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp/admin"
    exe="$tmp/httpd.worker"
    TEST_EXE="$exe"
    dir="$FRM_INSTANCES_DIR/ohs_a/config/OHS/ohs1"
    conf="$dir/httpd.conf"
    mkdir -p "$dir"
    : > "$conf"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$exe"
    chmod +x "$exe"

    instance_httpd_args() { printf '%s\n' "$TEST_EXE -DSSL"; }
    opmn_ohs_component() { printf '%s\n' ohs1; }

    resolve_configtest_command ohs_a
    [[ "${CONFIGTEST_COMMAND[*]}" == "$exe -DSSL -d $dir -f $conf -t" ]]
)


test_configtest_executes_read_only_syntax_check() (
    source "$FRM"
    local tmp exe out TEST_EXE
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    exe="$tmp/httpd"
    TEST_EXE="$exe"
    cat > "$exe" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$*" == *'-t'* ]] || exit 9
printf 'Syntax OK\n'
SCRIPT
    chmod +x "$exe"

    instance_httpd_args() { printf '%s\n' "$TEST_EXE -d $tmp -f $tmp/httpd.conf"; }
    : > "$tmp/httpd.conf"
    FRM_COLOR=never

    out="$(configtest_one ohs_a)"
    [[ "$out" == *'Configtest: ohs_a'* ]]
    [[ "$out" == *'ohs_a configtest OK: Syntax OK'* ]]
)


test_configtest_unavailable_without_reliable_runtime_command() (
    source "$FRM"
    instance_httpd_args() { return 1; }
    configtest_one ohs_a >/dev/null 2>&1
    [[ $? -eq "$EX_UNAVAILABLE" ]]
)


test_inspect_shows_uptime_and_started_at() (
    source "$FRM"
    local out
    build_selection() { SELECTED_INSTANCES=(ohs_a); return 0; }
    instance_family() { printf '%s\n' ohs12; }
    collect_status() {
        STATUS_STATE=RUNNING
        STATUS_DETAIL='pid=42 httpd=6'
        STATUS_BACKEND=process
        STATUS_UPTIME='4m37s'
        STATUS_STARTED_AT='2026-09-16T01:46:12+02:00'
    }
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    custom_handler_exists() { return 1; }
    FRM_INSTANCES_DIR=/tmp/frm-test

    out="$(inspect_instances)"
    [[ "$out" == *'uptime:          4m37s'* ]]
    [[ "$out" == *'started at:      2026-09-16T01:46:12+02:00'* ]]
)



test_ports_verify_matches_instance_httpd_pid() (
    source "$FRM"
    local snapshot out
    snapshot='LISTEN 0 128 0.0.0.0:7777 0.0.0.0:* users:(("httpd",pid=42,fd=7))'
    instance_httpd_pids() { printf '42\n43\n'; }
    out="$(verify_instance_ports ohs_a '7777' "$snapshot")"
    [[ "$out" == *'7777'* ]]
    [[ "$out" == *'LISTEN'* ]]
    [[ "$out" == *'YES'* ]]
    [[ "$out" == *'42,43'* ]]
)


test_ports_verify_detects_missing_listener() (
    source "$FRM"
    instance_httpd_pids() { printf '42\n'; }
    verify_instance_ports ohs_a '7777' '' >/dev/null
    [[ $? -eq "$EX_STATE" ]]
)


test_ports_cli_accepts_verify_flag() (
    source "$FRM"
    parse_ports_args --verify ohs_a
    [[ "$FRM_PORTS_VERIFY" == true ]]
    [[ "${PORT_SELECTORS[*]}" == ohs_a ]]
)


test_nodemanager_detection_uses_root_directory() (
    source "$FRM"
    FRM_INSTANCES_DIR=/u01/app/oracle/admin
    ps() {
        cat <<'PS'
58010 java /u01/app/oracle/product/jdk/bin/java -Dweblogic.RootDirectory=/u01/app/oracle/admin/ohs_a weblogic.NodeManager -v
58011 java /u01/app/oracle/product/jdk/bin/java -Dweblogic.RootDirectory=/u01/app/oracle/admin/ohs_b weblogic.NodeManager -v
PS
    }
    process_uptime_seconds() { [[ "$1" == 58010 ]] && printf '277\n'; }
    [[ "$(instance_nodemanager_info ohs_a)" == '58010 4m37s' ]]
)



test_log_discovery_filters_known_roots() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp/admin"
    mkdir -p "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs"
    mkdir -p "$FRM_INSTANCES_DIR/ohs_a/auditlogs/OHS/ohs_a"
    : > "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs/error_log-1"
    : > "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs/access_log-1"
    : > "$FRM_INSTANCES_DIR/ohs_a/auditlogs/OHS/ohs_a/audit-1.log"

    out="$(discover_log_files ohs_a error)"
    [[ "$out" == *'error_log-1'* ]]
    [[ "$out" != *'access_log-1'* ]]

    out="$(discover_log_files ohs_a audit)"
    [[ "$out" == *'audit-1.log'* ]]
)


test_log_tail_uses_latest_matching_file() (
    source "$FRM"
    local tmp out
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp/admin"
    mkdir -p "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs"
    printf 'old\n' > "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs/error_log-old"
    printf 'new1\nnew2\n' > "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs/error_log-new"
    touch -t 202609150100 "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs/error_log-old"
    touch -t 202609160100 "$FRM_INSTANCES_DIR/ohs_a/servers/ohs_a/logs/error_log-new"
    build_selection() { SELECTED_INSTANCES=(ohs_a); return 0; }
    FRM_LOG_TYPE=error
    FRM_LOG_TAIL=1

    out="$(logs_instances)"
    [[ "$out" == *'error_log-new'* ]]
    [[ "$out" == *'new2'* ]]
    [[ "$out" != *$'\nold\n'* ]]
)


test_logs_cli_parses_type_and_tail() (
    source "$FRM"
    parse_logs_args --type error --tail 100 ohs_a
    [[ "$FRM_LOG_TYPE" == error ]]
    [[ "$FRM_LOG_TAIL" == 100 ]]
    [[ "${LOG_SELECTORS[*]}" == ohs_a ]]
)

run_test 'log discovery filters known roots' test_log_discovery_filters_known_roots
run_test 'logs --tail selects newest file' test_log_tail_uses_latest_matching_file
run_test 'logs CLI parses type and tail' test_logs_cli_parses_type_and_tail
run_test 'ports --verify matches OHS owner pid' test_ports_verify_matches_instance_httpd_pid
run_test 'ports --verify detects missing listener' test_ports_verify_detects_missing_listener
run_test 'ports CLI accepts --verify' test_ports_cli_accepts_verify_flag
run_test 'NodeManager detection uses RootDirectory' test_nodemanager_detection_uses_root_directory
run_test 'configtest resolves live 12c command' test_configtest_resolves_live_12c_httpd_command
run_test 'configtest resolves 11g config root' test_configtest_resolves_11g_config_from_instance_tree
run_test 'configtest executes syntax-only command' test_configtest_executes_read_only_syntax_check
run_test 'configtest returns unavailable when unresolved' test_configtest_unavailable_without_reliable_runtime_command
run_test 'inspect shows uptime and started_at' test_inspect_shows_uptime_and_started_at
