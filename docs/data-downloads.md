# Parallel data downloads

Run from the repository root:

```bash
LANGS="tur_Latn" bash tools/download_multisynt_parallel.sh
# Mixing sources in one invocation is also supported:
LANGS="swe_Latn tur_Latn eng_Latn" bash tools/download_multisynt_parallel.sh
```

The script requires the cluster's `python-pytorch/2.13` module and either `hf`
or `huggingface-cli`. `DEST_ROOT`, `WORKERS`, and `HF_HOME` can be overridden
through environment variables.

| Language | Source | Directory under `DEST_ROOT` |
| --- | --- | --- |
| `tur_Latn` | [Helsinki-NLP/nemotron-cc-translated, `tur/`](https://huggingface.co/datasets/Helsinki-NLP/nemotron-cc-translated/tree/main/tur) | `tur_Latn/parallel/` |
| `eng_Latn` | [MultiSynt/MT-Nemotron-CC](https://huggingface.co/datasets/MultiSynt/MT-Nemotron-CC), `data/parallel/eng_Latn/` | `eng_Latn/parallel/` |
| Other languages | MultiSynt, `data/parallel/${MODEL}/${LANG}/` | `${LANG}/parallel/${MODEL}/` |

`MODEL=tower9b` (default) or `MODEL=tower72b` selects the MultiSynt translation
model. It does not affect Turkish or English. The default `DEST_ROOT` is
`/scratch/project_2008161/zihao/LangAcqBench/data/raw`.

The Turkish source schema, checked through the Hugging Face dataset metadata,
contains `warc_record_id`, `text`, `language`, and `url`; it has no `tokens`
column. Downloads preserve the original Parquet files. Compute token counts
from `text` with the tokenizer used for the desired quota; missing counts must
not be treated as zero. `tools/prepare_tokens.py` already computes counts
with `o200k_base` instead of reading a source `tokens` column.

For bilingual preparation, match documents by `warc_record_id` and check ID
overlap before combining sources. The Helsinki dataset also provides an
[`eng/` directory](https://huggingface.co/datasets/Helsinki-NLP/nemotron-cc-translated/tree/main/eng)
for its English source documents; `LANGS="eng_Latn"` in this script selects
MultiSynt's English data.
