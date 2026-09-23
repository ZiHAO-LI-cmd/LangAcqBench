#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

AGENT="${AGENT:-opencode}"
case "$AGENT" in
    opencode) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive" ;;
    codex) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive/codex" ;;
    claude) DEFAULT_RUN_DIR="$PROJECT_ROOT/interactive/claude" ;;
    *) echo "Unsupported AGENT: $AGENT (expected opencode, codex, or claude)" >&2; exit 2 ;;
esac

# The interactive environment is used by default; for batch jobs, a separate directory can be specified using RUN_DIR.
RUN_DIR="${RUN_DIR:-$DEFAULT_RUN_DIR}"
mkdir -p "$RUN_DIR/home" "$RUN_DIR/work"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"

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
    "${GPU_ARGS[@]}" \
    --home "$RUN_DIR/home:/home/agent" \
    --bind "$RUN_DIR/work:/workspace" \
    --bind "$HF_HOME:/hf-cache" \
    --bind "$RUNTIME_TMP:/tmp" \
    --bind "$PROJECT_ROOT/models:/models:ro" \
    --bind "$PROJECT_ROOT/data:/data:ro" \
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
