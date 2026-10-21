#!/bin/bash
#SBATCH --job-name=kimi-task
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
    echo "Usage: sbatch scripts/kimi.sh MODEL_ALIAS EXPERIMENT_CONFIG [EFFORT_LEVEL]" >&2
    exit 2
fi
# Kimi 2.2.0 has no effort CLI flag; override only the copied job config.
EFFORT_LEVEL="${3:-}"
if [[ -n "$EFFORT_LEVEL" ]]; then
    case "$EFFORT_LEVEL" in
        low|medium|high|xhigh|max) ;;
        *) echo "Invalid Kimi effort level: $EFFORT_LEVEL (expected low, medium, high, xhigh, max)" >&2; exit 2 ;;
    esac
fi
source "$SLURM_SUBMIT_DIR/env.sh"
MODEL_ID="${1:?Please provide a configured Kimi model alias}"
EXPERIMENT_CONFIG="${2:?Please provide an experiment JSON config path}"
if [[ "$EXPERIMENT_CONFIG" != /* ]]; then
    EXPERIMENT_CONFIG="$SLURM_SUBMIT_DIR/$EXPERIMENT_CONFIG"
fi
test -f "$EXPERIMENT_CONFIG"
export AGENT=kimi
export RUN_DIR="$PROJECT_ROOT/runs/${SLURM_JOB_NAME:-kimi-task}-$SLURM_JOB_ID"
export USE_GPU=1
source "$PROJECT_ROOT/scripts/job-summary.sh"

KIMI_RUN_HOME="$RUN_DIR/home/.kimi-code"
mkdir -p "$KIMI_RUN_HOME/credentials" "$RUN_DIR/work"
chmod 700 "$RUN_DIR/home" "$KIMI_RUN_HOME" "$KIMI_RUN_HOME/credentials"
source "$PROJECT_ROOT/scripts/prepare-agent.sh"

# Copy provider/model configuration and tokens, but no sessions, plugins or
# previous workspace state. Config may contain API keys: treat it as a secret.
KIMI_AUTH_HOME="$PROJECT_ROOT/interactive/kimi/home/.kimi-code"
if [[ ! -s "$KIMI_AUTH_HOME/config.toml" ]]; then
    echo "Missing Kimi config.toml; log in/configure the interactive Kimi home first." >&2
    exit 1
fi
command -v flock >/dev/null
exec 9>"$KIMI_AUTH_HOME/batch.lock"
flock -n 9 || { echo "Another Kimi job is using this login; retry later." >&2; exit 1; }
install -m 600 "$KIMI_AUTH_HOME/config.toml" "$KIMI_RUN_HOME/config.toml"
if [[ -n "$EFFORT_LEVEL" ]]; then
    # Use the image's Python 3.12/tomllib, not the host Python. Feed the helper
    # through stdin so it also works with train_only's restricted mounts.
    USE_GPU=0 bash "$PROJECT_ROOT/scripts/in-container.sh" \
        python3 - /home/agent/.kimi-code/config.toml "$MODEL_ID" "$EFFORT_LEVEL" \
        < "$PROJECT_ROOT/scripts/set-kimi-effort.py"
fi
shopt -s nullglob
AUTH_FILES=("$KIMI_AUTH_HOME/credentials/"*.json)
for credential in "${AUTH_FILES[@]}"; do
    install -m 600 "$credential" "$KIMI_RUN_HOME/credentials/$(basename "$credential")"
done
agent_cleanup() {
    local credential updated
    for credential in "$KIMI_RUN_HOME/credentials/"*.json; do
        [[ -s "$credential" ]] || continue
        mkdir -p "$KIMI_AUTH_HOME/credentials" || return 1
        chmod 700 "$KIMI_AUTH_HOME/credentials" || return 1
        updated="$(mktemp "$KIMI_AUTH_HOME/credentials/.refresh.XXXXXX")" || return 1
        if ! cp "$credential" "$updated" || ! mv -f "$updated" "$KIMI_AUTH_HOME/credentials/$(basename "$credential")"; then
            echo "Failed to persist Kimi authentication; inspect the run credential files." >&2
            return 1
        fi
    done
}

# In Kimi Code 2.2.0, -p already uses auto permissions; combining it with
# --yolo or --auto is invalid. Keep the full prompt in the workspace instead
# of a potentially huge command-line argument; no stdin support is assumed.
set +e
srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    kimi --model "$MODEL_ID" \
    --prompt 'Read /workspace/prompt.md and follow all task instructions in that file.' \
    --output-format stream-json \
    > "$RUN_DIR/agent.jsonl" \
    2> "$RUN_DIR/agent.err"
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
        if (isinstance(event, dict) and event.get("role") == "assistant"
                and not event.get("tool_calls") and isinstance(event.get("content"), str)):
            final = event["content"]
if final is not None:
    target.write_text(final.rstrip() + "\n", encoding="utf-8")
PY
exit "$AGENT_STATUS"
