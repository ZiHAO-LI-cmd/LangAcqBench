#!/bin/bash
#SBATCH --job-name=claude-task
#SBATCH --account=project_2008161
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=0-00:15:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail
umask 077
JOB_STARTED_AT="$(date +%s)"

# Usage: sbatch scripts/claude.sh MODEL EXPERIMENT_CONFIG [EFFORT_LEVEL]
if (( $# < 2 || $# > 3 )); then
    echo "Usage: sbatch scripts/claude.sh MODEL EXPERIMENT_CONFIG [EFFORT_LEVEL]" >&2
    exit 2
fi

source "$SLURM_SUBMIT_DIR/env.sh"

MODEL_ID="${1:?Please provide a Claude model alias or ID}"
EXPERIMENT_CONFIG="${2:?Please provide an experiment JSON config path}"
EFFORT_LEVEL="${3:-}"
EFFORT_ARGS=()
if [[ -n "$EFFORT_LEVEL" ]]; then
    case "$EFFORT_LEVEL" in
        low|medium|high|xhigh|max) ;;
        *) echo "Invalid Claude effort level: $EFFORT_LEVEL (expected low, medium, high, xhigh, max)" >&2; exit 2 ;;
    esac
    EFFORT_ARGS=(--effort "$EFFORT_LEVEL")
fi

if [[ "$EXPERIMENT_CONFIG" != /* ]]; then
    EXPERIMENT_CONFIG="$SLURM_SUBMIT_DIR/$EXPERIMENT_CONFIG"
fi
test -f "$EXPERIMENT_CONFIG"
export AGENT=claude
export RUN_DIR="$PROJECT_ROOT/runs/${SLURM_JOB_NAME:-claude-task}-$SLURM_JOB_ID"
export USE_GPU=1
source "$PROJECT_ROOT/scripts/job-summary.sh"

mkdir -p "$RUN_DIR/home/.claude" "$RUN_DIR/work"
chmod 700 "$RUN_DIR/home/.claude"

# Select the experiment mode, snapshot inputs, copy tools and initialize time.
source "$PROJECT_ROOT/scripts/prepare-agent.sh"

# Prefer an API key passed through Apptainer's clean-environment mechanism.
# Otherwise serialize use of the rotating OAuth login and persist refreshed
# credentials after the job. Never copy an API key into the run directory.
if [[ -n "${APPTAINERENV_ANTHROPIC_API_KEY:-}" ]]; then
    : # The key is injected into the container by Apptainer.
else
    AUTH_SRC="$PROJECT_ROOT/interactive/claude/home/.claude/.credentials.json"
    test -s "$AUTH_SRC"
    command -v flock >/dev/null
    exec 9>"$(dirname "$AUTH_SRC")/batch.lock"
    flock -n 9 || { echo "Another Claude Code job is using this login; retry later." >&2; exit 1; }
    cp "$AUTH_SRC" "$RUN_DIR/home/.claude/.credentials.json"
    chmod 600 "$RUN_DIR/home/.claude/.credentials.json"
    agent_cleanup() {
        if [[ -s "$RUN_DIR/home/.claude/.credentials.json" ]]; then
            local updated
            updated="$(mktemp "$(dirname "$AUTH_SRC")/credentials-update.XXXXXX")" || return 1
            if ! cp "$RUN_DIR/home/.claude/.credentials.json" "$updated" || ! mv -f "$updated" "$AUTH_SRC"; then
                echo "Failed to persist Claude Code authentication; inspect the run credential file." >&2
                return 1
            fi
            chmod 600 "$AUTH_SRC"
        fi
    }
fi

# Batch sessions cannot answer permission prompts. This enables autonomous
# tool execution inside the isolated job home/work; submit trusted prompts only.
set +e
srun bash "$PROJECT_ROOT/scripts/in-container.sh" \
    claude -p \
    --model "$MODEL_ID" \
    "${EFFORT_ARGS[@]}" \
    --output-format stream-json --verbose \
    --dangerously-skip-permissions \
    "Follow the full task instructions provided on stdin." \
    < "$RUN_DIR/work/prompt.md" \
    > "$RUN_DIR/agent.jsonl" \
    2> "$RUN_DIR/agent.err"
AGENT_STATUS=$?
set -e

# Keep the final assistant answer in a convenient plain-text artifact while
# preserving the full event stream in agent.jsonl.
python3 - "$RUN_DIR/agent.jsonl" "$RUN_DIR/work/agent-final.md" <<'PY'
import json
import sys
from pathlib import Path

source, target = map(Path, sys.argv[1:])
final = None
for line in source.read_text(errors="replace").splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") == "result" and isinstance(event.get("result"), str):
        final = event["result"]
if final is not None:
    target.write_text(final.rstrip() + "\n")
PY

exit "$AGENT_STATUS"
