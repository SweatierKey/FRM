# Changelog

## 0.1.2 - 2026-09-16

### Fixed

- Replace the invalid `opmnctl stop` / `start` lifecycle pair with an adaptive
  OPMN policy. In the default `auto` mode, an OHS-only Oracle Instance uses the
  operational `stopall` / `startall` pair; mixed-process instances use
  `stopproc` / `startproc process-type=OHS` to avoid collateral state changes.
  The selected mode is cached across each lifecycle operation so a rolling
  `stopall` is paired with `startall`. A standalone start with OPMN down remains
  conservative (`opmnctl start` then `startproc process-type=OHS`).
- Add `FRM_OPMN_MODE=auto|all|ohs` and `--opmn-mode` as an explicit override.
- Make `FRM_SUDO=auto` evaluate the exact lifecycle command with `sudo -n -l`
  instead of probing `sudo -n true`. This supports production sudoers policies
  that grant NOPASSWD only for specific systemctl/init-script commands.
- Invoke systemd lifecycle with the bare instance name (for example
  `systemctl stop ohs_cpf_12`) so command arguments match restricted sudoers
  entries exactly.
- Detect existing SysV init scripts for lifecycle even when the oracle account
  cannot execute them directly; `sudo` may still be explicitly authorized for
  those scripts. Status continues to avoid executing a non-executable SysV
  script directly and falls back to process detection.

### Tests

- Add command-specific sudo policy regression coverage.
- Add systemd sudoers-compatible lifecycle invocation coverage.
- Add adaptive OPMN lifecycle tests for OHS-only, mixed-process, forced-all and
  OPMN-daemon-down cases.
- Regression suite: 52 tests, also exercised with `BASH_COMPAT=4.2`.

## 0.1.1 - 2026-09-16

### Fixed

- Force unlimited-width `ps` output when attributing OHS `httpd`/`httpd.worker`
  processes. On RHEL7/procps, piped `ps` output could be truncated before the
  `/u01/app/oracle/admin/<instance>/...` argument, causing a running OHS 12c
  instance to be reported as `WARNING systemd active but httpd not found`.
- Apply the same wide-process snapshot to `frm processes` so status and process
  inspection use identical attribution semantics.
- Accept `frm status --debug` / `frm status -d` in addition to the existing
  `frm --debug status` and `frm debug status` forms.

### Tests

- Add an RHEL7-style process truncation regression test.
- Add command-local `status --debug` regression coverage.
- Regression suite: 43 tests, also exercised with `BASH_COMPAT=4.2`.

## 0.1.0 - 2026-09-15

Initial FRM release derived from the original `manage_instances_runtime.sh` operational
script.

### Added

- OHS candidate discovery and instance filtering.
- OHS 11g/OPMN status parsing.
- OHS 12c systemd/SysV plus real-process validation.
- Cross-generation `httpd` / `httpd.worker` process attribution.
- Exact/glob selectors and exclusions with atomic selection validation.
- Snapshot state filters (`--state`) with ACTIVE/STOPPED aliases and UNHEALTHY grouping.
- `restart --preserve-state` to restart only initially RUNNING instances.
- Batch and per-instance lifecycle confirmations (`--confirm`, `--confirm-each`, `--step`, `--yes`).
- Compact, verbose, JSON and TSV status output.
- Start/stop/restart with state verification.
- Rolling and all-at-once restart strategies.
- One-shot and per-instance lifecycle confirmations with safe rolling continuation.
- `plan`, `--dry-run`, lifecycle locking and sudo policy.
- `watch`, `inspect`, `processes`/`ps`, `ports`, and `doctor`.
- Custom lifecycle handlers file.
- Section-filterable help.
- Bash completion.
- Mock unit/integration test suite.
- Asciinema-compatible README demo and GIF renderer.

### Final review hardening

- Keep JSON/TSV stdout machine-readable even with verbose/debug status.
- Make plain `list` discovery-only.
- Preserve specific lifecycle failure exit codes.
- Reject zero poll/watch intervals.
- Expand help with monitoring, inspection and installation sections.
- Add Bash 4.2 compatibility regression coverage.
- Add state-aware lifecycle and rolling confirmation regression coverage.
- Split the 41-test regression suite into focused core/status/lifecycle/state modules.
