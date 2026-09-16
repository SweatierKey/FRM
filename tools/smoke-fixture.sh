#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/tools/fixture-lab.py" "$TMP/estate" --force >/dev/null

export PATH="$TMP/estate/bin:$PATH"
export FRM_INSTANCES_DIR="$TMP/estate/admin"
export FRM_COLOR=never
export FRM_SUDO=never
export FRM_TIMEOUT=5
export FRM_POLL_INTERVAL=0.1
# Fixture state changes are synchronous; skip polling to keep CI smoke fast.
export FRM_WAIT=false

mixed_json="$("$ROOT/frm" status --json ohs_legacy_a ohs_modern_a)"
[[ "$mixed_json" == *'"instance":"ohs_legacy_a"'* ]]
[[ "$mixed_json" == *'"instance":"ohs_modern_a"'* ]]
[[ "$mixed_json" == *'"started_at"'* ]]
[[ "$mixed_json" == *'"uptime_seconds"'* ]]

"$ROOT/frm" configtest ohs_legacy_a ohs_modern_a >"$TMP/configtest.out"
grep -q 'ohs_legacy_a configtest OK' "$TMP/configtest.out"
grep -q 'ohs_modern_a configtest OK' "$TMP/configtest.out"

"$ROOT/frm" ports --verify ohs_modern_a >"$TMP/ports.out"
grep -q 'ohs_modern_a.*YES' "$TMP/ports.out"

"$ROOT/frm" logs --type error --tail 1 ohs_modern_a >"$TMP/logs.out"
grep -q 'modern error sample' "$TMP/logs.out"

"$ROOT/frm" restart ohs_legacy_a >"$TMP/restart-legacy.out"
"$ROOT/frm" restart --preflight-configtest ohs_modern_a >"$TMP/restart-modern.out"
grep -q 'Lifecycle summary (restart)' "$TMP/restart-legacy.out"
grep -q 'Lifecycle summary (restart)' "$TMP/restart-modern.out"
grep -q 'OK.*RUNNING.*RUNNING' "$TMP/restart-legacy.out"
grep -q 'OK.*RUNNING.*RUNNING' "$TMP/restart-modern.out"

printf 'fixture smoke OK\n'
