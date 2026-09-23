#!/bin/bash
set -euo pipefail
DEST=""
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--output-last-message" ]]; then DEST="$2"; shift 2; else shift; fi
done
cat >/dev/null
case "${SN_TEST_MODE:-success}" in
    fail) echo 'authentication failed: 401' >&2; exit 1 ;;
    malformed) printf '{"title":' > "$DEST" ;;
    empty) printf '{}' > "$DEST" ;;
    hang) exec /bin/sleep 30 ;;
    *) cp "$(dirname "$0")/fixture.json" "$DEST" ;;
esac
