#!/usr/bin/env bash
# Compatibility launcher for the original script name.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/frm" "$@"
