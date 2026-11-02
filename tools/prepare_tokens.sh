#!/usr/bin/env bash
#SBATCH --job-name=language-token-prep
#SBATCH --error=../logs/data_prep/%x_%j.err
#SBATCH --output=../logs/data_prep/%x_%j.out
#SBATCH --account=project_2008161
#SBATCH --partition=small
#SBATCH --time=1-00:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G

set -euo pipefail

# One language: LANGUAGE=tur_Latn sbatch tools/prepare_tokens.sh
# Several: LANGS="fin_Latn ukr_Cyrl" sbatch tools/prepare_tokens.sh
# Each language receives its own TOTAL_TOKENS budget and output directory.
PROJECT_DIR="${PROJECT_DIR:-/scratch/project_2008161/zihao/LangAcqBench}"
RAW_ROOT="${RAW_ROOT:-${PROJECT_DIR}/data/raw}"
LANGS="${LANGS:-${LANGUAGE:-swe_Latn}}"
PARALLEL_LANGUAGE="${PARALLEL_LANGUAGE:-${ENG_LANGUAGE:-eng_Latn}}"
MONO_FORMAT="${MONO_FORMAT:-auto}"
TOTAL_TOKENS="${TOTAL_TOKENS:-50000000}"
MONO_PERCENT="${MONO_PERCENT:-60}"
PARALLEL_PERCENT="${PARALLEL_PERCENT:-40}"
TOKENIZER_WORKERS="${TOKENIZER_WORKERS:-${SLURM_CPUS_PER_TASK:-8}}"
TOKENIZE_BATCH_SIZE="${TOKENIZE_BATCH_SIZE:-256}"
ALIGNMENT_BATCH_SIZE="${ALIGNMENT_BATCH_SIZE:-50000}"

cd "${PROJECT_DIR}"

module --force purge
module load python-pytorch/2.13
source env-cpu/bin/activate

args=(
    --raw-root "${RAW_ROOT}"
    --parallel-language "${PARALLEL_LANGUAGE}"
    --mono-format "${MONO_FORMAT}"
    --total-tokens "${TOTAL_TOKENS}"
    --mono-percent "${MONO_PERCENT}"
    --parallel-percent "${PARALLEL_PERCENT}"
    --workers "${TOKENIZER_WORKERS}"
    --tokenize-batch-size "${TOKENIZE_BATCH_SIZE}"
    --alignment-batch-size "${ALIGNMENT_BATCH_SIZE}"
    --overwrite
)
if [[ -n "${PARALLEL_MODEL:-}" ]]; then
    args+=(--parallel-model "${PARALLEL_MODEL}")
fi

read -r -a languages <<< "${LANGS//[$'\n\r\t']/ }"
for language in "${languages[@]}"; do
    echo ">>> Preparing ${language} with partner ${PARALLEL_LANGUAGE}"
    python tools/prepare_tokens.py --language "${language}" "${args[@]}" "$@"
done
