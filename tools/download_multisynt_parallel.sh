#!/usr/bin/env bash

# Download the parallel split of MultiSynt/MT-Nemotron-CC from Hugging Face.
#
# Usage:
#   ./download_multisynt_parallel.sh
#   MODEL=tower72b ./download_multisynt_parallel.sh
#   LANGS="swe_Latn fin_Latn" ./download_multisynt_parallel.sh
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
    local dest="${DEST_ROOT}/${lang}/parallel/${MODEL}"
    local stage="${DEST_ROOT}/.multisynt-download/${MODEL}/${lang}"
    local source="${stage}/data/parallel/${MODEL}/${lang}"
    local include="data/parallel/${MODEL}/${lang}/*.parquet"

    echo ">>> [${lang}] model=${MODEL}; downloading parallel shards to ${dest}"
    mkdir -p "${dest}" "${stage}" "${HF_HOME}"

    if [ "${HF_CLI}" = "hf" ]; then
        hf download "${REPO_ID}" --repo-type dataset \
            --local-dir "${stage}" --max-workers "${WORKERS}" \
            --include "${include}"
    else
        huggingface-cli download "${REPO_ID}" --repo-type dataset \
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
        echo "ERROR: no parallel parquet shards found for ${MODEL}/${lang}." >&2
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
    echo ">>> Model: ${MODEL}"
    echo ">>> Languages: ${LANGS}"
    echo ">>> CLI: ${HF_CLI}; workers=${WORKERS}; Xet high-performance=${HF_XET_HIGH_PERFORMANCE}"

    local lang
    for lang in ${LANGS}; do
        download_lang "${lang}"
    done
}

main "$@"
