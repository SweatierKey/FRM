help_lifecycle() {
    cat <<'EOF_HELP'
LIFECYCLE

Backend order for start/stop:
  1. <instance>_start / <instance>_stop custom handler
  2. OPMN (`opmnctl`)
  3. systemd (`systemctl start|stop <instance>`)
  4. SysV init script

OPMN policy (`FRM_OPMN_MODE`, default `auto`):
  auto  if live `opmnctl status` shows only OHS process types, use
        `stopall`/`startall`; otherwise use OHS-only `stopproc`/`startproc`.
        A standalone start with OPMN down is conservative: FRM starts OPMN and
        then starts only process-type=OHS because no live inventory is available.
  all   always use `stopall`/`startall` for the Oracle Instance.
  ohs   always manage only `process-type=OHS` (starting OPMN first if needed).

The auto decision is cached per instance for the lifecycle operation. This is
important for a rolling restart: after `stopall` makes OPMN unavailable, the
matching start still uses `startall`. Override when needed with:
  frm restart --opmn-mode all ohs_legacy_11119
  frm restart --opmn-mode ohs ohs_legacy_11119

FRM verifies transitions by polling the unified status layer:
  start -> wait for RUNNING
  stop  -> wait for DOWN

Defaults:
  timeout:       60 seconds
  poll interval: 2 seconds
  wait:          enabled

Override:
  frm --timeout 120 restart ohs_jrv
  frm --poll-interval 1 start ohs_jrv
  frm --no-wait stop ohs_jrv

Restart strategies:
  rolling       stop + verify DOWN + start + verify RUNNING for each instance
                before moving to the next (default)
  all-at-once   stop all selected instances, then start those stopped cleanly

Failure policy:
  --on-error auto       fail-fast for rolling restart; continue for start/stop
                        and all-at-once recovery (default)
  --on-error stop       stop scheduling new lifecycle work after a failure
  --on-error continue   continue with later selected instances

Rolling restart is fail-fast by default. If one instance cannot stop or cannot
return RUNNING, FRM leaves later instances untouched and reports them SKIPPED.
For all-at-once restart, FRM always attempts to restore every instance it
successfully stopped, even when --on-error=stop is requested.

Lifecycle summary is enabled by default and reports result, before/after state,
old/new PID, final uptime and operation duration. Disable with
--no-lifecycle-summary.

Optional configuration preflight:
  frm restart --preflight-configtest 'ohs_*'

This runs the read-only configtest for every selected instance before any state
change. It is opt-in because configtest command resolution must first be proven
on each estate generation.

Interactive safety:
  --confirm         one confirmation before the lifecycle operation starts
  --confirm-each    confirm each selected instance before changing it
  --step            alias for --confirm-each
  --yes, -y         suppress lifecycle prompts (automation)

For rolling restart, --confirm-each prompts before each instance; once approved,
that instance completes stop -> DOWN -> start -> RUNNING before FRM asks about the
next one. For all-at-once restart, all per-instance confirmations are collected
as a preflight before any instance is stopped, preventing a partial outage caused
by cancelling half-way through the stop phase.

A restart is convergent: an instance already DOWN is started, so every selected
instance is intended to finish RUNNING. Use `plan` or `--dry-run` before a broad
restart when that behavior matters.

State-aware restart:
  frm restart --state RUNNING 'ohs_*'
  frm restart --preserve-state 'ohs_*'

`--preserve-state` is a restart convenience equivalent to filtering the initial
snapshot to RUNNING. Instances that are already DOWN are not selected and remain
DOWN. It cannot be combined with an explicit --state filter.

Examples:
  frm restart ohs_jrv
  frm restart --confirm 'ohs_*'
  frm restart --confirm-each 'ohs_*'
  frm restart --on-error continue 'ohs_*'
  frm restart --preflight-configtest 'ohs_*'
  frm restart --step 'ohs_*'
  frm restart --strategy all-at-once --confirm 'ohs_*'
  frm --yes restart 'ohs_*'
EOF_HELP
}

help_monitoring() {
    cat <<'EOF_HELP'
MONITORING

`watch` repeatedly executes the normalized status layer:

  frm watch
  frm watch --interval 2
  frm watch --no-clear 'ohs_*'

The interval must be greater than zero. When stdout is a real terminal FRM
clears the screen between refreshes by default. Use --no-clear for logs,
pagers or terminal multiplexers where scrollback should be preserved.

`watch` deliberately continues when one or more instances are DOWN/WARNING;
Ctrl-C remains the normal way to stop it.
EOF_HELP
}

help_inspection() {
    cat <<'EOF_HELP'
INSPECTION / DIAGNOSTICS

  frm inspect [selectors...]
      Show family, normalized state, status backend, uptime/started_at,
      OPMN/systemd/SysV availability, custom handlers and detected NodeManager.

  frm processes|ps [selectors...]
      Show the attributed OHS master PID, worker count and relevant process
      rows. OHS 11g httpd.worker ownership is inferred through
      instance-specific child processes when the master command line does not
      contain the instance path.

  frm ports [selectors...]
      OHS 11g: parse the OHS row from `opmnctl status -l`.
      OHS 12c: inventory unique active-looking `Listen` directives found under
      the instance OHS configuration tree.

  frm ports --verify [selectors...]
      Correlate discovered ports with ss/netstat LISTEN sockets. When process
      ownership is visible, verify that at least one listener PID belongs to
      the selected OHS master/worker tree.

  frm configtest [selectors...]
      Read-only syntax check. FRM derives the live OHS executable and syntax-
      affecting flags, adds a reliable instance httpd.conf when necessary, and
      invokes -t. If it cannot resolve the command safely, it returns
      UNAVAILABLE rather than guessing.

  frm logs [--type all|error|access|admin|audit] [--tail N] [selectors...]
      Read-only log discovery inside known instance-local roots. --tail selects
      the newest matching file and prints N lines. No external paths are guessed.

  frm doctor
      Report FRM/Bash versions, dependencies, discovery, selected status
      backends/families, and real/effective TTY/color state.

For backend-native status plus FRM diagnostics:
  frm --debug status ohs_jrv
EOF_HELP
}

help_installation() {
    cat <<'EOF_HELP'
INSTALLATION

Run directly:
  chmod +x frm
  ./frm status

Install with Make:
  sudo make install

Default paths:
  /usr/local/bin/frm
  /usr/local/share/bash-completion/completions/frm

Override PREFIX/DESTDIR when packaging:
  make PREFIX="$HOME/.local" install
  make DESTDIR=/tmp/pkg PREFIX=/usr install

Compatibility launcher:
  manage_instances_runtime.sh forwards all arguments to the adjacent `frm`
  executable, so existing calls can migrate without changing immediately.

Runtime target: Bash 4.x+ and an Enterprise Linux style userland. Python is
used only by the repository test/demo tooling, never by the FRM runtime.
EOF_HELP
}

help_output() {
    cat <<'EOF_HELP'
OUTPUT

Color modes:
  --color auto       ANSI only when the target file descriptor is a TTY
  --color always     Always emit ANSI colors
  --color never      Never emit ANSI colors

Legacy FORCE_TTY remains supported:
  FORCE_TTY=1 frm status |& less -R

Preferred equivalent:
  frm --color always status |& less -R

Use `less -R`, not `less -r`, when only ANSI color sequences need preserving.

Machine-readable status:
  frm status --json    # includes uptime_seconds + started_at
  frm status --tsv     # includes uptime_seconds + started_at

Compact + aggregate summary:
  frm status --summary

Native backend details:
  frm status --verbose

Full FRM diagnostics:
  frm --debug status
EOF_HELP
}

help_configuration() {
    cat <<'EOF_HELP'
CONFIGURATION

Environment variables:
  FRM_INSTANCES_DIR     Admin root (default /u01/app/oracle/admin)
  FRM_DEBUG             true/false
  FRM_QUIET             true/false
  FRM_COLOR             auto|always|never
  FRM_DRY_RUN           true/false
  FRM_WAIT              true/false
  FRM_TIMEOUT           transition timeout in seconds
  FRM_POLL_INTERVAL     polling interval in seconds
  FRM_SUDO              auto|always|never
  FRM_OPMN_MODE         auto|all|ohs
  FRM_ON_ERROR          auto|stop|continue
  FRM_LIFECYCLE_SUMMARY true/false
  FRM_PREFLIGHT_CONFIGTEST true/false
  FRM_INCLUDE_SKIPPED   true/false
  FRM_SKIP_WORDS        space-delimited replacement for default skip words
  FRM_LOCK_FILE         lifecycle lock path
  FRM_HANDLERS_FILE     optional Bash file with custom lifecycle functions
  FORCE_TTY             legacy true/false color override

Handlers file:
  Default: ~/.config/frm/handlers.sh

Example:
  ohs_jrv_start()  { sudo systemctl start ohs_jrv; }
  ohs_jrv_stop()   { sudo systemctl stop ohs_jrv; }
  ohs_jrv_status() { systemctl status ohs_jrv --no-pager; }

Functions exported by the invoking shell are also detected.
EOF_HELP
}

help_safety() {
    cat <<'EOF_HELP'
SAFETY

Selection is validated before lifecycle operations. An unmatched explicit
selector aborts the operation instead of operating on the remaining subset.

Lifecycle operations use `flock` when available. A second concurrent lifecycle
operation exits while the first holds the lock.

State-safe rolling restart:
  frm restart --state RUNNING 'ohs_*'
  frm restart --preserve-state 'ohs_*'

Dry-run:
  frm --dry-run restart 'ohs_*'

Confirmations:
  frm restart --confirm 'ohs_*'
  frm restart --confirm-each 'ohs_*'
  frm restart --on-error continue 'ohs_*'
  frm restart --preflight-configtest 'ohs_*'
  frm stop --confirm-each 'ohs_*'
  frm start --confirm-each 'ohs_*'

`--confirm-each` is especially useful with rolling restart: FRM fully restores
one approved instance before asking whether to continue with the next.
`--yes` suppresses prompts for unattended automation.

Plan without execution:
  frm plan restart 'ohs_*'

If confirmation is requested without an interactive /dev/tty, FRM exits instead
of reading from a pipe. Use --yes only when non-interactive execution is intended.

Sudo modes:
  --sudo auto      use non-interactive sudo when the exact lifecycle command is
                   NOPASSWD-authorized; otherwise execute directly
  --sudo always    always invoke sudo for systemd/SysV lifecycle commands
  --sudo never     never invoke sudo

In auto mode FRM checks the exact command with `sudo -n -l`, which supports
restricted sudoers entries such as:
  /usr/bin/systemctl stop ohs_cpf_12
  /etc/init.d/ohs_msi_12 stop

For systemd FRM deliberately uses the bare unit name (`ohs_cpf_12`) so its
arguments can match command-specific sudoers rules. FRM never uses sudo for OPMN
or custom handlers unless the handler itself does.

OPMN modes:
  --opmn-mode auto  use stopall/startall when the live OPMN inventory contains
                    only OHS process types; otherwise scope to OHS only
  --opmn-mode all   force stopall/startall
  --opmn-mode ohs   force stopproc/startproc process-type=OHS

`auto` is the default. The chosen mode is cached per instance for the lifecycle
operation, so a rolling stopall is always paired with startall.

Restart defaults to rolling mode so one instance is restored before FRM moves
on to the next selected instance. Rolling restart is fail-fast by default; use
`--on-error continue` only when intentionally proceeding past a failed instance.
EOF_HELP
}

help_exit_codes() {
    cat <<EOF_HELP
EXIT CODES

  $EX_OK  Success / every checked instance RUNNING
  $EX_GENERAL  General CLI or execution error
  $EX_STATE  One or more instances are not healthy, or lifecycle verification failed
  $EX_SELECTION  Instance discovery/selection failed
  $EX_UNAVAILABLE  Required lifecycle backend/dependency unavailable
  $EX_LOCKED  Another FRM lifecycle operation holds the lock

Examples:
  frm status >/dev/null
  case \$? in
    0) echo "all healthy" ;;
    $EX_STATE) echo "at least one runtime is not healthy" ;;
  esac
EOF_HELP
}

help_examples() {
    cat <<'EOF_HELP'
EXAMPLES

Discovery:
  frm list
  frm list --long
  frm list --json

Status:
  frm status
  frm status ohs_jrv
  frm status 'ohs_*_11119'
  frm status --summary
  frm status --json
  frm status --tsv
  frm status --verbose ohs_jrv

Selection/exclusion:
  frm --exclude '*_711' status 'ohs_*'

Lifecycle:
  frm plan restart ohs_jrv ohs_lfr7
  frm --dry-run restart 'ohs_*'
  frm restart ohs_jrv ohs_lfr7
  frm restart --confirm-each 'ohs_*'
  frm restart --on-error continue 'ohs_*'
  frm restart --preflight-configtest 'ohs_*'
  frm stop --confirm-each 'ohs_*'
  frm restart --strategy all-at-once --confirm 'ohs_*'
  frm --timeout 120 --poll-interval 1 restart ohs_jrv

Monitoring:
  frm watch
  frm watch --interval 2 'ohs_*'

Diagnostics:
  frm inspect ohs_jrv
  frm processes ohs_jrv
  frm ports ohs_jrv
  frm ports --verify ohs_jrv
  frm configtest ohs_jrv
  frm logs --type error --tail 100 ohs_jrv
  frm doctor
  frm --debug status

Pager with ANSI colors:
  frm --color always status |& less -R
EOF_HELP
}
