#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRM="${FRM_BIN:-$ROOT/frm}"

usage() {
    cat <<'USAGE'
Usage: tools/backend-probe.sh INSTANCE [INSTANCE ...]

Runs the same instance through FRM discovery/status/inspect/process/port views and
prints exit codes. Useful when bringing FRM to a new OHS host or product generation.
Environment variables such as FRM_INSTANCES_DIR, FRM_HANDLERS_FILE and PATH are
honored exactly as FRM would honor them.
USAGE
}

(( $# > 0 )) || { usage; exit 2; }

for instance in "$@"; do
    printf '\n========== %s ==========' "$instance"
    printf '\n-- inspect --\n'
    "$FRM" inspect "$instance" || printf '[rc=%d]\n' "$?"
    printf '\n-- compact status --\n'
    "$FRM" status "$instance" || printf '[rc=%d]\n' "$?"
    printf '\n-- verbose status --\n'
    "$FRM" status --verbose "$instance" || printf '[rc=%d]\n' "$?"
    printf '\n-- processes --\n'
    "$FRM" processes "$instance" || printf '[rc=%d]\n' "$?"
    printf '\n-- ports --\n'
    "$FRM" ports "$instance" || printf '[rc=%d]\n' "$?"
    printf '\n-- ports verify --\n'
    "$FRM" ports --verify "$instance" || printf '[rc=%d]\n' "$?"
    printf '\n-- configtest --\n'
    "$FRM" configtest "$instance" || printf '[rc=%d]\n' "$?"
done
