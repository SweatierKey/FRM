#!/usr/bin/env bash
set -u
set -o pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=testlib.sh
source "$TEST_DIR/testlib.sh"

for suite in core status lifecycle state; do
    # shellcheck disable=SC1090
    source "$TEST_DIR/$suite.sh"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
