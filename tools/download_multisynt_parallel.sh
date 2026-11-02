#!/usr/bin/env bash

# Download the parallel split of MultiSynt/MT-Nemotron-CC from Hugging Face.
# tur_Latn uses Helsinki-NLP/nemotron-cc-translated (tur/*.parquet) instead.
# Preserve source columns: Turkish has no tokens column. Token counts must be
# computed from text during preprocessing with the chosen tokenizer.
#
# Usage:
#   ./download_multisynt_parallel.sh
#   MODEL=tower72b ./download_multisynt_parallel.sh
#   LANGS="swe_Latn fin_Latn" ./download_multisynt_parallel.sh
#   LANGS="tur_Latn" ./download_multisynt_parallel.sh
#   WORKERS=1 ./download_multisynt_parallel.sh

set -euo pipefail

module load python-pytorch/2.13

REPO_ID="MultiSynt/MT-Nemotron-CC"
DEST_ROOT="${DEST_ROOT:-/scratch/project_2008161/zihao/LangAcqBench/data/raw}"
MODEL="${MODEL:-tower9b}"
LANGS="${LANGS:-swe_Latn}"
WORKERS="${WORKERS:-1}"

case "${MODEL}" in
    tower9b|tower72b) ;;
    *) echo "ERROR: MODEL must be tower9b or tower72b (got '${MODEL}')." >&2; exit 1 ;;
esac

# Limit Xet's memory use on shared compute nodes. Can be overridden by the user.
export HF_HOME="${HF_HOME:-/scratch/project_2008161/cache/huggingface}"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-0}"

if command -v hf >/dev/null 2>&1; then
    HF_CLI="hf"
elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_CLI="huggingface-cli"
else
    echo "ERROR: neither 'hf' nor 'huggingface-cli' found on PATH." >&2
    echo "       Activate the venv or install huggingface_hub[cli]." >&2
    exit 1
fi

download_lang() {
    local lang="$1"
    local repo_id="${REPO_ID}"
    local model_path="${MODEL}/${lang}"
    local dest="${DEST_ROOT}/${lang}/parallel/${MODEL}"
    local stage="${DEST_ROOT}/.multisynt-download/${MODEL}/${lang}"
    local remote_dir="data/parallel/${model_path}"
    if [ "${lang}" = "eng_Latn" ]; then
        # English is the shared source side of the parallel corpus and is not
        # stored under a translation-model directory in the HF repository.
        remote_dir="data/parallel/${lang}"
        dest="${DEST_ROOT}/${lang}/parallel"
    elif [ "${lang}" = "tur_Latn" ]; then
        # Turkish is unavailable in MultiSynt. This source is independent of
        # MODEL and must not be labelled as a Tower translation.
        repo_id="Helsinki-NLP/nemotron-cc-translated"
        remote_dir="tur"
        dest="${DEST_ROOT}/${lang}/parallel"
        stage="${DEST_ROOT}/.multisynt-download/helsinki-nlp-nemotron-cc-translated/${lang}"
    fi
    local source="${stage}/${remote_dir}"
    local include="${remote_dir}/*.parquet"

    echo ">>> [${lang}] source=${repo_id}/${remote_dir}; downloading parallel shards to ${dest}"
    if [ "${lang}" = "tur_Latn" ]; then
        echo ">>> [${lang}] MODEL does not apply; source has no tokens column (count tokens from text during preprocessing)."
    fi
    mkdir -p "${dest}" "${stage}" "${HF_HOME}"

    if [ "${HF_CLI}" = "hf" ]; then
        hf download "${repo_id}" --repo-type dataset \
            --local-dir "${stage}" --max-workers "${WORKERS}" \
            --include "${include}"
    else
        huggingface-cli download "${repo_id}" --repo-type dataset \
            --local-dir "${stage}" --local-dir-use-symlinks False \
            --include "${include}"
    fi

    local moved=0
    if [ -d "${source}" ]; then
        while IFS= read -r -d '' file; do
            mv -f "${file}" "${dest}/"
            moved=$((moved + 1))
        done < <(find "${source}" -maxdepth 1 -type f -name '*.parquet' -print0)
    fi
    if [ "${moved}" -eq 0 ] && [ -z "$(find "${dest}" -maxdepth 1 -type f -name '*.parquet' -print -quit)" ]; then
        echo "ERROR: no parallel parquet shards found for ${lang} in ${repo_id}/${remote_dir}." >&2
        return 1
    fi

    if [ -d "${source}" ]; then
        rm -rf "${source}"
    fi
    local count
    count="$(find "${dest}" -maxdepth 1 -type f -name '*.parquet' | wc -l)"
    echo ">>> [${lang}] ${count} parquet shard(s) present in ${dest}"
}

main() {
    echo ">>> Dataset: ${REPO_ID} (parallel split)"
    echo ">>> Turkish fallback: Helsinki-NLP/nemotron-cc-translated (tur/*.parquet)"
    echo ">>> MultiSynt translation model: ${MODEL}"
    echo ">>> Languages: ${LANGS}"
    echo ">>> CLI: ${HF_CLI}; workers=${WORKERS}; Xet high-performance=${HF_XET_HIGH_PERFORMANCE}"

    local lang
    for lang in ${LANGS}; do
        download_lang "${lang}"
    done
}

main "$@"
