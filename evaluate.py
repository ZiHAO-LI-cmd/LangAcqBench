#!/usr/bin/env python3
"""Evaluate local causal-LM translations with FLORES200 BLEU and chrF++."""
import argparse
from datetime import datetime, timezone
import hashlib
import itertools
import json
import random
from pathlib import Path
import sys


def positive_int(value):
    value = int(value)
    if value <= 0:
        raise argparse.ArgumentTypeError('must be positive')
    return value


def nonnegative_int(value):
    value = int(value)
    if value < 0:
        raise argparse.ArgumentTypeError('must be nonnegative')
    return value


def memory_fraction(value):
    value = float(value)
    if not 0 < value <= 1:
        raise argparse.ArgumentTypeError('must be in (0, 1]')
    return value


def language_map(items):
    result = {}
    for item in items:
        code, sep, name = item.partition('=')
        if not sep or not name.strip() or not code or Path(code).name != code or code in ('.', '..'):
            raise ValueError('Languages must be CODE=NAME, using the Parquet filename stem')
        if code in result:
            raise ValueError(f'Duplicate language code: {code}')
        result[code] = name.strip()
    if len(result) < 2:
        raise ValueError('At least two languages are required')
    return result


def read_records(path, text_column, id_column, language):
    import pyarrow.parquet as pq
    table = pq.read_table(path)
    if text_column not in table.column_names:
        raise ValueError(f'{path}: missing text column {text_column}')
    texts = table[text_column].to_pylist()
    if not texts or any(not isinstance(t, str) or not t.strip() for t in texts):
        raise ValueError(f'{path}: empty dataset or null/empty/non-string text')
    if 'lang' in table.column_names and set(table['lang'].to_pylist()) != {language}:
        raise ValueError(f'{path}: lang values do not match filename code {language}')
    if id_column:
        if id_column not in table.column_names:
            raise ValueError(f'{path}: missing ID column {id_column}')
        ids = table[id_column].to_pylist()
        if any(i is None or isinstance(i, bool) or not isinstance(i, (str, int)) for i in ids):
            raise ValueError(f'{path}: IDs must be non-null strings or integers')
        if len(set(ids)) != len(ids):
            raise ValueError(f'{path}: duplicate IDs')
    else:
        ids = None
    return texts, ids


def load_pair(source, target, src_code, tgt_code, text_column='text', id_column=None,
              assume_row_aligned=False):
    import pyarrow.parquet as pq
    if id_column is None:
        common = set(pq.read_schema(source).names) & set(pq.read_schema(target).names)
        id_column = next((c for c in ('id', 'sentence_id', 'sample_id') if c in common), None)
    src, src_ids = read_records(source, text_column, id_column, src_code)
    tgt, tgt_ids = read_records(target, text_column, id_column, tgt_code)
    if id_column:
        if set(src_ids) != set(tgt_ids):
            raise ValueError(f'{source.parent.name}: source/target ID sets differ; restore missing records before evaluation')
        by_id = dict(zip(tgt_ids, tgt))
        tgt = [by_id[i] for i in src_ids]
        alignment = 'id:' + id_column
    else:
        if len(src) != len(tgt):
            raise ValueError(f'{source.parent.name}: unaligned row counts ({src_code}={len(src)}, '
                             f'{tgt_code}={len(tgt)}); supply aligned files with IDs; refusing to truncate')
        if not assume_row_aligned:
            raise ValueError(f'{source.parent.name}: no shared ID column; only use --assume-row-aligned '
                             'after confirming the original files have identical sentence ordering')
        alignment = 'row_order_explicitly_confirmed'
    return src, tgt, alignment


def compute_metrics(predictions, references, bleu, chrf):
    if not predictions or len(predictions) != len(references):
        raise ValueError('Predictions and references must be nonempty and equal in length')
    return {
        'bleu': bleu.corpus_score(predictions, [references]).score,
        'chrf++': chrf.corpus_score(predictions, [references]).score,
        'signatures': {'bleu': str(bleu.get_signature()), 'chrf++': str(chrf.get_signature())},
    }


def translation_prompt(text, source_language, target_language, examples=()):
    instruction = (f'Translate from {source_language} to {target_language}. '
                   'Return only the translation, without explanation.')
    blocks = [instruction]
    blocks.extend(f'Source: {source}\nTranslation: {target}' for source, target in examples)
    blocks.append(f'Source: {text}\nTranslation:')
    return '\n\n'.join(blocks)


def translation_messages(text, source_language, target_language, examples=()):
    instruction = (f'Translate the following text from {source_language} to {target_language}. '
                   'Return only the translation, without explanation.\n\n')
    messages = []
    for source, target in examples:
        messages.extend([{'role': 'user', 'content': instruction + source},
                         {'role': 'assistant', 'content': target}])
    messages.append({'role': 'user', 'content': instruction + text})
    return messages


def load_examples(args, dataset, src, tgt):
    if args.n_shot == 0:
        return [], {'n_shot': 0}
    # Canonical order keeps the same selected pairs for both translation directions.
    left, right = sorted((src, tgt))
    paths = [args.dev_dir / dataset / (code + '.parquet') for code in (left, right)]
    test_root = args.test_dir.resolve()
    for path in paths:
        resolved = path.resolve()
        if resolved == test_root or test_root in resolved.parents:
            raise ValueError('Few-shot examples must come from development data, not the test directory')
        # Also reject aliases (e.g. hard links) of the test files for this dataset.
        for test_file in (args.test_dir / dataset).glob('*.parquet'):
            if path.exists() and path.samefile(test_file):
                raise ValueError('A few-shot file aliases a test file')
    sources, targets, alignment = load_pair(
        *paths, left, right, args.text_column, args.id_column, args.assume_row_aligned)
    unique = {}
    for index, pair in enumerate(zip(sources, targets)):
        unique.setdefault(pair, index)
    pool = list(unique)
    if len(pool) < args.n_shot:
        raise ValueError(f'{dataset}: only {len(pool)} unique dev pairs for {args.n_shot}-shot evaluation')
    selected = random.Random(args.seed).sample(pool, args.n_shot)
    examples = selected if src == left else [(b, a) for a, b in selected]
    return examples, {'n_shot': args.n_shot, 'seed': args.seed, 'alignment': alignment,
                      'dev_dir': str(args.dev_dir.resolve()), 'canonical_source': left,
                      'canonical_target': right, 'selected_row_indices': [unique[p] for p in selected],
                      'file_sha256': {code: sha256(path) for code, path in zip((left, right), paths)}}


class Translator:
    def __init__(self, args):
        from vllm import LLM, SamplingParams
        self.args = args
        model_path = args.model.resolve()
        if not model_path.is_dir():
            raise ValueError(f'Model directory not found: {model_path}')
        adapter = (model_path / 'adapter_config.json').exists()
        if adapter and args.base_model is None:
            raise ValueError('Adapter evaluation requires --base-model pointing to the local original model')
        if not adapter and args.base_model is not None:
            raise ValueError('--base-model is only for adapter checkpoints')
        base = args.base_model.resolve() if adapter else model_path
        if not base.is_dir():
            raise ValueError(f'Base model directory not found: {base}')
        tokenizer_path = (args.tokenizer or (model_path if (model_path / 'tokenizer_config.json').exists() else base)).resolve()
        if not tokenizer_path.is_dir():
            raise ValueError(f'Tokenizer directory not found: {tokenizer_path}')
        engine_options = dict(model=str(base), tokenizer=str(tokenizer_path), trust_remote_code=False,
                              dtype='auto', tensor_parallel_size=args.tensor_parallel_size,
                              gpu_memory_utilization=args.gpu_memory_utilization,
                              seed=args.seed, generation_config='vllm', enable_lora=adapter)
        if args.max_model_len is not None:
            engine_options['max_model_len'] = args.max_model_len
        self.lora_request = None
        if adapter:
            from vllm.lora.request import LoRARequest
            adapter_config = json.loads((model_path / 'adapter_config.json').read_text())
            if adapter_config.get('peft_type') != 'LORA':
                raise ValueError('vLLM adapter inference requires a LoRA adapter; merge other adapter types first')
            rank = max([adapter_config.get('r', 0)] + list((adapter_config.get('rank_pattern') or {}).values()))
            if rank > args.max_lora_rank:
                raise ValueError(f'Adapter rank {rank} exceeds --max-lora-rank {args.max_lora_rank}')
            engine_options['max_lora_rank'] = args.max_lora_rank
            self.lora_request = LoRARequest('evaluation_adapter', 1, str(model_path))
        self.llm = LLM(**engine_options)
        self.tokenizer = self.llm.get_tokenizer()
        self.use_chat = args.prompt_format == 'chat' or (
            args.prompt_format == 'auto' and bool(getattr(self.tokenizer, 'chat_template', None)))
        if self.use_chat and not getattr(self.tokenizer, 'chat_template', None):
            raise ValueError('--prompt-format chat requires a tokenizer chat template')
        generation = dict(temperature=0.0, max_tokens=args.max_new_tokens, seed=args.seed,
                          stop=None if self.use_chat else ['\n\nSource:'])
        self.sampling_params = SamplingParams(**generation)
        self.metadata = {'backend': 'vllm', 'model': str(model_path),
                         'base_model': str(base) if adapter else None,
                         'tokenizer': str(tokenizer_path), 'prompt_format': 'chat' if self.use_chat else 'plain',
                         'engine': engine_options, 'generation': generation,
                         'n_shot': args.n_shot, 'seed': args.seed,
                         'prompt_template': (translation_messages if self.use_chat else translation_prompt)(
                             '{source_text}', '{source_language}', '{target_language}',
                             [('{example_source}', '{example_target}')] * args.n_shot)}

    def translate(self, texts, source_language, target_language, examples=()):
        predictions = []
        if len(examples) != self.args.n_shot:
            raise ValueError('The supplied example count does not match --n-shot')
        for start in range(0, len(texts), self.args.batch_size):
            prompts = []
            for text in texts[start:start + self.args.batch_size]:
                if self.use_chat:
                    prompt = self.tokenizer.apply_chat_template(
                        translation_messages(text, source_language, target_language, examples),
                        tokenize=False, add_generation_prompt=True, enable_thinking=False)
                else:
                    prompt = translation_prompt(text, source_language, target_language, examples)
                # Explicit token IDs avoid duplicate BOS tokens after chat-template rendering.
                ids = self.tokenizer.encode(prompt, add_special_tokens=not self.use_chat)
                prompts.append({'prompt_token_ids': ids})
            outputs = self.llm.generate(prompts, self.sampling_params,
                                        lora_request=self.lora_request, use_tqdm=False)
            if len(outputs) != len(prompts) or any(len(o.outputs) != 1 for o in outputs):
                raise ValueError('vLLM must return exactly one translation per input')
            predictions.extend(o.outputs[0].text.strip() for o in outputs)
            print(f'  translated {len(predictions)}/{len(texts)}', file=sys.stderr)
        return predictions


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model', type=Path, required=True)
    p.add_argument('--base-model', type=Path, help='Required local base path for PEFT adapters')
    p.add_argument('--tokenizer', type=Path)
    p.add_argument('--test-dir', type=Path, default=Path('/data/test'))
    p.add_argument('--dev-dir', type=Path, default=Path('/data/dev'), help='Aligned few-shot examples, grouped by dataset')
    p.add_argument('--n-shot', type=nonnegative_int, default=3, help='Number of dev examples per prompt (default: 3; 0 disables)')
    p.add_argument('--seed', type=nonnegative_int, default=0, help='Fixed few-shot selection and inference seed')
    p.add_argument('--languages', nargs='+', required=True, metavar='CODE=NAME')
    p.add_argument('--directions', nargs='+', metavar='SOURCE:TARGET', help='Default: all ordered language pairs')
    p.add_argument('--datasets', nargs='+', help='Default: all subdirectories containing Parquet files')
    p.add_argument('--text-column', default='text')
    p.add_argument('--id-column', help='Default: auto-detect id, sentence_id, or sample_id')
    p.add_argument('--assume-row-aligned', action='store_true')
    p.add_argument('--batch-size', type=positive_int, default=64)
    p.add_argument('--max-new-tokens', type=positive_int, default=256)
    p.add_argument('--tensor-parallel-size', type=positive_int, default=1)
    p.add_argument('--gpu-memory-utilization', type=memory_fraction, default=0.9)
    p.add_argument('--max-model-len', type=positive_int)
    p.add_argument('--max-lora-rank', type=positive_int, default=64)
    p.add_argument('--prompt-format', choices=['auto', 'plain', 'chat'], default='auto')
    p.add_argument('--output', type=Path, default=Path('translation_metrics.json'))
    p.add_argument('--validate-only', action='store_true', help='Validate all alignments without model loading/scoring')
    args = p.parse_args()
    try:
        languages = language_map(args.languages)
        directions = list(itertools.permutations(languages, 2)) if args.directions is None else [
            tuple(d.split(':')) for d in args.directions]
        if any(len(d) != 2 or d[0] == d[1] or any(c not in languages for c in d) for d in directions):
            raise ValueError('Directions must be SOURCE:TARGET with distinct configured language codes')
        if len(set(directions)) != len(directions):
            raise ValueError('Duplicate directions')
        if not args.test_dir.is_dir():
            raise ValueError(f'Test directory does not exist: {args.test_dir}')
        datasets = args.datasets or sorted(d.name for d in args.test_dir.iterdir()
                                          if d.is_dir() and any(d.glob('*.parquet')))
        if not datasets or len(set(datasets)) != len(datasets):
            raise ValueError('No datasets found, or duplicate dataset names')
        groups = []
        for dataset in datasets:
            if Path(dataset).name != dataset or dataset in ('.', '..'):
                raise ValueError('Dataset names must be immediate subdirectory names')
            for src, tgt in directions:
                source = args.test_dir / dataset / (src + '.parquet')
                target = args.test_dir / dataset / (tgt + '.parquet')
                texts, refs, alignment = load_pair(source, target, src, tgt, args.text_column,
                                                   args.id_column, args.assume_row_aligned)
                examples, shot_metadata = load_examples(args, dataset, src, tgt)
                groups.append((dataset, src, tgt, texts, refs, alignment, source, target, examples, shot_metadata))
        if args.validate_only:
            print(json.dumps({'status': 'validated_only', 'groups': [
                {'dataset': d, 'source': s, 'target': t, 'count': len(x), 'alignment': a, 'few_shot': sm}
                for d, s, t, x, _, a, _, _, _, sm in groups]}, indent=2))
            return
        from sacrebleu.metrics import BLEU, CHRF
        # Fail on unavailable FLORES resources rather than silently using another tokenizer.
        bleu, chrf = BLEU(tokenize='flores200'), CHRF(char_order=6, word_order=2, beta=2)
        translator = Translator(args)
        results = []
        for dataset, src, tgt, texts, refs, alignment, source, target, examples, shot_metadata in groups:
            print(f'Evaluating {dataset}: {src} -> {tgt}', file=sys.stderr)
            predictions = translator.translate(texts, languages[src], languages[tgt], examples)
            results.append(dict(dataset=dataset, source=src, target=tgt, count=len(texts),
                                alignment=alignment, few_shot=shot_metadata, source_sha256=sha256(source), target_sha256=sha256(target),
                                **compute_metrics(predictions, refs, bleu, chrf)))
        import importlib.metadata
        report = {'task': 'translation', 'timestamp': datetime.now(timezone.utc).isoformat(),
                  'test_dir': str(args.test_dir.resolve()), 'languages': languages,
                  'inference': translator.metadata, 'groups': results,
                  'macro_average': {m: sum(r[m] for r in results) / len(results) for m in ('bleu', 'chrf++')},
                  'aggregation': 'Unweighted mean over dataset/direction groups; scores on a 0-100 scale.',
                  'versions': {pkg: importlib.metadata.version(pkg) for pkg in
                               ('sacrebleu', 'sentencepiece', 'pyarrow', 'vllm', 'transformers', 'torch')}}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (OSError, ValueError, ImportError) as exc:
        p.exit(2, f'evaluate: {exc}\n')


if __name__ == '__main__':
    main()
