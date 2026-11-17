#!/usr/bin/env python3
"""Add COMET scores to saved translation results after vLLM has exited."""

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import tempfile


DEFAULT_MODEL = 'Unbabel/wmt22-comet-da'


def positive_int(value):
    value = int(value)
    if value <= 0:
        raise argparse.ArgumentTypeError('must be positive')
    return value


def load_samples(report, translation_path):
    artifact = report.get('samples_file')
    if not artifact:
        raise ValueError('No saved translation samples; rerun evaluate-mt.py to capture model outputs')
    path = Path(artifact['path'])
    if not path.is_absolute():
        path = translation_path.parent / path
    content = path.read_bytes()
    if hashlib.sha256(content).hexdigest() != artifact['sha256']:
        raise ValueError('Translation samples checksum mismatch')
    saved = json.loads(content)['groups']
    groups = report['groups']
    if not groups or len(saved) != len(groups):
        raise ValueError('Translation sample groups do not match metric groups')
    for group, sample_group in zip(groups, saved):
        if any(group[key] != sample_group[key] for key in ('dataset', 'source', 'target')):
            raise ValueError('Translation sample dataset/direction does not match metrics')
        samples = sample_group['samples']
        if not samples or len(samples) != group['count']:
            raise ValueError('Translation sample count does not match metrics')
        for sample in samples:
            if any(not isinstance(sample.get(key), str) for key in ('src', 'mt', 'ref')):
                raise ValueError('COMET samples require string src, mt and ref fields')
            if not sample['src'].strip() or not sample['ref'].strip():
                raise ValueError('COMET source/reference must be nonempty')
    return saved


def score_report(report, sample_groups, model, batch_size, gpus):
    # Validate all scores before changing the report, so a failed group can be retried.
    scores = []
    for group in sample_groups:
        output = model.predict(group['samples'], batch_size=batch_size, gpus=gpus,
                               num_workers=0)
        score = float(output.system_score)
        if (len(output.scores) != len(group['samples']) or not math.isfinite(score)
                or any(not math.isfinite(float(value)) for value in output.scores)):
            raise ValueError('COMET returned invalid scores or an unexpected sample count')
        scores.append(score)
    for group, score in zip(report['groups'], scores):
        group['comet'] = score
    report['macro_average']['comet'] = sum(scores) / len(scores)


def write_report(path, report):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix=path.name + '.', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write('\n')
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--translation', type=Path, required=True, help='Update this translation JSON in place')
    parser.add_argument('--model', default=DEFAULT_MODEL, help='Hugging Face model ID or local COMET .ckpt')
    parser.add_argument('--batch-size', type=positive_int, default=8)
    parser.add_argument('--gpus', type=int, choices=(0, 1), default=1, help='0 for CPU, 1 for one GPU')
    args = parser.parse_args()
    try:
        report = json.loads(args.translation.read_text(encoding='utf-8'))
        sample_groups = load_samples(report, args.translation)
        try:
            from comet import download_model, load_from_checkpoint
        except ImportError as exc:
            raise ValueError('COMET requires unbabel-comet in the separate env-comet environment; '
                             'see docs/evaluation.md') from exc
        local_model = Path(args.model).expanduser()
        if local_model.is_file():
            checkpoint = str(local_model.resolve())
        elif local_model.is_absolute() or args.model.endswith('.ckpt'):
            raise ValueError(f'COMET checkpoint not found: {args.model}')
        else:
            checkpoint = download_model(args.model)
        model = load_from_checkpoint(checkpoint)
        score_report(report, sample_groups, model, args.batch_size, args.gpus)
        report['comet'] = {'model': args.model, 'checkpoint': str(checkpoint),
                           'version': importlib.metadata.version('unbabel-comet'),
                           'batch_size': args.batch_size, 'gpus': args.gpus,
                           'timestamp': datetime.now(timezone.utc).isoformat(),
                           'scale': 'Raw model scores, without rescaling or clipping.',
                           'aggregation': 'Per-group system_score; macro_average is the unweighted mean over groups.'}
        write_report(args.translation, report)
        print(f'COMET macro average: {report["macro_average"]["comet"]:.6f}')
    except (OSError, KeyError, TypeError, ValueError, ImportError, RuntimeError) as exc:
        parser.exit(2, f'evaluate-comet: {exc}\n')


if __name__ == '__main__':
    main()
