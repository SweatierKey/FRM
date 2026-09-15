# Bash completion for FRM - Fronten Runtime Manager

_frm_complete_instances() {
    local frm_cmd="${1:-frm}"
    "$frm_cmd" list 2>/dev/null
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
        COMPREPLY=( $(compgen -W "$commands --debug --quiet --color --instances-dir --exclude --state --include-skipped --dry-run --confirm --confirm-each --step --yes --wait --no-wait --timeout --poll-interval --sudo --no-sudo --handlers --help --version" -- "$cur") )
        return 0
    fi

    if [[ "$prev" == "--color" ]]; then
        COMPREPLY=( $(compgen -W "auto always never" -- "$cur") )
        return 0
    fi

    if [[ "$prev" == "--sudo" ]]; then
        COMPREPLY=( $(compgen -W "auto always never" -- "$cur") )
        return 0
    fi

    if [[ "$prev" == "--state" ]]; then
        COMPREPLY=( $(compgen -W "RUNNING ACTIVE DOWN STOPPED WARNING UNKNOWN HEALTHY UNHEALTHY" -- "$cur") )
        return 0
    fi

    case "$command" in
        help)
            COMPREPLY=( $(compgen -W "$help_sections --list" -- "$cur") )
            ;;
        plan)
            if [[ "$prev" == "plan" ]]; then
                COMPREPLY=( $(compgen -W "start stop restart" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_frm_complete_instances "$frm_cmd")" -- "$cur") )
            fi
            ;;
        restart)
            if [[ "$prev" == "--strategy" ]]; then
                COMPREPLY=( $(compgen -W "rolling all-at-once" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$(_frm_complete_instances "$frm_cmd") --strategy --state --preserve-state --confirm --confirm-each --step --yes --all --help" -- "$cur") )
            fi
            ;;
        status)
            COMPREPLY=( $(compgen -W "$(_frm_complete_instances "$frm_cmd") --state --json --tsv --summary --verbose --all --help" -- "$cur") )
            ;;
        list)
            COMPREPLY=( $(compgen -W "$(_frm_complete_instances "$frm_cmd") --state --long --json --all --help" -- "$cur") )
            ;;
        watch)
            COMPREPLY=( $(compgen -W "$(_frm_complete_instances "$frm_cmd") --state --interval --no-clear --all --help" -- "$cur") )
            ;;
        start|stop|shutdown|inspect|processes|ps|ports)
            COMPREPLY=( $(compgen -W "$(_frm_complete_instances "$frm_cmd") --state --confirm --confirm-each --step --yes --all --help" -- "$cur") )
            ;;
        *)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            ;;
    esac
}

complete -F _frm frm
complete -F _frm manage_instances_runtime.sh
