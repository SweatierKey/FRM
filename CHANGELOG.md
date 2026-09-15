# Changelog

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
