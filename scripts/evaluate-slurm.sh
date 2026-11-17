#!/bin/bash
#SBATCH --job-name=eval
#SBATCH --error=runs/evaluate/logs/%x_%j.err
#SBATCH --output=runs/evaluate/logs/%x_%j.out
#SBATCH --account=project_2001403
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=0-00:15:00

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sbatch [SBATCH_OPTIONS] scripts/evaluate-slurm.sh MODEL \
         --mt-dirs CODE=NAME CODE=NAME [--mono-tasks TASK [TASK ...]] \
         [EVALUATOR_OPTIONS]

Submit translation evaluation with this cluster's Slurm resource defaults.
Run from the repository root; create runs/evaluate/logs before submitting.

  MODEL              Directory under models/, models/NAME, or an absolute path.
  --mt-dirs          Required language code/name pairs; supply at least two.
  --mono-tasks       Optional lm_eval tasks, separated by spaces or commas.
  --no-comet         Skip COMET scoring (enabled by default: Unbabel/wmt22-comet-da).
  EVALUATOR_OPTIONS  See scripts/evaluate.sh --help (e.g. --n-shot 3, --comet-model PATH).
  SBATCH_OPTIONS     Override local resource defaults, such as --time or --partition.

Results go to runs/evaluate/MODEL__job-JOB_ID/ as translation.json,
lm-eval_*.json (when requested), and summary.xlsx. Slurm logs go to
runs/evaluate/logs/.
COMET uses env-comet/bin/python; see docs/evaluation.md for separate environment setup.

Examples:
  sbatch scripts/evaluate-slurm.sh SmolLM3-3B \
    --mt-dirs eng_Latn=English swe_Latn=Swedish --n-shot 3

  sbatch scripts/evaluate-slurm.sh SmolLM3-3B \
    --mt-dirs eng_Latn=English swe_Latn=Swedish --n-shot 3 --no-comet

  sbatch scripts/evaluate-slurm.sh SmolLM3-3B \
    --mt-dirs eng_Latn=English swe_Latn=Swedish --n-shot 3 \
    --mono-tasks belebele_swe_Latn multiblimp_swe global_piqa_nonparallel_cloze_swe_latn global_piqa_nonparallel_generation_swe_latn global_piqa_parallel_cloze_swe_latn global_piqa_parallel_generation_swe_latn

Show this help without submitting a job: bash scripts/evaluate-slurm.sh --help
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
PROJECT_DIR="${PROJECT_DIR:-/scratch/project_2008161/zihao/LangAcqBench}"
exec bash "$PROJECT_DIR/scripts/evaluate.sh" "$@"
