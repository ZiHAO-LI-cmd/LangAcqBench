#!/usr/bin/env bash
# Submit an agent job with a readable, shared name for Slurm, logs, and runs.
set -euo pipefail

if (( $# < 3 || $# > 4 )); then
    echo "Usage: scripts/submit-agent.sh {opencode|codex|claude} MODEL EXPERIMENT_CONFIG [REASONING_OR_EFFORT_LEVEL]" >&2
    exit 2
fi

agent="$1"
model="$2"
config="$3"
case "$agent" in
    opencode|codex|claude) ;;
    *) echo "Unknown agent: $agent" >&2; exit 2 ;;
esac
[[ -n "$model" ]] || { echo "MODEL must not be empty" >&2; exit 2; }
[[ -f "$config" ]] || { echo "Experiment config not found: $config" >&2; exit 2; }
config="$(cd "$(dirname "$config")" && pwd)/$(basename "$config")"

# Slurm reads #SBATCH lines before running the script, so set these at submit
# time. Its time limit has one-minute resolution.
minutes="$(python3 - "$config" <<'PY'
import json
import math
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as file:
        hours = json.load(file)["num_hours"]
    if isinstance(hours, bool) or not isinstance(hours, (int, float)) or not math.isfinite(hours) or hours <= 0:
        raise ValueError("num_hours must be a positive finite number")
    print(math.ceil(hours * 60))
except (OSError, KeyError, ValueError, OverflowError) as exc:
    sys.exit(f"Invalid experiment config: {exc}")
PY
)"
if (( minutes > 15 )); then
    partition=gpumedium
else
    partition=gputest
fi

# The config filename is the human-readable experiment label. Keep Slurm job
# names short and path-safe; the numeric job ID makes each output unique.
slug() {
    local value
    value="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c 1-32)"
    printf '%s' "${value%-}"
}
experiment="$(slug "$(basename "${config%.json}")")"
model_slug="$(slug "$model")"
[[ -n "$experiment" ]] || experiment=experiment
[[ -n "$model_slug" ]] || model_slug=model
job_name="$agent-$experiment-$model_slug"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mkdir -p logs
sbatch --job-name="$job_name" --time="$minutes" --partition="$partition" \
    "scripts/$agent.sh" "$model" "$config" "${@:4}"
