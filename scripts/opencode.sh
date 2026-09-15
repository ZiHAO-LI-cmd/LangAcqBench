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

source "$SLURM_SUBMIT_DIR/env.sh"

MODEL_ID="${1:?Please provide provider/model}"
export RUN_DIR="$PROJECT_ROOT/runs/opencode-$SLURM_JOB_ID"
export USE_GPU=1

mkdir -p \
    "$RUN_DIR/home/.local/share/opencode" \
    "$RUN_DIR/home/.config/opencode" \
    "$RUN_DIR/work"

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

cp "$SLURM_SUBMIT_DIR/prompt.txt" "$RUN_DIR/work/prompt.txt"
PROMPT="$(cat "$RUN_DIR/work/prompt.txt")"

srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    opencode run --model "$MODEL_ID" --format json "$PROMPT" \
    > "$RUN_DIR/agent.jsonl" \
    2> "$RUN_DIR/agent.err"