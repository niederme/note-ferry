#!/bin/bash
set -euo pipefail
DEST=""
MODEL=""
EFFORT=""
ISOLATED=0
EPHEMERAL=0
SANDBOX=""
APPROVAL=""
SHELL_DISABLED=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-last-message) DEST="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --ignore-user-config) ISOLATED=1; shift ;;
        --ephemeral) EPHEMERAL=1; shift ;;
        --sandbox) SANDBOX="$2"; shift 2 ;;
        -c)
            case "$2" in
                model_reasoning_effort=*) EFFORT="$2" ;;
                approval_policy=*) APPROVAL="$2" ;;
                features.shell_tool=false) SHELL_DISABLED=1 ;;
            esac
            shift 2 ;;
        *) shift ;;
    esac
done
[[ "$MODEL" == "${NF_TEST_EXPECTED_MODEL:-}" && -z "$EFFORT" && "$ISOLATED" == 1 && "$EPHEMERAL" == 1 && "$SANDBOX" == read-only && "$APPROVAL" == 'approval_policy="never"' && "$SHELL_DISABLED" == 1 ]] || {
    echo 'Unexpected model, reasoning override, or execution safeguards' >&2
    exit 1
}
cat >"${NF_TEST_INPUT:-/dev/null}"
case "${NF_TEST_MODE:-success}" in
    fail) echo 'authentication failed: 401' >&2; exit 1 ;;
    unavailable) echo 'The selected model is not supported when using Codex with a ChatGPT account.' >&2; exit 1 ;;
    model_missing) echo 'model_not_found: model does not exist or you do not have access' >&2; exit 1 ;;
    model_access_denied) echo 'model_access_denied' >&2; exit 1 ;;
    malformed) printf '{"title":' > "$DEST" ;;
    empty) printf '{}' > "$DEST" ;;
    hang) exec /bin/sleep 30 ;;
    *) cp "$(dirname "$0")/fixture.json" "$DEST" ;;
esac
