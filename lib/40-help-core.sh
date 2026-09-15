# Help
###############################################################################

help_sections() {
    cat <<'EOF_HELP'
Available help sections:
  overview       What FRM does and command synopsis
  commands       Command reference
  selection      Instance selectors, globs and exclusions
  status         Status backends and output formats
  lifecycle      Start/stop/restart behavior and verification
  monitoring     watch behavior and runtime polling
  inspection     inspect/processes/ports/doctor reference
  output         Color, JSON, TSV, verbose and pager usage
  configuration  Environment variables and handlers file
  installation   Install, completion and compatibility launcher
  safety         Locks, dry-run, restart strategies and sudo
  exit-codes     Exit status contract for automation
  examples       Practical command examples
  all            Print every section

Examples:
  frm help status
  frm --help selection
  frm help all | less
EOF_HELP
}

help_overview() {
    cat <<EOF_HELP
FRM $FRM_VERSION - Fronten Runtime Manager

Manage Oracle HTTP Server runtimes discovered under an Oracle admin directory.
FRM supports mixed estates, including OHS 11g/OPMN and OHS 12c/systemd/SysV,
and validates runtime state against real httpd/httpd.worker processes.

Synopsis:
  frm [GLOBAL-OPTIONS] COMMAND [COMMAND-OPTIONS] [INSTANCE|GLOB ...]
  frm debug COMMAND ...              # compatibility form for --debug

Core commands:
  list       Discover instances
  status     Compact or structured runtime status
  start      Start selected instances and verify RUNNING
  stop       Stop selected instances and verify DOWN
  shutdown   Alias for stop
  restart    Restart selected instances
  watch      Continuously refresh status
  inspect    Show detection/backend details
  processes  Show the attributed OHS process tree (alias: ps)
  ports      Discover OHS listener ports
  plan       Show lifecycle commands without executing them
  doctor     Diagnose FRM and the host
  help       Detailed help by macro section
  version    Print FRM version

Run:
  frm help --list
  frm help all
EOF_HELP
}

help_commands() {
    cat <<'EOF_HELP'
COMMANDS

  list [--long] [--json] [selectors...]
      List detected OHS instances. --long adds family/backend/path.

  status [--json|--tsv] [--summary] [--verbose] [--debug] [selectors...]
      Show current runtime state. Table output is compact by default.
      --verbose emits native backend output before the derived state.

  start [lifecycle-options] [selectors...]
      Start selected instances. Already-running instances are left alone.

  stop|shutdown [lifecycle-options] [selectors...]
      Stop selected instances. Already-down instances are left alone.

  restart [--strategy rolling|all-at-once] [lifecycle-options] [selectors...]
      Restart selected instances. rolling is the default and safest strategy.

  watch [--interval SEC] [--no-clear] [selectors...]
      Refresh compact status until interrupted with Ctrl-C.

  inspect [selectors...]
      Show instance family, path, state, selected status backend and available
      control mechanisms.

  processes|ps [selectors...]
      Show the OHS master/workers and instance-attributed helper processes.

  ports [selectors...]
      For OPMN, parse the ports column from `opmnctl status -l`. For 12c,
      collect unique Listen directives under the instance OHS configuration.

  plan start|stop|restart [selectors...]
      Resolve and display the exact lifecycle backend/command without running it.

  doctor
      Check dependencies, runtime discovery, handlers and TTY/color behavior.

  help [SECTION]
      Show detailed help. Use `frm help --list` for section names.

  version
      Print version.
EOF_HELP
}

help_selection() {
    cat <<'EOF_HELP'
SELECTION

Selectors are positional instance names or shell-style glob patterns.
Without selectors, FRM selects every detected instance.

  frm status ohs_jrv
  frm status ohs_jrv ohs_lfr7
  frm status 'ohs_*_11119'
  frm restart 'ohs_[jl]*'

Quote globs so your calling shell does not expand them before FRM sees them.

Global exclusion can be repeated:
  frm --exclude '*_711' status
  frm --exclude '*old*' --exclude '*test*' status 'ohs_*'

State filters are evaluated as a snapshot after name selection/exclusion and
before any lifecycle state change:
  frm list --state RUNNING
  frm restart --state RUNNING 'ohs_*'
  frm start --state DOWN
  frm status --state WARNING

Accepted states (case-insensitive):
  RUNNING  aliases: ACTIVE, UP, HEALTHY
  DOWN     aliases: STOPPED, INACTIVE, OFFLINE
  WARNING  alias: WARN
  UNKNOWN
  UNHEALTHY / NOT-RUNNING  matches DOWN, WARNING and UNKNOWN

--state can be repeated or comma-separated; filters are ORed:
  frm list --state DOWN,WARNING
  frm --state DOWN --state UNKNOWN list

Explicit all:
  frm status --all

Detection ignores configured skip words by default. To include them:
  frm --include-skipped list

The default skip words are:
  old ritm bck backup bk bkp bckup bckp bkup spenta

If any explicit selector matches nothing, selection fails before lifecycle work
begins. This prevents a typo from causing a partial start/stop/restart.
EOF_HELP
}

help_status() {
    cat <<'EOF_HELP'
STATUS

FRM chooses the best available status backend per instance:

  1. <instance>_status custom handler, if loaded
  2. <instance>/bin/opmnctl for OHS 11g
  3. <instance>.service via systemd
  4. matching SysV init script
  5. direct httpd/httpd.worker process detection

OHS 11g:
  `opmnctl status` is parsed for Alive/Down and PID.

OHS 12c:
  systemd/SysV may report `active (exited)`. FRM therefore validates the real
  httpd process belonging to the instance before reporting RUNNING.

Default compact output:
  ohs_jrv                  RUNNING  pid=3217 httpd=6
  ohs_legacy_711           DOWN     opmn=Down

Structured formats:
  frm status --json
  frm status --tsv

Verbose native output:
  frm status --verbose ohs_jrv
  frm --debug status       # native output + discovery/debug diagnostics
  frm status --debug       # equivalent command-local form

Summary:
  frm status --summary
EOF_HELP
}
