#!/bin/bash
set -euo pipefail

# Run this script inside a Slurm allocation. For the local resource defaults,
# submit scripts/evaluate-slurm.sh instead.
usage() {
    cat <<'EOF'
Usage: bash scripts/evaluate.sh MODEL --mt-dirs CODE=NAME CODE=NAME \
         [--mono-tasks TASK [TASK ...]] [OPTIONS]

Run translation evaluation inside an existing Slurm allocation.

  MODEL           Model directory under models/, models/NAME, or an absolute path.
  --mt-dirs       Required language code/name pairs; supply at least two.
                  All ordered translation directions are evaluated by default.
  --mono-tasks    Optional lm_eval tasks, separated by spaces or commas.
  OPTIONS         Additional options accepted by scripts/evaluation/evaluate-mt.py.

Common options:
  --n-shot N      Few-shot examples per prompt (default: 3; use 0 without data/dev).
  --dev-dir DIR   Aligned examples for few-shot evaluation.
  --output FILE   Override the default translation JSON path.
  --no-comet      Skip COMET scoring (enabled by default: Unbabel/wmt22-comet-da).
  --comet-model MODEL  Use a Hugging Face model ID or local COMET .ckpt.
  --comet-batch-size N  COMET batch size (default: 8).
  --comet-gpus N   COMET devices: 0 for CPU, 1 for GPU (default: 1).
  --validate-only Check translation data without inference, scoring, or reporting.

Results: runs/evaluate/MODEL__job-JOB_ID/{translation.json,lm-eval_*.json,summary.xlsx}
Translation samples are saved beside the JSON for later COMET scoring.
COMET runs by default after the translation process exits. See docs/evaluation.md for setup.

Environment:
  PROJECT_DIR     Repository path (defaults to this project's host path).
  COMET_PYTHON    Separate COMET interpreter (default: PROJECT_DIR/env-comet/bin/python).

Example (inside a Slurm allocation):
  bash scripts/evaluate.sh SmolLM3-3B \
    --mt-dirs eng_Latn=English swe_Latn=Swedish --n-shot 0 \
    --mono-tasks belebele_swe_Latn

Use scripts/evaluate-slurm.sh to request the local Slurm resources.
EOF
}

if (( $# == 0 )); then
    usage >&2
    exit 2
fi
if [[ "$1" == -h || "$1" == --help ]]; then
    usage
    exit 0
fi

MODEL="$1"
shift
mono_tasks=""
has_mt_dirs=0
evaluator_args=()
translation_output=""
comet_enabled=1
comet_model="Unbabel/wmt22-comet-da"
comet_batch_size=8
comet_gpus=1
validate_only=0
while (( $# )); do
    case "$1" in
        --no-comet)
            comet_enabled=0
            shift
            ;;
        --comet)
            comet_enabled=1
            shift
            ;;
        --comet-model|--comet-model=*|--comet-batch-size|--comet-batch-size=*|--comet-gpus|--comet-gpus=*)
            option="${1%%=*}"
            if [[ "$1" == *=* ]]; then
                value="${1#*=}"
                shift
            else
                if (( $# < 2 )) || [[ "$2" == -* ]]; then
                    echo "$1 requires a value." >&2
                    exit 2
                fi
                value="$2"
                shift 2
            fi
            if [[ -z "$value" ]]; then
                echo "$option requires a value." >&2
                exit 2
            fi
            case "$option" in
                --comet-model) comet_model="$value" ;;
                --comet-batch-size) comet_batch_size="$value" ;;
                --comet-gpus) comet_gpus="$value" ;;
            esac
            ;;
        --validate-only)
            validate_only=1
            evaluator_args+=("$1")
            shift
            ;;
        --mono-tasks|--mono-tasks=*)
            if [[ "$1" == *=* ]]; then
                mono_tasks="${mono_tasks:+$mono_tasks,}${1#*=}"
            fi
            shift
            while (( $# )) && [[ "$1" != -* ]]; do
                mono_tasks="${mono_tasks:+$mono_tasks,}$1"
                shift
            done
            if [[ -z "$mono_tasks" ]]; then
                echo "--mono-tasks requires at least one task name." >&2
                exit 2
            fi
            ;;
        --mt-dirs|--mt-dirs=*)
            has_mt_dirs=1
            evaluator_args+=("$1")
            shift
            ;;
        --output)
            if (( $# < 2 )) || [[ "$2" == -* ]]; then
                echo "--output requires a file path." >&2
                exit 2
            fi
            translation_output="$2"
            evaluator_args+=("$1" "$2")
            shift 2
            ;;
        --output=*)
            translation_output="${1#*=}"
            if [[ -z "$translation_output" ]]; then
                echo "--output requires a file path." >&2
                exit 2
            fi
            evaluator_args+=("$1")
            shift
            ;;
        *)
            evaluator_args+=("$1")
            shift
            ;;
    esac
done
if [[ ! "$comet_batch_size" =~ ^[1-9][0-9]*$ ]] || [[ ! "$comet_gpus" =~ ^[01]$ ]]; then
    echo "COMET requires --comet-batch-size > 0 and --comet-gpus 0 or 1." >&2
    exit 2
fi
if (( ! has_mt_dirs )); then
    echo "Missing --mt-dirs; provide at least two CODE=NAME values." >&2
    exit 2
fi

PROJECT_DIR="${PROJECT_DIR:-/scratch/project_2008161/zihao/LangAcqBench}"
cd "${PROJECT_DIR}"

module --force purge
module load python-vllm/0.29.0
source env-eval/bin/activate

comet_python="${COMET_PYTHON:-$PROJECT_DIR/env-comet/bin/python}"
if (( comet_enabled && ! validate_only )) && [[ ! -x "$comet_python" ]]; then
    echo "COMET interpreter not found: $comet_python" >&2
    echo "Create the separate env-comet environment using docs/evaluation.md; do not install COMET into env-eval." >&2
    exit 2
fi

case "$MODEL" in
    /*) ;;
    models/*) MODEL="$PROJECT_DIR/$MODEL" ;;
    *) MODEL="$PROJECT_DIR/models/$MODEL" ;;
esac
test -d "$MODEL" || {
    echo "Model directory not found: $MODEL" >&2
    exit 2
}

job_id="${SLURM_JOB_ID:?Run this script inside a Slurm allocation}"
model_name="${MODEL##*/}"
if [[ "$MODEL" == "$PROJECT_DIR"/runs/* ]]; then
    model_run="${MODEL#"$PROJECT_DIR"/runs/}"
    model_run="${model_run%%/*}"
    source_job="${model_run##*-}"
    if [[ "$source_job" =~ ^[0-9]+$ ]]; then
        model_run="${model_run%%-*}-$source_job"
    fi
    model_name="$model_run-$model_name"
fi
model_name="$(printf '%s' "$model_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
RUN_DIR="$PROJECT_DIR/runs/evaluate/${model_name}__job-${job_id}"
mkdir -p "$RUN_DIR"
translation_output="${translation_output:-$RUN_DIR/translation.json}"

# Extra arguments can override these defaults, including --n-shot and --output.
srun python -u "$PROJECT_DIR/scripts/evaluation/evaluate-mt.py" \
    --model "$MODEL" \
    --test-dir "$PROJECT_DIR/data/test" \
    --dev-dir "$PROJECT_DIR/data/dev" \
    --n-shot 3 \
    --output "$RUN_DIR/translation.json" \
    "${evaluator_args[@]}"

if (( validate_only )); then
    exit 0
fi

if (( comet_enabled )); then
    srun "$comet_python" -u "$PROJECT_DIR/scripts/evaluation/evaluate-comet.py" \
        --translation "$translation_output" --model "$comet_model" \
        --batch-size "$comet_batch_size" --gpus "$comet_gpus"
fi

if [[ -n "$mono_tasks" ]]; then
    srun lm_eval \
        --model_args "pretrained=$MODEL,trust_remote_code=True" \
        --device cuda:0 \
        --batch_size 4 \
        --tasks "$mono_tasks" \
        --num_fewshot 0 \
        --output_path "$RUN_DIR/lm-eval.json"
else
    echo "Skipping lm_eval: pass --mono-tasks to run monolingual tasks."
fi

report_args=(--translation "$translation_output" --output "$RUN_DIR/summary.xlsx")
if [[ -n "$mono_tasks" ]]; then
    report_args+=(--lm-eval-dir "$RUN_DIR")
fi
python "$PROJECT_DIR/scripts/evaluation/evaluate-report.py" "${report_args[@]}"
echo "Evaluation results: $RUN_DIR"
