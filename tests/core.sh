# shellcheck shell=bash

test_syntax() {
    bash -n "$FRM"
}

test_zero_watch_interval_rejected() (
    source "$FRM"
    parse_watch_args --interval 0 >/dev/null 2>&1
    [[ $? -eq "$EX_GENERAL" ]]
)

test_json_escape() (
    # shellcheck source=../frm
    source "$FRM"
    [[ "$(json_escape $'a"b\\c\nd')" == 'a\"b\\c\nd' ]]
)

test_discovery_filters_non_ohs_and_skip() (
    source "$FRM"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    FRM_INCLUDE_SKIPPED=false
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }

    mkdir -p "$tmp/ohs_a/bin" "$tmp/ohs_b/bin" "$tmp/random_dir" "$tmp/ohs_backup/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"
    : > "$tmp/ohs_b/bin/startNodeManager.sh"
    : > "$tmp/ohs_backup/bin/opmnctl"
    chmod +x "$tmp/ohs_backup/bin/opmnctl"

    [[ "$(instance_list)" == $'ohs_a\nohs_b' ]]
)

test_selection_glob_and_exclude() (
    source "$FRM"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }

    local n
    for n in ohs_a_11119 ohs_b_11119 ohs_c_711; do
        mkdir -p "$tmp/$n/bin"
        : > "$tmp/$n/bin/opmnctl"
        chmod +x "$tmp/$n/bin/opmnctl"
    done

    EXCLUDE_PATTERNS=('*_711')
    build_selection 'ohs_*'
    [[ "${SELECTED_INSTANCES[*]}" == 'ohs_a_11119 ohs_b_11119' ]]
)

test_selection_failure_is_atomic() (
    source "$FRM"
    local tmp rc
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    FRM_INSTANCES_DIR="$tmp"
    systemd_unit_exists() { return 1; }
    sysv_script_path() { return 1; }
    mkdir -p "$tmp/ohs_a/bin"
    : > "$tmp/ohs_a/bin/opmnctl"
    chmod +x "$tmp/ohs_a/bin/opmnctl"

    build_selection ohs_a does_not_exist >/dev/null 2>&1
    rc=$?
    [[ "$rc" -eq "$EX_SELECTION" ]]
    (( ${#SELECTED_INSTANCES[@]} == 0 ))
)

test_help_sections() (
    source "$FRM"
    local out
    out="$(show_help selection)"
    [[ "$out" == *"SELECTION"* ]]
    [[ "$out" == *"--exclude"* ]]
)

test_no_arg_help() (
    source "$FRM"
    local out rc
    FRM_HANDLERS_FILE=/nonexistent
    out="$(main 2>/dev/null)"
    rc=$?
    [[ "$rc" -eq 0 ]]
    [[ "$out" == *"Fronten Runtime Manager"* ]]
)

run_test 'bash syntax' test_syntax
run_test 'zero watch interval is rejected' test_zero_watch_interval_rejected
run_test 'JSON escaping' test_json_escape
run_test 'discovery filters non-OHS and skip words' test_discovery_filters_non_ohs_and_skip
run_test 'glob selection with exclusion' test_selection_glob_and_exclude
run_test 'selection failure is atomic' test_selection_failure_is_atomic
run_test 'help section filtering' test_help_sections
run_test 'no-argument overview help' test_no_arg_help
