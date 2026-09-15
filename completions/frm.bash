# Bash completion for FRM - Fronten Runtime Manager

_frm_complete_instances() {
    local frm_cmd="${1:-frm}"
    "$frm_cmd" list 2>/dev/null
}

_frm_set_compreply() {
    local words="$1"
    local current="$2"
    mapfile -t COMPREPLY < <(compgen -W "$words" -- "$current")
}

_frm() {
    local cur prev command
    local frm_cmd="${COMP_WORDS[0]}"
    local commands="list status start stop shutdown restart watch inspect processes ps ports plan doctor help version"
    local help_sections="overview commands selection status lifecycle monitoring inspection output configuration installation safety exit-codes examples all"

    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    command=""
    local word
    for word in "${COMP_WORDS[@]:1}"; do
        case "$word" in
            list|status|start|stop|shutdown|restart|watch|inspect|processes|ps|ports|plan|doctor|help|version)
                command="$word"
                break
                ;;
        esac
    done

    if (( COMP_CWORD == 1 )); then
        _frm_set_compreply "$commands --debug --quiet --color --instances-dir --exclude --state --include-skipped --dry-run --confirm --confirm-each --step --yes --wait --no-wait --timeout --poll-interval --sudo --no-sudo --handlers --help --version" "$cur"
        return 0
    fi

    if [[ "$prev" == "--color" ]]; then
        _frm_set_compreply "auto always never" "$cur"
        return 0
    fi

    if [[ "$prev" == "--sudo" ]]; then
        _frm_set_compreply "auto always never" "$cur"
        return 0
    fi

    if [[ "$prev" == "--state" ]]; then
        _frm_set_compreply "RUNNING ACTIVE DOWN STOPPED WARNING UNKNOWN HEALTHY UNHEALTHY" "$cur"
        return 0
    fi

    case "$command" in
        help)
            _frm_set_compreply "$help_sections --list" "$cur"
            ;;
        plan)
            if [[ "$prev" == "plan" ]]; then
                _frm_set_compreply "start stop restart" "$cur"
            else
                _frm_set_compreply "$(_frm_complete_instances "$frm_cmd")" "$cur"
            fi
            ;;
        restart)
            if [[ "$prev" == "--strategy" ]]; then
                _frm_set_compreply "rolling all-at-once" "$cur"
            else
                _frm_set_compreply "$(_frm_complete_instances "$frm_cmd") --strategy --state --preserve-state --confirm --confirm-each --step --yes --all --help" "$cur"
            fi
            ;;
        status)
            _frm_set_compreply "$(_frm_complete_instances "$frm_cmd") --state --json --tsv --summary --verbose --all --help" "$cur"
            ;;
        list)
            _frm_set_compreply "$(_frm_complete_instances "$frm_cmd") --state --long --json --all --help" "$cur"
            ;;
        watch)
            _frm_set_compreply "$(_frm_complete_instances "$frm_cmd") --state --interval --no-clear --all --help" "$cur"
            ;;
        start|stop|shutdown|inspect|processes|ps|ports)
            _frm_set_compreply "$(_frm_complete_instances "$frm_cmd") --state --confirm --confirm-each --step --yes --all --help" "$cur"
            ;;
        *)
            _frm_set_compreply "$commands" "$cur"
            ;;
    esac
}

complete -F _frm frm
complete -F _frm manage_instances_runtime.sh
