#!/usr/bin/env bash

# Download HPLT Monolingual Dataset 3.0 language shards.
# Data is Zstandard-compressed JSONL (.jsonl.zst).
#
# Usage:
#   ./download_hplt3.sh
#   LANGS="swe_Latn nob_Latn" ./download_hplt3.sh
#   DEST_ROOT=/path/to/data/raw ./download_hplt3.sh

set -euo pipefail

BASE_URL="https://data.hplt-project.org/three/sorted"
DEST_ROOT="${DEST_ROOT:-/scratch/project_2008161/zihao/LangAcqBench/data/raw}"
LANGS="${LANGS:-swe_Latn}"

if ! command -v wget >/dev/null 2>&1; then
    echo "ERROR: wget is required but was not found on PATH." >&2
    exit 1
fi

download_lang() {
    local lang="$1"
    local dest="${DEST_ROOT}/${lang}/monolingual"
    local map_file
    map_file="$(mktemp "${TMPDIR:-/tmp}/hplt3-${lang}.XXXXXX.map")"
    trap 'rm -f "${map_file}"' RETURN

    mkdir -p "${dest}"
    echo ">>> [${lang}] fetching shard map"
    if ! wget --quiet --show-progress -O "${map_file}" "${BASE_URL}/${lang}.map"; then
        echo "ERROR: could not fetch map for ${lang}; check that this language is in HPLT 3.0." >&2
        return 1
    fi
    if [ ! -s "${map_file}" ]; then
        echo "ERROR: HPLT returned an empty shard map for ${lang}." >&2
        return 1
    fi

    local shard_count
    shard_count="$(wc -l < "${map_file}")"
    echo ">>> [${lang}] downloading ${shard_count} shard(s) into ${dest}"
    # The map contains URLs under /three/sorted/<lang>/. Strip those three
    # path components so only the shard filenames land in the monolingual dir.
    wget --continue --tries=0 --timeout=60 --waitretry=5 \
        --no-host-directories --cut-dirs=3 \
        --directory-prefix="${dest}" --input-file="${map_file}"

    local downloaded
    downloaded="$(find "${dest}" -maxdepth 1 -type f -name '*.jsonl.zst' | wc -l)"
    if [ "${downloaded}" -eq 0 ]; then
        echo "ERROR: no .jsonl.zst shards found in ${dest}" >&2
        return 1
    fi
    echo ">>> [${lang}] found ${downloaded} .jsonl.zst shard(s) in ${dest}"
}

main() {
    mkdir -p "${DEST_ROOT}"
    echo ">>> HPLT dataset: v3.0 monolingual"
    echo ">>> Destination root: ${DEST_ROOT}"
    echo ">>> Languages: ${LANGS}"

    # LANGS is a whitespace-separated list, e.g. "swe_Latn nob_Latn".
    local lang
    for lang in ${LANGS}; do
        download_lang "${lang}"
    done
}

main "$@"
