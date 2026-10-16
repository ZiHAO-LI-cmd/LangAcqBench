#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

AGENT="${AGENT:-opencode}"
case "$AGENT" in
    opencode) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive" ;;
    codex) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive/codex" ;;
    claude) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive/claude" ;;
    kimi) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive/kimi" ;;
    *) echo "Unsupported AGENT: $AGENT (expected opencode, codex, claude, or kimi)" >&2; exit 2 ;;
esac

# The interactive environment is used by default; for batch jobs, a separate directory can be specified using RUN_DIR.
RUN_DIR="${RUN_DIR:-$DEFAULT_RUN_DIR}"
mkdir -p "$RUN_DIR/home" "$RUN_DIR/work"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"

# Read the snapshotted mode for batch jobs; interactive use remains standard.
if [[ -f "$RUN_DIR/work/experiment.json" ]]; then
    EXPERIMENT_MODE="$(python3 "$SCRIPT_DIR/experiment_config.py" "$RUN_DIR/work/experiment.json")"
else
    EXPERIMENT_MODE="${EXPERIMENT_MODE:-standard}"
fi
DATA_ARGS=()
ISOLATION_ARGS=()
CONTAINER_HF_HOME="$HF_HOME"
case "$EXPERIMENT_MODE" in
    standard)
        DATA_ARGS+=(--bind "$PROJECT_ROOT/data:/data:ro")
        ;;
    train_only)
        # Do not expose the shared HF cache: it can contain benchmark splits
        # downloaded by earlier runs. Mount only the configured training paths.
        CONTAINER_HF_HOME="$RUN_DIR/hf-cache"
        mkdir -p "$CONTAINER_HF_HOME"
        TRAIN_BINDS="$(python3 "$SCRIPT_DIR/experiment_config.py" "$RUN_DIR/work/experiment.json" --binds)"
        while IFS= read -r bind; do
            DATA_ARGS+=(--bind "$bind")
        done <<< "$TRAIN_BINDS"
        # Suppress inherited/site mounts and host process visibility that could
        # expose test data, evaluation scripts or other run directories.
        ISOLATION_ARGS+=(--containall --no-mount hostfs,bind-paths,cwd)
        unset APPTAINER_BIND APPTAINER_BINDPATH SINGULARITY_BIND SINGULARITY_BINDPATH
        ;;
    *) echo "Unsupported experiment_mode: $EXPERIMENT_MODE" >&2; exit 2 ;;
esac

chmod 700 "$RUN_DIR/home"

mkdir -p \
    "$RUN_DIR/home/.config" \
    "$RUN_DIR/home/.cache" \
    "$RUN_DIR/home/.local/share" \
    "$RUN_DIR/home/.local/state"

case "$AGENT" in
    opencode)
        CREDENTIAL_DIR="$RUN_DIR/home/.local/share/opencode"
        CREDENTIAL_FILE="$CREDENTIAL_DIR/auth.json"
        ;;
    codex)
        CREDENTIAL_DIR="$RUN_DIR/home/.codex"
        CREDENTIAL_FILE="$CREDENTIAL_DIR/auth.json"
        ;;
    claude)
        CREDENTIAL_DIR="$RUN_DIR/home/.claude"
        CREDENTIAL_FILE="$CREDENTIAL_DIR/.credentials.json"
        ;;
    kimi)
        CREDENTIAL_DIR="$RUN_DIR/home/.kimi-code/credentials"
        CREDENTIAL_FILE="$CREDENTIAL_DIR/kimi-code.json"
        ;;
esac
mkdir -p "$CREDENTIAL_DIR"
chmod 700 "$CREDENTIAL_DIR"
if [[ -f "$CREDENTIAL_FILE" ]]; then
    chmod 600 "$CREDENTIAL_FILE"
fi

RUNTIME_TMP="$TMPDIR/$AGENT-${SLURM_JOB_ID:-interactive}"
mkdir -p "$RUNTIME_TMP"

GPU_ARGS=()
if [[ "${USE_GPU:-0}" == "1" ]]; then
    GPU_ARGS+=(--nv)

    # Preserving GPU visibility set by the scheduler within Slurm job steps
    if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
        GPU_ARGS+=(--env "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES")
    fi
fi

if [[ "$#" -eq 0 ]]; then
    set -- "$AGENT"
fi

exec apptainer exec --cleanenv --contain \
    "${ISOLATION_ARGS[@]}" \
    "${GPU_ARGS[@]}" \
    --home "$RUN_DIR/home:/home/agent" \
    --bind "$RUN_DIR/work:/workspace" \
    --bind "$CONTAINER_HF_HOME:/hf-cache" \
    --bind "$RUNTIME_TMP:/tmp" \
    --bind "$PROJECT_ROOT/models:/models:ro" \
    "${DATA_ARGS[@]}" \
    --pwd /workspace \
    --env HF_HOME=/hf-cache \
    --env XDG_CONFIG_HOME=/home/agent/.config \
    --env XDG_CACHE_HOME=/home/agent/.cache \
    --env XDG_DATA_HOME=/home/agent/.local/share \
    --env XDG_STATE_HOME=/home/agent/.local/state \
    --env PYTHONNOUSERSITE=1 \
    --env "TERM=${TERM:-xterm-256color}" \
    "$PROJECT_ROOT/containers/$AGENT.sif" \
    "$@"
