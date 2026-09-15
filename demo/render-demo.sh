#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAST="$ROOT/demo/frm-demo.cast"
GIF="$ROOT/assets/demo.gif"

python3 "$ROOT/demo/make-demo-cast.py" >/dev/null

if command -v agg >/dev/null 2>&1; then
    agg \
        --cols 105 \
        --rows 28 \
        --font-size 18 \
        "$CAST" \
        "$GIF"
else
    echo "agg not found; using bundled fallback renderer" >&2
    python3 "$ROOT/demo/render_cast.py" "$CAST" "$GIF"
fi

printf 'generated %s\n' "$GIF"
