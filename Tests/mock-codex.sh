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
JSON_EVENTS=0
SCHEMA=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-schema) SCHEMA="$2"; shift 2 ;;
        --output-last-message) DEST="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --json) JSON_EVENTS=1; shift ;;
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
[[ "$MODEL" == "${NF_TEST_EXPECTED_MODEL:-}" && -z "$EFFORT" && "$ISOLATED" == 1 && "$EPHEMERAL" == 1 && "$SANDBOX" == read-only && "$APPROVAL" == 'approval_policy="never"' && "$SHELL_DISABLED" == 1 && "$JSON_EVENTS" == 1 ]] || {
    echo 'Unexpected model, reasoning override, or execution safeguards' >&2
    exit 1
}
cat >"${NF_TEST_INPUT:-/dev/null}"
case "${NF_TEST_MODE:-success}" in
    fail) echo 'authentication failed: 401' >&2; exit 1 ;;
    unavailable) echo 'The selected model is not supported when using Codex with a ChatGPT account.' >&2; exit 1 ;;
    model_missing) echo 'model_not_found: model does not exist or you do not have access' >&2; exit 1 ;;
    model_access_denied) echo 'model_access_denied' >&2; exit 1 ;;
    json_model_error) printf '%s\n' '{"type":"turn.failed","error":{"message":"model_access_denied"}}'; exit 1 ;;
    malformed) printf '{"title":' > "$DEST" ;;
    empty) printf '{}' > "$DEST" ;;
    hang) exec /bin/sleep 30 ;;
    interview|interview_followup|interview_empty|interview_three)
       [[ "$SCHEMA" == */Interview.schema.json ]] || exit 1
       case "$NF_TEST_MODE" in
         interview) printf '%s' '{"questions":[{"question":"What does Jamie mean by it?","excerpt":"Jamie: I can send it Friday.","options":["The proposal","The schedule"]}]}' > "$DEST" ;;
         interview_followup) printf '%s' '{"questions":[{"question":"Which Friday is intended?","excerpt":"Jamie: I can send it Friday.","options":[]}]}' > "$DEST" ;;
         interview_three) printf '%s' '{"questions":[{"question":"What does Jamie mean by it?","excerpt":"Jamie: I can send it Friday.","options":["The proposal","The schedule"]},{"question":"Which Friday is intended?","excerpt":"Jamie: I can send it Friday.","options":[]},{"question":"Who should review the proposal?","excerpt":"Alex: We still need to review the proposal before deciding what to share with the project team.","options":["The project team","Alex"]}]}' > "$DEST" ;;
         interview_empty) printf '%s' '{"questions":[]}' > "$DEST" ;;
       esac
       printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":20}}' ;;

    *) cp "$(dirname "$0")/fixture.json" "$DEST"
       printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":250}}' ;;
esac
