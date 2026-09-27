#!/bin/bash

# Download selected FineWeb-2 language subsets from the Hugging Face Hub.
# Repo: HuggingFaceFW/fineweb-2  (https://huggingface.co/datasets/HuggingFaceFW/fineweb-2)
#
# Usage:
#   ./download_fineweb2.sh                 # download train (+test) for all languages below
#   INCLUDE_REMOVED=1 ./download_fineweb2.sh   # also fetch the large "removed" (dedup) shards
#   LANGS="fra_Latn spa_Latn" ./download_fineweb2.sh   # override the language list
#
# Run this on a node with internet access (e.g. a LUMI login node).

set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
module load python-pytorch/2.13
REPO_ID="HuggingFaceFW/fineweb-2"
DEST_ROOT="/scratch/project_2008161/zihao/LangAcqBench/data/raw"

# Pick whichever HF CLI is available (prefer the modern `hf`).
if command -v hf >/dev/null 2>&1; then
    HF_CLI="hf"
elif command -v huggingface-cli >/dev/null 2>&1; then
    HF_CLI="huggingface-cli"
else
    echo "ERROR: neither 'hf' nor 'huggingface-cli' found on PATH." >&2
    echo "       Activate the venv or 'pip install huggingface_hub[cli]'." >&2
    exit 1
fi

# Cache/tmp on scratch so we never fill up $HOME.
export HF_HOME="${HF_HOME:-/scratch/project_2008161/cache/huggingface}"
# Xet high-performance mode and many workers can use substantial memory.
# Enable high-performance mode explicitly if the node has enough RAM.
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-0}"
# Keep memory usage modest on shared compute nodes; override with WORKERS=N.
WORKERS="${WORKERS:-2}"

# Set INCLUDE_REMOVED=1 to also download the (very large) dedup "removed" shards.
INCLUDE_REMOVED="${INCLUDE_REMOVED:-0}"

# Languages to download (override by exporting LANGS="lang1 lang2 ...").
LANGS="${LANGS:-"
swe_Latn
"}"

# Download one language subset. Uses `hf download` if available, else the
# legacy `huggingface-cli download` syntax.
download_lang() {
    local lang="$1"
    local download_dest="${DEST_ROOT}/${lang}/monolingual"
    local staging_dest="${DEST_ROOT}/.fineweb2-download"

    local includes=("data/${lang}/train/*.parquet" "data/${lang}/test/*.parquet")
    if [ "${INCLUDE_REMOVED}" = "1" ]; then
        includes+=("data/${lang}/removed/*.parquet")
    fi

    echo ">>> [${lang}] downloading FineWeb-2 subset '${lang}' -> ${download_dest}"

    mkdir -p "${download_dest}" "${staging_dest}"

    if [ "${HF_CLI}" = "hf" ]; then
        local args=(download "${REPO_ID}" --repo-type dataset
                    --local-dir "${staging_dest}" --max-workers "${WORKERS}")
        for p in "${includes[@]}"; do args+=(--include "${p}"); done
        if ! hf "${args[@]}"; then
            echo "!!! [${lang}] download failed for subset ${lang}" >&2
            return 1
        fi
    else
        local args=(download "${REPO_ID}" --repo-type dataset
                    --local-dir "${staging_dest}" --local-dir-use-symlinks False)
        for p in "${includes[@]}"; do args+=(--include "${p}"); done
        if ! huggingface-cli "${args[@]}"; then
            echo "!!! [${lang}] download failed for subset ${lang}" >&2
            return 1
        fi
    fi

    # Make sure the subset actually produced files (missing subsets result in
    # "Fetching 0 files" but the CLI still exits 0).
    local source_dir="${staging_dest}/data/${lang}"
    local found=0
    for split in train test; do
        local split_dir="${source_dir}/${split}"
        if [ -d "${split_dir}" ]; then
            while IFS= read -r -d '' file; do
                mv -f "${file}" "${download_dest}/"
                found=1
            done < <(find "${split_dir}" -maxdepth 1 -type f -name '*.parquet' -print0)
        fi
    done
    if [ "${INCLUDE_REMOVED}" = "1" ] && [ -d "${source_dir}/removed" ]; then
        while IFS= read -r -d '' file; do
            mv -f "${file}" "${download_dest}/"
            found=1
        done < <(find "${source_dir}/removed" -maxdepth 1 -type f -name '*.parquet' -print0)
    fi
    if [ "${found}" -eq 0 ]; then
        echo "!!! [${lang}] download produced no parquet files under ${source_dir}" >&2
        return 1
    fi

    rm -rf "${source_dir}"

    return 0
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    mkdir -p "${DEST_ROOT}" "${HF_HOME}"
    echo ">>> Using CLI: ${HF_CLI}"
    echo ">>> Final destination: ${DEST_ROOT}/swe_Latn/monolingual"
    echo ">>> Staging directory: ${DEST_ROOT}/.fineweb2-download"
    echo ">>> INCLUDE_REMOVED=${INCLUDE_REMOVED}  WORKERS=${WORKERS}"

    local total ok=0 fail=0
    # shellcheck disable=SC2086
    set -- ${LANGS}
    total="$#"
    local i=0
    for lang in "$@"; do
        i=$((i + 1))
        echo ">>> ($i/$total) ${lang}"
        if download_lang "${lang}"; then
            ok=$((ok + 1))
        else
            echo "!!! FAILED: ${lang}" >&2
            fail=$((fail + 1))
        fi
    done

    echo "================================================================"
    echo ">>> Done. success=${ok} failed=${fail} total=${total}"
    echo ">>> Data at: ${DEST_ROOT}/swe_Latn/monolingual"
    [ "${fail}" -eq 0 ]
}

main "$@"
