#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
DEST="$HOME/Applications/Summary Notes.app"
mkdir -p "$HOME/Applications"
if [[ -e "$DEST" ]]; then
    BACKUP="$HOME/Applications/Summary Notes backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    mv "$DEST" "$BACKUP/"
fi
ditto "build/Summary Notes.app" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
printf 'Installed %s\nOpen Summary Notes from Spotlight or Raycast, paste your text, and choose Format only or Summarize & format.\n' "$DEST"
