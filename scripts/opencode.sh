#!/bin/bash
#SBATCH --job-name=opencode-task
#SBATCH --account=project_2008161
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=0-00:15:00
#SBATCH --output=logs/opencode-%j.out
#SBATCH --error=logs/opencode-%j.err

set -euo pipefail
umask 077
JOB_STARTED_AT="$(date +%s)"

# Usage: sbatch scripts/opencode.sh MODEL EXPERIMENT_CONFIG [REASONING_LEVEL]
if (( $# < 2 || $# > 3 )); then
    echo "Usage: sbatch scripts/opencode.sh MODEL EXPERIMENT_CONFIG [REASONING_LEVEL]" >&2
    exit 2
fi

source "$SLURM_SUBMIT_DIR/env.sh"

MODEL_ID="${1:?Please provide provider/model}"
EXPERIMENT_CONFIG="${2:?Please provide an experiment JSON config path}"
# Omit the optional level to retain the CLI/model default.
REASONING_LEVEL="${3:-}"
REASONING_ARGS=()
if [[ -n "$REASONING_LEVEL" ]]; then
    # Variant names and availability depend on the provider/model.
    REASONING_ARGS=(--variant "$REASONING_LEVEL")
fi

if [[ "$EXPERIMENT_CONFIG" != /* ]]; then
    EXPERIMENT_CONFIG="$SLURM_SUBMIT_DIR/$EXPERIMENT_CONFIG"
fi
test -f "$EXPERIMENT_CONFIG"
export RUN_DIR="$PROJECT_ROOT/runs/opencode-$SLURM_JOB_ID"
export USE_GPU=1

mkdir -p \
    "$RUN_DIR/home/.local/share/opencode" \
    "$RUN_DIR/home/.config/opencode" \
    "$RUN_DIR/work"

# Snapshot inputs and render before starting the agent.
cp "$SLURM_SUBMIT_DIR/prompt.md" "$RUN_DIR/work/prompt.template.md"
cp "$EXPERIMENT_CONFIG" "$RUN_DIR/work/experiment.json"
python3 "$PROJECT_ROOT/scripts/render-prompt.py" \
    --template "$RUN_DIR/work/prompt.template.md" \
    --config "$RUN_DIR/work/experiment.json" \
    --output "$RUN_DIR/work/prompt.md"

# Copy the credential for this task to avoid sharing the entire session directory.
AUTH_SRC="$PROJECT_ROOT/interactive/home/.local/share/opencode/auth.json"
test -f "$AUTH_SRC"
cp "$AUTH_SRC" "$RUN_DIR/home/.local/share/opencode/auth.json"

cat > "$RUN_DIR/home/.config/opencode/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "permission": "allow"
}
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

PROMPT="$(cat "$RUN_DIR/work/prompt.md")"

srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    opencode run --model "$MODEL_ID" "${REASONING_ARGS[@]}" --format json "$PROMPT" \
    > "$RUN_DIR/agent.jsonl" \
    2> "$RUN_DIR/agent.err"
