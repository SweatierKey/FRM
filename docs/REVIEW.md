# FRM engineering review

This document captures the review that turned the original `manage_instances_runtime.sh`
into FRM.

## Defects found in the original implementation

| Area | Problem | Resolution |
|---|---|---|
| TTY | `[[ is_a_tty ]]` tested a literal string instead of invoking the function | Replaced with explicit real/effective TTY helpers |
| TTY/debug | TTY checks inside command substitutions observed the pipe created by the substitution | Values are now evaluated before formatting/logging |
| Paths | `instance_dir` was referenced but never defined | All paths derive from `FRM_INSTANCES_DIR` |
| Debug | `DEBUG=true` was enabled after debug output was requested | Debug is parsed before diagnostics |
| stdout contract | `instance_list` mixed debug messages and data on stdout | Debug/error output is on stderr; discovery data remains clean |
| Iteration | `for x in $(...)` introduced word splitting | Arrays and line-safe iteration are used |
| OPMN parser | Multiline `gsub()` formatting failed on the older awk in the 11g estate | Parser is intentionally conservative and portable |
| OHS 11g processes | Master `httpd.worker` does not contain the instance path | FRM follows instance-specific child log processes back to the master PID |
| OHS 12c status | Generated SysV/systemd units can be `active (exited)` | FRM confirms the real instance `httpd` process before reporting RUNNING |
| Status verbosity | Native backend output was too noisy for normal use | Compact table by default; native output in `--verbose`/`--debug` |
| Selection | No safe way to target a subset | Exact names, globs, `--exclude`, state snapshots, and atomic selector validation |
| Discovery | Every directory under the admin root was treated as an instance | Candidate detection now requires OHS/runtime markers |
| Lifecycle | 12c control was missing when shell wrapper functions were not inherited | Added systemd and SysV lifecycle backends plus optional handler file |
| Lifecycle safety | No post-action validation | Start/stop now wait for RUNNING/DOWN with timeout and polling |
| Concurrency | Two operators could issue lifecycle changes concurrently | `flock` lifecycle lock when available |
| Automation | Output was human-only | JSON/TSV status and documented exit codes |
| Operability | No way to preview destructive work | `plan` and `--dry-run` |
| Diagnostics | No consolidated environment/backend inspection | `doctor` and `inspect` |
| Help | One-line usage only | Sectioned help with `frm help <section>` |
| Structured output | Verbose/debug native output could corrupt JSON/TSV stdout | Native backend detail is routed to stderr for machine formats |
| Discovery cost | Plain list needlessly queried every runtime backend | Plain `list` is now discovery-only |
| Exit codes | Lifecycle loops collapsed backend errors into a generic state error | Specific exit codes are preserved and aggregated |
| Polling | A zero interval could create a busy-loop | Poll/watch intervals must be greater than zero |

## Implemented feature set

### Discovery and selection

- OHS candidate detection under the configurable admin root.
- OHS 11g/OPMN and OHS 12c family classification.
- Default backup/old-instance filtering.
- Exact selectors and quoted shell globs.
- Repeated global exclusion patterns.
- Atomic selection failure: one bad explicit selector prevents lifecycle work.
- Snapshot state filters for RUNNING/DOWN/WARNING/UNKNOWN and aliases.
- `--preserve-state` restart convenience leaves initially DOWN instances untouched.
- Optional inclusion of normally skipped names.

### Runtime status

- Custom `<instance>_status` handlers.
- `opmnctl status` parsing for OHS 11g.
- systemd and SysV status support.
- Process fallback for both `httpd` and `httpd.worker`.
- 11g parent inference using instance-specific child processes.
- Compact colored output, JSON, TSV, summary and native verbose output.
- Status exit code suitable for monitoring/automation.

### Lifecycle

- Custom start/stop handlers.
- OPMN start/stop.
- systemd start/stop.
- SysV start/stop.
- Optional non-interactive sudo behavior.
- Start/stop state verification with timeout.
- Rolling restart by default.
- One-shot and per-instance lifecycle confirmation, with safe all-at-once preflight.
- Optional all-at-once restart.
- `plan` and `--dry-run`.
- Lifecycle locking.
- Optional batch/per-instance confirmations for state-changing operations.
- Rolling restart can pause between fully restored instances.
- Rolling restart is fail-fast by default, with explicit continue-on-error override.
- Lifecycle evidence summary records old/new PID, final uptime and duration.
- Optional read-only configtest preflight before start/restart.

### Operations

- `list`
- `status`
- `start`
- `stop` / `shutdown`
- `restart`
- `watch`
- `inspect`
- `processes` / `ps`
- `ports` / `ports --verify`
- `configtest`
- `logs`
- `plan`
- `doctor`
- sectioned `help` (including monitoring, inspection and installation sections)
- `version`

## Remaining roadmap after 0.2.0-dev

The core runtime/lifecycle path is now covered. Remaining work mostly requires
environment-specific policy rather than generic guesses:

1. **HTTP/HTTPS application health probes.** FRM currently validates the OHS runtime,
   not whether every front-end URL is functionally healthy.
2. **Automatic configtest enforcement.** `frm configtest` and opt-in lifecycle
   preflight now exist, but automatic preflight remains disabled until both real 11g
   and 12c estates have been qualified.
3. **Advanced listener diagnostics.** `ports --verify` correlates configured ports with
   sockets/PIDs; future work could include protocol/TLS probing and richer bind-address
   policy checks.
4. **Advanced log navigation.** Basic read-only discovery and newest-file tailing now
   cover known instance-local 11g/12c roots. Future work can add pager/follow modes,
   log-role overrides and environment-specific conventions without guessing globally.
5. **Remote multi-host orchestration.** FRM is intentionally local to one host. It can be
   wrapped by SSH/psmpx/Ansible/ob-multihost later without coupling credentials into FRM.
6. **Application-aware draining.** Rolling restart means sequential runtime restart; it
   does not manipulate an upstream load balancer.

## Compatibility target

- Bash 4.x or newer.
- Enterprise Linux style userlands, including the older Bash/awk behavior observed in the
  OHS 11g environment.
- No Python, jq or Perl dependency at runtime.
- Optional: `systemctl`, `flock`, `sudo`, depending on the chosen lifecycle backend.
