#!/usr/bin/env bash
# Source after setting EXPERIMENT_CONFIG, RUN_DIR, PROJECT_ROOT and JOB_STARTED_AT.
# All agents use the same mode selection, snapshot and tool-copy rules.
cp "$EXPERIMENT_CONFIG" "$RUN_DIR/work/experiment.json"
EXPERIMENT_MODE="$(python3 "$PROJECT_ROOT/scripts/experiment_config.py" "$RUN_DIR/work/experiment.json")"
export EXPERIMENT_MODE

case "$EXPERIMENT_MODE" in
    standard) PROMPT_TEMPLATE="$SLURM_SUBMIT_DIR/prompt.md" ;;
    train_only) PROMPT_TEMPLATE="$SLURM_SUBMIT_DIR/prompt.train-only.md" ;;
esac

cp "$PROMPT_TEMPLATE" "$RUN_DIR/work/prompt.template.md"
python3 "$PROJECT_ROOT/scripts/render-prompt.py" \
    --template "$RUN_DIR/work/prompt.template.md" \
    --config "$RUN_DIR/work/experiment.json" \
    --output "$RUN_DIR/work/prompt.md"

cp "$PROJECT_ROOT/timer.sh" "$RUN_DIR/work/"
if [[ "$EXPERIMENT_MODE" == standard ]]; then
    cp "$PROJECT_ROOT/scripts/evaluate-mt.py" "$PROJECT_ROOT/scripts/evaluate.sh" "$RUN_DIR/work/"
fi

TIMER_ARGS=(--init --config "$RUN_DIR/work/experiment.json" --start "$JOB_STARTED_AT")
JOB_END_EPOCH="${SLURM_JOB_END_TIME:-}"
if [[ ! "$JOB_END_EPOCH" =~ ^[0-9]+$ ]] && command -v scontrol >/dev/null 2>&1; then
    JOB_INFO="$(scontrol show job "$SLURM_JOB_ID" -o 2>/dev/null || true)"
    if [[ "$JOB_INFO" =~ EndTime=([^[:space:]]+) ]]; then
        JOB_END_EPOCH="$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || true)"
    fi
fi
if [[ "$JOB_END_EPOCH" =~ ^[0-9]+$ ]]; then
    TIMER_ARGS+=(--deadline "$JOB_END_EPOCH")
fi
bash "$RUN_DIR/work/timer.sh" "${TIMER_ARGS[@]}"
