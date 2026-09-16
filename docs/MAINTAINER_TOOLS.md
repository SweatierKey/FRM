# Maintainer tools

FRM has no runtime dependency on the files in `tools/`. They are deliberately kept
outside the installed footprint and are intended for development, qualification on new
Oracle estates, demos and releases.

## `fixture-lab.py`

Creates an isolated mixed OHS estate containing mock 11g/OPMN and 12c/systemd
instances. It also creates mock `systemctl`, `ps`, `ss`, OPMN lifecycle commands and
syntax-checking OHS binaries so status/lifecycle/configtest/ports verification can be
exercised without middleware.

```bash
make dev-fixture
PATH="$PWD/.frm-fixture/bin:$PATH" \
  FRM_INSTANCES_DIR="$PWD/.frm-fixture/admin" \
  ./frm status
```

This is useful for experimenting with selectors/lifecycle behavior without middleware.

Run the full fixture smoke path with:

```bash
make smoke-fixture
```

The smoke test covers mixed status, `configtest`, `ports --verify`, log discovery, rolling restart,
lifecycle evidence summaries and structured uptime/started-at output.

## `backend-probe.sh`

Runs several non-destructive FRM views against one or more real instances:

```bash
FRM_INSTANCES_DIR=/u01/app/oracle/admin \
  tools/backend-probe.sh ohs_jrv ohs_lfr7
```

It collects `inspect`, compact/verbose `status`, `processes`, `ports`, `ports --verify`
and `configtest`. It does not start or stop anything.

## `release-check.sh`

One-command pre-release gate:

```bash
make release-check
```

It validates version format, Bash/Python syntax, regression tests, Bash 4.2 compatibility,
optional ShellCheck and Git cleanliness.

## `make-release.sh`

Builds tar.gz, ZIP and Git bundle artifacts from the current committed tree and writes
SHA-256 checksums:

```bash
make release
```

Artifacts are written to `dist/` and intentionally ignored by Git.
