#!/bin/bash
#SBATCH --job-name=opencode-task
#SBATCH --account=project_2008161
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=0-00:15:00
#SBATCH --output=runs/%x-%j/%x-%j.out
#SBATCH --error=runs/%x-%j/%x-%j.err

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
export RUN_DIR="$PROJECT_ROOT/runs/${SLURM_JOB_NAME:-opencode-task}-$SLURM_JOB_ID"
export USE_GPU=1
export AGENT=opencode
source "$PROJECT_ROOT/scripts/job-summary.sh"

mkdir -p \
    "$RUN_DIR/home/.local/share/opencode" \
    "$RUN_DIR/home/.config/opencode" \
    "$RUN_DIR/work"

# Select the experiment mode, snapshot inputs, copy tools and initialize time.
source "$PROJECT_ROOT/scripts/prepare-agent.sh"

# Copy the credential for this task to avoid sharing the entire session directory.
AUTH_SRC="$PROJECT_ROOT/interactive/home/.local/share/opencode/auth.json"
test -f "$AUTH_SRC"
cp "$AUTH_SRC" "$RUN_DIR/home/.local/share/opencode/auth.json"

# Custom provider definitions (deployment IDs, endpoints and variants) live in
# configuration, not auth.json. Snapshot only the selected provider so jobs do
# not inherit unrelated interactive agents, plugins or instructions.
python3 - "$PROJECT_ROOT/interactive/home/.config/opencode/opencode.json" \
    "$RUN_DIR/home/.config/opencode/opencode.json" "$MODEL_ID" <<'PY'
import json
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
provider_id = sys.argv[3].split("/", 1)[0]
config = {
    "$schema": "https://opencode.ai/config.json",
    "autoupdate": False,
    "permission": "allow",
}
if source.exists():
    providers = json.loads(source.read_text(encoding="utf-8")).get("provider", {})
    if provider_id in providers:
        config["provider"] = {provider_id: providers[provider_id]}
destination.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

PROMPT="$(cat "$RUN_DIR/work/prompt.md")"

srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    opencode run --print-logs --log-level ERROR \
    --model "$MODEL_ID" "${REASONING_ARGS[@]}" --format json "$PROMPT" \
    > "$RUN_DIR/agent.jsonl" \
    2> "$RUN_DIR/agent.err"
