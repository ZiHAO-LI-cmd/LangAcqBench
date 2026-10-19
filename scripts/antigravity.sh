#!/bin/bash
#SBATCH --job-name=antigravity-task
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
    echo "Usage: sbatch scripts/antigravity.sh MODEL EXPERIMENT_CONFIG [EFFORT_LEVEL]" >&2
    exit 2
fi
MODEL_ID="${1:?Please provide an Antigravity model slug}"
EFFORT_ARGS=()
if [[ -n "${3:-}" ]]; then
    case "$3" in
        low|medium|high|xhigh|max) EFFORT_ARGS=(--effort "$3") ;;
        *) echo "Invalid Antigravity effort level: $3" >&2; exit 2 ;;
    esac
fi
source "$SLURM_SUBMIT_DIR/env.sh"
EXPERIMENT_CONFIG="$2"
if [[ "$EXPERIMENT_CONFIG" != /* ]]; then
    EXPERIMENT_CONFIG="$SLURM_SUBMIT_DIR/$EXPERIMENT_CONFIG"
fi
test -f "$EXPERIMENT_CONFIG"
export AGENT=antigravity
export RUN_DIR="$PROJECT_ROOT/runs/${SLURM_JOB_NAME:-antigravity-task}-$SLURM_JOB_ID"
export USE_GPU=1
source "$PROJECT_ROOT/scripts/job-summary.sh"

mkdir -p "$RUN_DIR/home/.gemini/antigravity-cli" "$RUN_DIR/work"
chmod 700 "$RUN_DIR/home" "$RUN_DIR/home/.gemini" "$RUN_DIR/home/.gemini/antigravity-cli"
source "$PROJECT_ROOT/scripts/prepare-agent.sh"

# Keep interactive sessions, hooks and plugins out of the batch home. The key
# stays in the environment; settings only select the provider and task policies.
cat > "$RUN_DIR/home/.gemini/antigravity-cli/settings.json" <<'JSON'
{
  "modelProvider": "gemini",
  "enableTerminalSandbox": false,
  "allowNonWorkspaceAccess": true,
  "artifactReviewPolicy": "always-proceed"
}
JSON
chmod 600 "$RUN_DIR/home/.gemini/antigravity-cli/settings.json"

# Print mode otherwise times out after five minutes. Let the shared task timer
# and Slurm allocation bound the experiment, including long training commands.
PRINT_TIMEOUT="$(python3 - "$RUN_DIR/work/experiment.json" <<'PY'
import json
import math
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    hours = json.load(source)["num_hours"]
if isinstance(hours, bool) or not isinstance(hours, (int, float)) or not math.isfinite(hours) or hours <= 0:
    sys.exit("num_hours must be a positive finite number")
print(f"{math.ceil(hours * 3600)}s")
PY
)"

# Experiments require unattended tool execution in the Apptainer environment.
# Read the prompt from the workspace to avoid command-line size limits.
set +e
srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    agy --model "$MODEL_ID" "${EFFORT_ARGS[@]}" \
    --print 'Read /workspace/prompt.md and follow all task instructions in that file.' \
    --output-format stream-json --print-timeout "$PRINT_TIMEOUT" \
    --dangerously-skip-permissions \
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
        if not isinstance(event, dict) or event.get("event") != "result":
            continue
        result = event.get("result")
        if isinstance(result, dict) and isinstance(result.get("response"), str):
            final = result["response"]
if final is not None:
    target.write_text(final.rstrip() + "\n", encoding="utf-8")
PY
exit "$AGENT_STATUS"
