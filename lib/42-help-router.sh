show_help() {
    local section="${1:-overview}"

    case "$section" in
        --list|list-sections) help_sections ;;
        overview|general) help_overview ;;
        commands) help_commands ;;
        selection|selectors) help_selection ;;
        status) help_status ;;
        lifecycle|start|stop|restart) help_lifecycle ;;
        monitoring|watch) help_monitoring ;;
        inspection|inspect|processes|ps|ports|doctor) help_inspection ;;
        output|color|json|tsv) help_output ;;
        configuration|config|env) help_configuration ;;
        installation|install|completion) help_installation ;;
        safety|dry-run|lock) help_safety ;;
        exit-codes|exit|codes) help_exit_codes ;;
        examples|example) help_examples ;;
        all)
            help_overview
            printf '\n\n'
            help_commands
            printf '\n\n'
            help_selection
            printf '\n\n'
            help_status
            printf '\n\n'
            help_lifecycle
            printf '\n\n'
            help_monitoring
            printf '\n\n'
            help_inspection
            printf '\n\n'
            help_output
            printf '\n\n'
            help_configuration
            printf '\n\n'
            help_installation
            printf '\n\n'
            help_safety
            printf '\n\n'
            help_exit_codes
            printf '\n\n'
            help_examples
            ;;
        *)
            log error "Unknown help section: $section"
            printf '\n'
            help_sections
            return "$EX_GENERAL"
            ;;
    esac
}

###############################################################################
