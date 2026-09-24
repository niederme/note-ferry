#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
ROOT="$PWD/.build/sparkle/$VERSION"
ARCHIVE="$ROOT/Sparkle-$VERSION.tar.xz"
if [[ -d "$ROOT/Sparkle.framework" && -x "$ROOT/bin/sign_update" ]]; then
    exit 0
fi
mkdir -p "$ROOT"
curl --fail --location --retry 3 --output "$ARCHIVE.tmp" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
printf '%s  %s\n' "$SHA256" "$ARCHIVE.tmp" | shasum -a 256 --check --status
mv "$ARCHIVE.tmp" "$ARCHIVE"
tar -xf "$ARCHIVE" -C "$ROOT"
[[ -d "$ROOT/Sparkle.framework" && -x "$ROOT/bin/sign_update" ]] || {
    printf 'Sparkle distribution is incomplete.\n' >&2
    exit 1
}
