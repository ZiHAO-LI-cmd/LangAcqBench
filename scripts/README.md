# Scripts

Run examples from the repository root. The five common entry points stay in
`scripts/`; implementations and helpers are grouped by purpose.

| Path | Purpose |
| --- | --- |
| `submit-agent.sh` | Validate an experiment and submit the selected agent job |
| `in-container.sh` | Open an interactive CLI or execute a command in Apptainer |
| `evaluate-slurm.sh` | Request Slurm resources and run evaluation |
| `evaluate.sh` | Run evaluation inside an existing Slurm allocation |
| `gpu-check.sh` | Submit a GPU availability and computation check |
| `agents/` | Slurm launchers for OpenCode, Codex, Claude, Kimi, Antigravity, and Grok |
| `downloads/` | Prepare pinned CLI releases in the repository's `build-AGENT/` directories |
| `evaluation/` | `evaluate-mt.py` and `evaluate-report.py` |
| `lib/` | Shared experiment validation, prompt rendering, API-key loading, job setup, summaries, and Kimi effort settings |

Dataset download and token preparation scripts live in [`../tools/`](../tools/).
See the [shared workflow](../docs/agent-common.md) and individual agent guides for
authentication, resource settings, and supported model arguments.

## Common commands

```bash
# Interactive container session.
AGENT=claude bash scripts/in-container.sh

# Submit an experiment; time and partition come from the configuration.
bash scripts/submit-agent.sh claude sonnet configs/smollm3-swedish.json

# Preview the prompt without submitting a job.
python3 scripts/lib/render-prompt.py --config configs/smollm3-swedish.json \
  --output /tmp/prompt.preview.md

# Show evaluation options without submitting a job.
bash scripts/evaluate-slurm.sh --help

# Download a pinned CLI release for an image build.
bash scripts/downloads/download-codex.sh 0.167.0
```

## Paths after reorganization

The five top-level entry points keep their existing paths and arguments.
For direct Slurm submissions, use `scripts/agents/AGENT.sh`:

```bash
sbatch scripts/agents/claude.sh sonnet configs/smollm3-swedish.json
```

Direct submissions retain the launcher's `#SBATCH` defaults; inspect the account
and override resources as needed. `submit-agent.sh` selects the new launcher
path automatically.

Other former flat paths move as follows:

| Former path | Current path |
| --- | --- |
| `scripts/<agent>.sh` | `scripts/agents/<agent>.sh` |
| `scripts/download-<agent>.sh` | `scripts/downloads/download-<agent>.sh` |
| `scripts/evaluate-mt.py`, `scripts/evaluate-report.py` | `scripts/evaluation/` with the same filenames |
| Shared shell and Python helpers | `scripts/lib/` with the same filenames |

Use the new paths in external scripts. Historical run snapshots keep the tools
copied when those jobs started. New standard-mode jobs still copy evaluation
tools into `work/` using their existing filenames; train-only jobs omit them.
