#!/usr/bin/env python3
"""Select mono/parallel data for a configurable language within o200k token budgets.

Parallel quota accounting uses the sum of both language sides. Whole documents
and aligned pairs are retained, so actual counts can fall below the budgets.
"""

import argparse
from contextlib import closing
import io
import json
import os
import sys
import time
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
import tiktoken
import zstandard as zstd


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--raw-root", type=Path, default=Path("/scratch/project_2008161/zihao/LangAcqBench/data/raw"))
    p.add_argument("--output-dir", type=Path, default=None)
    p.add_argument("--total-tokens", type=int, default=50_000_000,
                    help="Total tokens; parallel budget counts both language sides.")
    p.add_argument("--mono-percent", type=float, default=60)
    p.add_argument("--parallel-percent", type=float, default=40)
    p.add_argument("--language", default="swe_Latn", help="Target language directory, e.g. tur_Latn.")
    p.add_argument("--parallel-language", "--eng-language", dest="parallel_language", default="eng_Latn",
                   help="Partner language directory (--eng-language is a compatibility alias).")
    p.add_argument("--parallel-model", choices=("tower9b", "tower72b"),
                   help="Select a nested Tower directory; flat parallel directories are also supported.")
    p.add_argument("--mono-format", choices=("auto", "jsonl.zst", "parquet"), default="auto",
                   help="Monolingual shard format; auto requires only one format to be present.")
    p.add_argument("--id-column", default="warc_record_id",
                   help="Alignment ID column in parallel Parquet files.")
    p.add_argument("--text-column", default="text", help="Text column in each parallel parquet.")
    p.add_argument("--progress-seconds", type=float, default=10,
                   help="Seconds between progress messages (0 disables periodic messages).")
    p.add_argument("--workers", type=int, default=int(os.environ.get("SLURM_CPUS_PER_TASK", "1")),
                   help="Parallel tokenizer workers; defaults to CPUs allocated by Slurm.")
    p.add_argument("--tokenize-batch-size", type=int, default=256,
                   help="Texts submitted per tokenizer batch.")
    p.add_argument("--alignment-batch-size", type=int, default=50_000,
                   help="Target rows per in-memory alignment batch; no full partner database is built.")
    p.add_argument("--overwrite", action="store_true", help="Replace existing output files.")
    return p.parse_args()


def text_from_json(obj):
    if isinstance(obj, dict):
        for key in ("text", "content", "document"):
            if isinstance(obj.get(key), str):
                return obj[key]
    raise ValueError("Could not find a string text field in a monolingual JSON record")


def mono_input_files(directory, file_format):
    formats = {ext: sorted(directory.glob(f"*.{ext}")) for ext in ("jsonl.zst", "parquet")}
    if file_format != "auto":
        return formats[file_format]
    populated = [files for files in formats.values() if files]
    if len(populated) > 1:
        raise ValueError(f"{directory}: both JSONL.zst and Parquet found; select --mono-format to avoid mixing corpora")
    return populated[0] if populated else []


def parallel_input_files(directory, model):
    flat = sorted(directory.glob("*.parquet"))
    if model:
        nested = sorted((directory / model).glob("*.parquet"))
        return nested or flat
    if flat:
        return flat
    variants = [files for path in sorted(directory.glob("tower*"))
                if path.is_dir() and (files := sorted(path.glob("*.parquet")))]
    if len(variants) > 1:
        raise ValueError(f"{directory}: multiple Tower directories found; select --parallel-model")
    return variants[0] if variants else []


def mono_records(files, progress_seconds):
    dctx = zstd.ZstdDecompressor()
    started = time.monotonic()
    next_report = started + progress_seconds if progress_seconds > 0 else float("inf")
    rows = 0
    for filename in files:
        print(f"[mono] reading {filename}", flush=True)
        if Path(filename).suffix == ".parquet":
            pf = pq.ParquetFile(filename)
            if "text" not in pf.schema_arrow.names:
                raise ValueError(f"{filename}: expected monolingual column 'text'; found {pf.schema_arrow.names}")
            columns = ["text"] + (["id"] if "id" in pf.schema_arrow.names else [])
            file_row = 0
            for batch in pf.iter_batches(columns=columns, batch_size=8192):
                for row in batch.to_pylist():
                    file_row += 1
                    if not isinstance(row["text"], str) or not row["text"].strip():
                        continue
                    rows += 1
                    now = time.monotonic()
                    if now >= next_report:
                        print(f"[mono] read_rows={rows:,} elapsed={now - started:.0f}s", flush=True)
                        next_report = now + progress_seconds
                    row_id = row.get("id")
                    yield row_id if row_id is not None else f"{Path(filename).name}:{file_row}", row["text"]
            continue
        with open(filename, "rb") as raw, dctx.stream_reader(raw) as reader:
            # Read lines from decompressed stream without loading an entire shard.
            for line_no, line in enumerate(io.BufferedReader(reader), 1):
                if not line.strip():
                    continue
                obj = json.loads(line)
                txt = text_from_json(obj)
                if not txt.strip():
                    continue
                rows += 1
                now = time.monotonic()
                if now >= next_report:
                    print(f"[mono] read_rows={rows:,} elapsed={now - started:.0f}s", flush=True)
                    next_report = now + progress_seconds
                yield obj.get("id", f"{Path(filename).name}:{line_no}"), txt
    print(f"[mono] input exhausted: rows={rows:,} elapsed={time.monotonic() - started:.0f}s", flush=True)


def parquet_rows(files, id_col, text_col, stage, progress_seconds):
    started = time.monotonic()
    next_report = started + progress_seconds if progress_seconds > 0 else float("inf")
    rows = 0
    for filename in files:
        print(f"[{stage}] reading {filename}", flush=True)
        pf = pq.ParquetFile(filename)
        names = pf.schema_arrow.names
        if id_col not in names or text_col not in names:
            raise ValueError(f"{filename}: expected columns {id_col!r} and {text_col!r}; found {names}")
        for batch in pf.iter_batches(columns=[id_col, text_col], batch_size=8192):
            for row_id, text in zip(batch.column(0).to_pylist(), batch.column(1).to_pylist()):
                if row_id is not None and isinstance(text, str) and text.strip():
                    rows += 1
                    yield str(row_id), text
            now = time.monotonic()
            if now >= next_report:
                print(f"[{stage}] rows={rows:,} elapsed={now - started:.0f}s", flush=True)
                next_report = now + progress_seconds
    print(f"[{stage}] input exhausted: rows={rows:,} elapsed={time.monotonic() - started:.0f}s", flush=True)


def batches(items, batch_size):
    batch = []
    for item in items:
        batch.append(item)
        if len(batch) >= batch_size:
            yield batch
            batch = []
    if batch:
        yield batch


def aligned_rows(language_files, partner_files, id_column, text_column,
                 progress_seconds, batch_size):
    """Join bounded target batches in source order without storing the partner corpus.

    Each batch streams the partner shards until every requested ID is found or
    the source is exhausted. Duplicate partner IDs keep their first occurrence.
    Later target batches are read only if the consumer still needs more tokens.
    """
    targets = parquet_rows(language_files, id_column, text_column, "parallel-target", progress_seconds)
    with closing(targets):
        for batch_number, target_batch in enumerate(batches(targets, batch_size), 1):
            pending = {row_id for row_id, _ in target_batch}
            matches = {}
            print(f"[alignment] batch={batch_number} target_rows={len(target_batch):,} "
                  f"unique_ids={len(pending):,}; streaming partner", flush=True)
            with closing(parquet_rows(partner_files, id_column, text_column,
                                      "parallel-partner", progress_seconds)) as partners:
                for row_id, text in partners:
                    if row_id in pending:
                        matches[row_id] = text
                        pending.remove(row_id)
                        if not pending:
                            break
            print(f"[alignment] batch={batch_number} matched_ids={len(matches):,} "
                  f"unmatched_ids={len(pending):,}", flush=True)
            for row_id, text in target_batch:
                if row_id in matches:
                    yield row_id, text, matches[row_id]


def main():
    a = parse_args()
    if a.total_tokens <= 0 or a.mono_percent < 0 or a.parallel_percent < 0:
        raise SystemExit("total tokens must be positive and percentages non-negative")
    if a.workers < 1 or a.tokenize_batch_size < 1 or a.alignment_batch_size < 1:
        raise SystemExit("workers, tokenize-batch-size and alignment-batch-size must be positive")
    if abs(a.mono_percent + a.parallel_percent - 100) > 1e-8:
        raise SystemExit("mono-percent + parallel-percent must equal 100")
    if a.language == a.parallel_language:
        raise SystemExit("language and parallel-language must be different")
    mono_target = int(a.total_tokens * a.mono_percent / 100)
    parallel_target = a.total_tokens - mono_target
    raw = a.raw_root
    out = a.output_dir or raw.parent / "train" / a.language
    mono_out = out / "monolingual.parquet"
    parallel_out = out / "parallel.parquet"
    if not a.overwrite and (mono_out.exists() or parallel_out.exists()):
        raise SystemExit(f"Output exists; use --overwrite: {mono_out}, {parallel_out}")

    try:
        mono_files = mono_input_files(raw / a.language / "monolingual", a.mono_format) if mono_target else []
        language_files = parallel_input_files(raw / a.language / "parallel", a.parallel_model) if parallel_target else []
        partner_files = parallel_input_files(raw / a.parallel_language / "parallel", a.parallel_model) if parallel_target else []
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    if ((mono_target and not mono_files) or
            (parallel_target and (not language_files or not partner_files))):
        raise SystemExit(f"Missing inputs under {raw}: {a.language} mono={len(mono_files)}, "
                         f"{a.language} parallel={len(language_files)}, "
                         f"{a.parallel_language} parallel={len(partner_files)}")
    out.mkdir(parents=True, exist_ok=True)

    enc = tiktoken.get_encoding("o200k_base")
    print(f"[tokenizer] o200k_base; workers={a.workers}; batch_size={a.tokenize_batch_size}", flush=True)
    print(f"[languages] target={a.language}; partner={a.parallel_language}", flush=True)
    counters = {"mono_tokens": 0, "mono_rows": 0, "parallel_language_tokens": 0,
                "parallel_partner_tokens": 0, "parallel_rows": 0}

    mono_schema = pa.schema([("id", pa.string()), ("text", pa.string()), ("num_tokens", pa.int64())])
    mono_writer = pq.ParquetWriter(mono_out, mono_schema, compression="zstd")
    mono_batch = []
    try:
        print(f"[mono] target={mono_target:,} tokens", flush=True)
        mono_done = False
        for input_batch in batches(mono_records(mono_files, a.progress_seconds), a.tokenize_batch_size):
            token_ids = enc.encode_ordinary_batch([text for _, text in input_batch], num_threads=a.workers)
            for (row_id, text), ids in zip(input_batch, token_ids):
                n = len(ids)
                if counters["mono_tokens"] + n > mono_target:
                    mono_done = True
                    break
                mono_batch.append({"id": str(row_id), "text": text, "num_tokens": n})
                counters["mono_tokens"] += n
                counters["mono_rows"] += 1
                if counters["mono_rows"] % 100_000 == 0:
                    print(f"[mono] selected rows={counters['mono_rows']:,} tokens={counters['mono_tokens']:,}/{mono_target:,}", flush=True)
                if len(mono_batch) >= 4096:
                    mono_writer.write_table(pa.Table.from_pylist(mono_batch, schema=mono_schema))
                    mono_batch.clear()
            if mono_done:
                break
        if mono_batch:
            mono_writer.write_table(pa.Table.from_pylist(mono_batch, schema=mono_schema))
    finally:
        mono_writer.close()

    parallel_schema = pa.schema([
        ("id", pa.string()), (f"{a.language}_text", pa.string()),
        (f"{a.parallel_language}_text", pa.string()), (f"{a.language}_tokens", pa.int64()),
        (f"{a.parallel_language}_tokens", pa.int64()),
    ])
    parallel_writer = pq.ParquetWriter(parallel_out, parallel_schema, compression="zstd")
    parallel_batch = []
    paired_rows = aligned_rows(language_files, partner_files, a.id_column, a.text_column,
                               a.progress_seconds, a.alignment_batch_size)
    try:
        print(f"[parallel] target={parallel_target:,} combined {a.language}+{a.parallel_language} tokens", flush=True)
        parallel_done = False
        for input_batch in batches(paired_rows, a.tokenize_batch_size):
            all_texts = [text for _, language_text, partner_text in input_batch for text in (language_text, partner_text)]
            token_ids = enc.encode_ordinary_batch(all_texts, num_threads=a.workers)
            for i, (row_id, language_text, partner_text) in enumerate(input_batch):
                language_n = len(token_ids[2 * i])
                partner_n = len(token_ids[2 * i + 1])
                if (counters["parallel_language_tokens"] + counters["parallel_partner_tokens"]
                        + language_n + partner_n > parallel_target):
                    parallel_done = True
                    break
                parallel_batch.append({"id": row_id, f"{a.language}_text": language_text,
                    f"{a.parallel_language}_text": partner_text, f"{a.language}_tokens": language_n,
                    f"{a.parallel_language}_tokens": partner_n})
                counters["parallel_language_tokens"] += language_n
                counters["parallel_partner_tokens"] += partner_n
                counters["parallel_rows"] += 1
                if counters["parallel_rows"] % 100_000 == 0:
                    done = counters["parallel_language_tokens"] + counters["parallel_partner_tokens"]
                    print(f"[parallel] selected rows={counters['parallel_rows']:,} tokens={done:,}/{parallel_target:,}", flush=True)
                if len(parallel_batch) >= 4096:
                    parallel_writer.write_table(pa.Table.from_pylist(parallel_batch, schema=parallel_schema))
                    parallel_batch.clear()
            if parallel_done:
                break
        if parallel_batch:
            parallel_writer.write_table(pa.Table.from_pylist(parallel_batch, schema=parallel_schema))
    finally:
        paired_rows.close()
        parallel_writer.close()

    print(json.dumps({"tokenizer": "o200k_base", "language": a.language,
        "parallel_language": a.parallel_language, "total_target_tokens": a.total_tokens,
        "requested_mono_tokens": mono_target, "requested_parallel_bilingual_tokens": parallel_target,
        **counters, "outputs": [str(mono_out), str(parallel_out)]}, ensure_ascii=False, indent=2))
    parallel_actual = counters["parallel_language_tokens"] + counters["parallel_partner_tokens"]
    if counters["mono_tokens"] < mono_target or parallel_actual < parallel_target:
        print("WARNING: one or more budgets were not reached (whole-record boundary or insufficient aligned data)", file=sys.stderr)


if __name__ == "__main__":
    main()
