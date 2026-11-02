# Token-budgeted data preparation

The scripts `tools/prepare_tokens.py` and
`tools/prepare_tokens.sh` support any language with the following local
layout, including `fin_Latn`, `tur_Latn`, and `ukr_Cyrl`:

```text
data/raw/<language>/monolingual/*.jsonl.zst  # HPLT
# or: data/raw/<language>/monolingual/*.parquet  # FineWeb-2
data/raw/<language>/parallel/*.parquet
# or: data/raw/<language>/parallel/tower9b/*.parquet
data/raw/eng_Latn/parallel/*.parquet
```

Run the Python script in an environment with `pyarrow`, `tiktoken`, and
`zstandard`. For example:

```bash
python tools/prepare_tokens.py --language tur_Latn
python tools/prepare_tokens.py --language fin_Latn --parallel-model tower9b
python tools/prepare_tokens.py --language ukr_Cyrl --output-dir /path/to/output
```

Outputs default to `data/train/<language>/monolingual.parquet` and
`parallel.parquet`. Existing outputs require `--overwrite`. Monolingual output
contains `id`, `text`, and `num_tokens`; parallel output contains `id`,
`<language>_text`, `<partner>_text`, `<language>_tokens`, and `<partner>_tokens`.

The default remains Swedish with a 50 million token budget split 60% monolingual
and 40% parallel. Counts use `o200k_base` on text, including sources without a
token-count column. The parallel budget includes **both** sides. Documents and
aligned pairs are kept whole, in sorted shard and source row order; selection
stops at the first record exceeding each budget. Actual counts may therefore
fall below the requested budget. The final JSON reports actual counts using
`parallel_language_tokens` and `parallel_partner_tokens`, together with the
language codes.

Monolingual JSON accepts `text`, `content`, or `document`; Parquet requires
`text` and uses `id` if available, otherwise a shard/row ID. Automatic format
selection rejects directories containing both JSONL.zst and Parquet; choose
`--mono-format jsonl.zst` or `--mono-format parquet` explicitly in that case.

Parallel files require `warc_record_id` and `text` (override with `--id-column`
and `--text-column`). Pairs are joined by ID rather than row position; unmatched
IDs are skipped. Sources must share alignment IDs. `--parallel-language`
selects the partner, defaulting to `eng_Latn`; `--eng-language` remains an alias.
Flat parallel shards take precedence in automatic discovery; a single populated
Tower directory is discovered if no flat shards exist. With multiple Tower
directories, select `--parallel-model tower9b` or `tower72b`. An explicit model
uses that directory if populated, otherwise flat shards, so Turkish and English
can use their flat layout alongside Tower translations.

Alignment holds at most `--alignment-batch-size` target records (default 50,000)
and their matching partner texts in memory. It streams partner Parquet shards
for each batch, stops scanning when all requested IDs are found, and preserves
target order. It does not copy the full English corpus into a temporary SQLite
database. Reduce the batch size for lower memory use; smaller batches or missing
IDs can require repeated partner scans and increase runtime.

A 100/0 or 0/100 percentage split does not require files for the unused component;
both output files are still created, with the unused one empty.

The Slurm wrapper loads `python-pytorch/2.13` and activates `env-cpu`. Its Slurm
log paths are relative to the submission directory. From the repository root:

```bash
mkdir -p logs/data_prep
(cd tools && LANGUAGE=tur_Latn sbatch prepare_tokens.sh)
(cd tools && LANGS="fin_Latn ukr_Cyrl" sbatch prepare_tokens.sh)
(cd tools && LANGS="swe_Latn fin_Latn" PARALLEL_MODEL=tower9b sbatch prepare_tokens.sh)
```

`LANGS` takes precedence over `LANGUAGE`; if neither is set, Swedish is used.
Languages run sequentially, each with its own `TOTAL_TOKENS` budget and output
directory. Other environment options are `RAW_ROOT`, `PROJECT_DIR`,
`PARALLEL_LANGUAGE` (or legacy `ENG_LANGUAGE`), `MONO_FORMAT`, `TOTAL_TOKENS`,
`MONO_PERCENT`, `PARALLEL_PERCENT`, `TOKENIZER_WORKERS`, and `TOKENIZE_BATCH_SIZE`.
`ALIGNMENT_BATCH_SIZE` sets the in-memory alignment batch size.
Extra Python options may be passed after the shell script name. As before, the
wrapper passes `--overwrite`, replacing existing outputs for selected languages.
Adjust Slurm time/resources for large inputs or multiple languages.

Small fixture checks, with real Parquet I/O and mocked tokenizer/decompression:

```bash
python -m unittest discover -s tests -p 'test_prepare_tokens.py' -v
bash -n tools/prepare_tokens.sh
```

## Diagnosing earlier preparation failures

On November 2, jobs `2740918` (Icelandic), `2740919` (Dutch), `2740920`
(Turkish), and `2740922` (Ukrainian) failed with
`sqlite3.OperationalError: database or disk is full` while building the old
full-English lookup. They had not reached output generation. The English input
has 140,359,346 rows in 16 shards (124.8 GiB compressed Parquet; 321.3 GiB
uncompressed row groups). The new streaming alignment avoids that temporary
database. The logs do not identify the exact temporary filesystem that filled.

Finnish job `2740911` completed with exit code 0 and both output files. Its
warning describes whole-record budget rounding: 29,999,927 monolingual tokens
and 19,998,647 combined parallel tokens, totaling 49,998,574. This warning does
not indicate a failed job.
