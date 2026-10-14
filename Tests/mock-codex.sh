#!/bin/bash
set -euo pipefail
DEST=""
MODEL=""
EFFORT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-last-message) DEST="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        -c) [[ "$2" != model_reasoning_effort=* ]] || EFFORT="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[[ "$MODEL" == "gpt-6.1-sol" && "$EFFORT" == 'model_reasoning_effort="medium"' ]] || {
    echo 'Unexpected summarization model or reasoning effort' >&2
    exit 1
}
cat >/dev/null
case "${NF_TEST_MODE:-success}" in
    fail) echo 'authentication failed: 401' >&2; exit 1 ;;
    malformed) printf '{"title":' > "$DEST" ;;
    empty) printf '{}' > "$DEST" ;;
    hang) exec /bin/sleep 30 ;;
    *) cp "$(dirname "$0")/fixture.json" "$DEST" ;;
esac
