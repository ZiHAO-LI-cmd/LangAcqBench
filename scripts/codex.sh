#!/bin/bash
#SBATCH --job-name=codex-task
#SBATCH --account=project_2008161
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=0-00:15:00
#SBATCH --output=logs/codex-%j.out
#SBATCH --error=logs/codex-%j.err

set -euo pipefail
umask 077
JOB_STARTED_AT="$(date +%s)"

# Usage: sbatch scripts/codex.sh MODEL EXPERIMENT_CONFIG [REASONING_LEVEL]
if (( $# < 2 || $# > 3 )); then
    echo "Usage: sbatch scripts/codex.sh MODEL EXPERIMENT_CONFIG [REASONING_LEVEL]" >&2
    exit 2
fi

source "$SLURM_SUBMIT_DIR/env.sh"

MODEL_ID="${1:?Please provide a Codex model ID}"
EXPERIMENT_CONFIG="${2:?Please provide an experiment JSON config path}"
# Omit the optional level to retain the CLI/model default.
REASONING_LEVEL="${3:-}"
REASONING_ARGS=()
if [[ -n "$REASONING_LEVEL" ]]; then
    case "$REASONING_LEVEL" in
        none|minimal|low|medium|high|xhigh) ;;
        *) echo "Invalid Codex reasoning level: $REASONING_LEVEL (expected none, minimal, low, medium, high, xhigh)" >&2; exit 2 ;;
    esac
    REASONING_ARGS=(-c "model_reasoning_effort=\"$REASONING_LEVEL\"")
fi

if [[ "$EXPERIMENT_CONFIG" != /* ]]; then
    EXPERIMENT_CONFIG="$SLURM_SUBMIT_DIR/$EXPERIMENT_CONFIG"
fi
test -f "$EXPERIMENT_CONFIG"
export AGENT=codex
export RUN_DIR="$PROJECT_ROOT/runs/codex-$SLURM_JOB_ID"
export USE_GPU=1

mkdir -p \
    "$RUN_DIR/home/.codex" \
    "$RUN_DIR/work"

# Snapshot inputs and render before starting the agent.
cp "$SLURM_SUBMIT_DIR/prompt.md" "$RUN_DIR/work/prompt.template.md"
cp "$EXPERIMENT_CONFIG" "$RUN_DIR/work/experiment.json"
python3 "$PROJECT_ROOT/scripts/render-prompt.py" \
    --template "$RUN_DIR/work/prompt.template.md" \
    --config "$RUN_DIR/work/experiment.json" \
    --output "$RUN_DIR/work/prompt.md"

# Keep session history per job, but persist refreshed credentials for later jobs.
# Fail fast instead of burning a GPU allocation waiting for another auth user.
AUTH_SRC="$PROJECT_ROOT/interactive/codex/home/.codex/auth.json"
test -f "$AUTH_SRC"
command -v flock >/dev/null
exec 9>"$(dirname "$AUTH_SRC")/batch.lock"
flock -n 9 || { echo "Another Codex job is using this login; retry later." >&2; exit 1; }
cp "$AUTH_SRC" "$RUN_DIR/home/.codex/auth.json"
persist_auth() {
    local status=$?
    trap - EXIT
    if [[ -s "$RUN_DIR/home/.codex/auth.json" ]]; then
        local updated
        updated=$(mktemp "$(dirname "$AUTH_SRC")/auth-update.XXXXXX") || exit 1
        if ! cp "$RUN_DIR/home/.codex/auth.json" "$updated" || ! mv -f "$updated" "$AUTH_SRC"; then
            echo "Failed to persist Codex authentication; inspect the run auth file." >&2
            exit 1
        fi
    fi
    exit "$status"
}
trap persist_auth EXIT
cat > "$RUN_DIR/home/.codex/config.toml" <<'EOF'
cli_auth_credentials_store = "file"
EOF

# Make the fixed task tools available in the container workspace.
cp "$PROJECT_ROOT/evaluate.py" "$PROJECT_ROOT/timer.sh" "$RUN_DIR/work/"
TIMER_ARGS=(--init --config "$RUN_DIR/work/experiment.json" --start "$JOB_STARTED_AT")
JOB_END_EPOCH="${SLURM_JOB_END_TIME:-}"
if [[ ! "$JOB_END_EPOCH" =~ ^[0-9]+$ ]] && command -v scontrol >/dev/null 2>&1; then
    JOB_INFO="$(scontrol show job "$SLURM_JOB_ID" -o 2>/dev/null || true)"
    if [[ "$JOB_INFO" =~ EndTime=([^[:space:]]+) ]]; then
        JOB_END_EPOCH="$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || true)"
    fi
fi
if [[ "$JOB_END_EPOCH" =~ ^[0-9]+$ ]]; then
    TIMER_ARGS+=(--deadline "$JOB_END_EPOCH")
fi
bash "$RUN_DIR/work/timer.sh" "${TIMER_ARGS[@]}"

# Approval prompts cannot be answered in a batch job. Full host-user execution
# is explicit here, matching the existing OpenCode batch tool permissions.
# Only run trusted experiments; Apptainer containment is not a VM boundary.
srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    codex exec --model "$MODEL_ID" "${REASONING_ARGS[@]}" --json --skip-git-repo-check \
    --dangerously-bypass-approvals-and-sandbox \
    --output-last-message /workspace/agent-final.md - \
    < "$RUN_DIR/work/prompt.md" \
    > "$RUN_DIR/agent.jsonl" \
    2> "$RUN_DIR/agent.err"
