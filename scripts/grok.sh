#!/bin/bash
#SBATCH --job-name=grok-task
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

if (( $# < 2 || $# > 3 )); then
    echo "Usage: sbatch scripts/grok.sh MODEL EXPERIMENT_CONFIG [EFFORT_LEVEL]" >&2
    exit 2
fi
MODEL_ID="${1:?Please provide a Grok model ID}"
EFFORT_ARGS=()
if [[ -n "${3:-}" ]]; then
    case "$3" in
        none|minimal|low|medium|high|xhigh|max) EFFORT_ARGS=(--reasoning-effort "$3") ;;
        *) echo "Invalid Grok effort level: $3" >&2; exit 2 ;;
    esac
fi
source "$SLURM_SUBMIT_DIR/env.sh"
EXPERIMENT_CONFIG="$2"
if [[ "$EXPERIMENT_CONFIG" != /* ]]; then
    EXPERIMENT_CONFIG="$SLURM_SUBMIT_DIR/$EXPERIMENT_CONFIG"
fi
test -f "$EXPERIMENT_CONFIG"
export AGENT=grok
export RUN_DIR="$PROJECT_ROOT/runs/${SLURM_JOB_NAME:-grok-task}-$SLURM_JOB_ID"
export USE_GPU=1
source "$PROJECT_ROOT/scripts/job-summary.sh"

mkdir -p "$RUN_DIR/home/.grok" "$RUN_DIR/work"
chmod 700 "$RUN_DIR/home" "$RUN_DIR/home/.grok"
source "$PROJECT_ROOT/scripts/prepare-agent.sh"

# Reuse persistent model/provider configuration, as with the Kimi launcher.
# An explicit file overrides it; relative paths use the submitting directory.
GROK_CONFIG_SOURCE="$PROJECT_ROOT/interactive/grok/home/.grok/config.toml"
if [[ -n "${GROK_CONFIG_FILE:-}" ]]; then
    GROK_CONFIG_SOURCE="$GROK_CONFIG_FILE"
    if [[ "$GROK_CONFIG_SOURCE" != /* ]]; then
        GROK_CONFIG_SOURCE="$SLURM_SUBMIT_DIR/$GROK_CONFIG_SOURCE"
    fi
fi
if [[ -f "$GROK_CONFIG_SOURCE" ]]; then
    install -m 600 "$GROK_CONFIG_SOURCE" "$RUN_DIR/home/.grok/config.toml"
elif [[ -n "${GROK_CONFIG_FILE:-}" ]]; then
    echo "Grok config not found: $GROK_CONFIG_SOURCE" >&2
    exit 1
else
    # The default uses XAI_API_KEY without copying interactive credentials.
    cat > "$RUN_DIR/home/.grok/config.toml" <<'TOML'
[cli]
auto_update = false
TOML
fi
chmod 600 "$RUN_DIR/home/.grok/config.toml"

# Read the actual rendered prompt directly, with unattended tools inside the
# existing Apptainer mount boundary. Slurm and the shared timer bound runtime.
set +e
srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    grok --model "$MODEL_ID" "${EFFORT_ARGS[@]}" \
    --prompt-file /workspace/prompt.md --output-format streaming-messages-json \
    --yolo --sandbox off --no-auto-update \
    < /dev/null > "$RUN_DIR/agent.jsonl" 2> "$RUN_DIR/agent.err"
AGENT_STATUS=$?
set -e

python3 - "$RUN_DIR/agent.jsonl" "$RUN_DIR/work/agent-final.md" <<'PY'
import json
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
final = None
with source.open(encoding="utf-8", errors="replace") as stream:
    for line in stream:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (isinstance(event, dict) and event.get("type") == "result"
                and isinstance(event.get("result"), str)):
            final = event["result"]
if final is not None:
    target.write_text(final.rstrip() + "\n", encoding="utf-8")
PY
exit "$AGENT_STATUS"
