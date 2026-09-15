#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

version="$(tr -d '[:space:]' < VERSION)"
outdir="${1:-dist}"
mkdir -p "$outdir"

./tools/release-check.sh

git archive --format=tar.gz --prefix="FRM-$version/" -o "$outdir/FRM-$version.tar.gz" HEAD
git archive --format=zip --prefix="FRM-$version/" -o "$outdir/FRM-$version.zip" HEAD
git bundle create "$outdir/FRM-$version.bundle" --all
sha256sum "$outdir/FRM-$version.tar.gz" "$outdir/FRM-$version.zip" "$outdir/FRM-$version.bundle" > "$outdir/SHA256SUMS"

printf '\nRelease artifacts:\n'
cat "$outdir/SHA256SUMS"
