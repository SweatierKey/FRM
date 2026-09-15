#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok   %s\n' "$*"; }

[[ -f VERSION ]] || fail 'VERSION missing'
version="$(tr -d '[:space:]' < VERSION)"
[[ -n "$version" ]] || fail 'VERSION empty'
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || fail "invalid VERSION: $version"
ok "version $version"

bash -n frm
for f in lib/*.sh tools/*.sh tests/*.sh demo/*.sh manage_instances_runtime.sh completions/frm.bash; do
    [[ -f "$f" ]] || continue
    bash -n "$f"
done
ok 'bash syntax'

python3 -m py_compile demo/*.py tools/*.py
ok 'python syntax'

make test >/dev/null
ok 'make test'

BASH_COMPAT=4.2 ./tests/test.sh >/dev/null
ok 'Bash 4.2 compatibility'

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck frm manage_instances_runtime.sh lib/*.sh tools/*.sh tests/*.sh completions/frm.bash
    ok 'shellcheck'
else
    printf 'skip shellcheck (not installed)\n'
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain)" ]]; then
        fail 'working tree is dirty'
    fi
    ok 'git working tree clean'
fi

if grep -RInE '(TO''DO|FIX''ME|X''XX)' --exclude-dir=.git --exclude='*.cast' --exclude='release-check.sh' . >/tmp/frm-release-todos.$$ 2>/dev/null; then
    printf 'note unresolved markers:\n'
    cat /tmp/frm-release-todos.$$
else
    ok 'no TODO/FIXME/XXX markers'
fi
rm -f /tmp/frm-release-todos.$$

printf '\nFRM %s release checks passed.\n' "$version"
