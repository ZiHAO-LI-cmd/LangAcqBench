#!/usr/bin/env bash
set -euo pipefail
TIMER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$TIMER_DIR/.timer.json" "$@" <<'PY'
import argparse
import json
import math
from pathlib import Path
import sys
import time

state = Path(sys.argv[1])
p = argparse.ArgumentParser(description="Show remaining experiment time; state lives beside timer.sh.")
p.add_argument('--init', action='store_true')
p.add_argument('--config', type=Path, help='Experiment JSON containing num_hours (initialization only)')
p.add_argument('--start', type=float, help='Start Unix timestamp; defaults to now')
p.add_argument('--deadline', type=float, help='Optional earlier scheduler deadline as Unix timestamp')
p.add_argument('--json', action='store_true')
a = p.parse_args(sys.argv[2:])
try:
    if a.init:
        if a.config is None:
            p.error('--init requires --config')
        hours = json.loads(a.config.read_text())['num_hours']
        if isinstance(hours, bool) or not isinstance(hours, (int, float)) or not math.isfinite(hours) or hours <= 0:
            raise ValueError('num_hours must be a positive finite number')
        start = time.time() if a.start is None else a.start
        if not math.isfinite(start) or (a.deadline is not None and not math.isfinite(a.deadline)):
            raise ValueError('timestamps must be finite')
        deadline = start + hours * 3600
        if a.deadline is not None:
            deadline = min(deadline, a.deadline)
        # Exclusive creation prevents an accidental restart from resetting the budget.
        with state.open('x') as f:
            json.dump({'start_epoch': start, 'deadline_epoch': deadline, 'num_hours': hours}, f)
    elif a.config is not None or a.start is not None or a.deadline is not None:
        p.error('--config, --start, and --deadline require --init')
    data = json.loads(state.read_text())
    now = time.time()
    remaining = max(0, math.ceil(data['deadline_epoch'] - now))
    result = dict(data, remaining_seconds=remaining,
                  elapsed_seconds=max(0, int(now - data['start_epoch'])),
                  expired=now >= data['deadline_epoch'])
    if a.json:
        print(json.dumps(result))
    else:
        h, r = divmod(remaining, 3600)
        m, s = divmod(r, 60)
        print(f'Remaining: {h:02d}:{m:02d}:{s:02d} ({remaining} seconds)' + (' [EXPIRED]' if result['expired'] else ''))
except (OSError, ValueError, KeyError, TypeError) as exc:
    p.exit(2, f'timer: {exc}\nInitialize once with: bash timer.sh --init --config experiment.json\n')
PY
