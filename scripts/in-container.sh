#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

# 默认使用交互环境；批量作业可通过 RUN_DIR 指定独立目录
RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/interactive}"
mkdir -p "$RUN_DIR/home" "$RUN_DIR/work"
RUN_DIR="$(cd "$RUN_DIR" && pwd)"

chmod 700 "$RUN_DIR/home"

mkdir -p \
    "$RUN_DIR/home/.config" \
    "$RUN_DIR/home/.cache" \
    "$RUN_DIR/home/.local/share" \
    "$RUN_DIR/home/.local/state"

RUNTIME_TMP="$TMPDIR/opencode-${SLURM_JOB_ID:-interactive}"
mkdir -p "$RUNTIME_TMP"

GPU_ARGS=()
if [[ "${USE_GPU:-0}" == "1" ]]; then
    GPU_ARGS+=(--nv)

    # 在 Slurm 作业步骤内保留调度器设置的 GPU 可见性
    if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
        GPU_ARGS+=(--env "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES")
    fi
fi

if [[ "$#" -eq 0 ]]; then
    set -- opencode
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
    "$PROJECT_ROOT/containers/opencode.sif" \
    "$@"