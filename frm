#!/usr/bin/env bash
# FRM - Fronten Runtime Manager
# Oracle HTTP Server runtime discovery, status and lifecycle manager.

set -o pipefail

FRM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$FRM_SCRIPT_DIR/lib" ]]; then
    FRM_LIB_DIR="$FRM_SCRIPT_DIR/lib"
else
    FRM_LIB_DIR="${FRM_LIB_DIR:-$FRM_SCRIPT_DIR/../lib/frm}"
fi

for FRM_LIB in \
    00-core.sh \
    10-status.sh \
    20-actions.sh \
    21-commands.sh \
    22-operations.sh \
    30-inspection.sh \
    40-help-core.sh \
    41-help-extra.sh \
    42-help-router.sh \
    50-cli.sh
do
    # shellcheck source=/dev/null
    . "$FRM_LIB_DIR/$FRM_LIB"
done
unset FRM_LIB

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
