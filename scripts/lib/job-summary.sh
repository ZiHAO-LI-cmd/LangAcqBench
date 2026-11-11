#!/usr/bin/env bash
# Source after PROJECT_ROOT, RUN_DIR, AGENT, and JOB_STARTED_AT are set.
job_summary_on_exit() {
    local status=$?
    trap - EXIT

    # Agent scripts may define this to save refreshed login credentials.
    if declare -F agent_cleanup >/dev/null; then
        agent_cleanup || status=$?
    fi

    local model_args=()
    if [[ -n "${MODEL_ID:-}" ]]; then
        model_args=(--model "$MODEL_ID")
    fi
    python3 "$PROJECT_ROOT/scripts/lib/agent-summary.py" \
        "$AGENT" "$RUN_DIR/agent.jsonl" "$JOB_STARTED_AT" "$(date +%s)" "$status" \
        "${model_args[@]}" || true
    exit "$status"
}
trap job_summary_on_exit EXIT
