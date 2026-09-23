# Claude Code on Roihu

Claude Code runs as a separate CLI in an Apptainer image based on vLLM 0.19.1.
It shares the prompt template, experiment JSON, evaluation tool, and timer with
OpenCode and Codex. The container image uses a pinned Claude Code version and
disables in-job auto-updates. Build the image on Roihu-GPU so the official
installer selects the target Linux architecture.

## Build once

Run from the repository root on Roihu. Set `TMPDIR` to a cluster-provided
writable location before sourcing `env.sh`.

```bash
source env.sh
mkdir -p containers build-claude models data logs

# Prepare a specific official Claude Code version in an isolated temporary home.
bash scripts/download-claude.sh VERSION

# First obtain the prepared vLLM base image if it is not already present.
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu

apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/claude.sif claude.def
AGENT=claude bash scripts/in-container.sh claude --version
```

Replace `VERSION` with the numeric version selected for the experiment records.
The download helper runs Anthropic's official installer under a temporary
`HOME`, copies the installed CLI binary into `build-claude/`, and records local
SHA-256 checksums for the binary and installer. Those checksums document the
prepared files; they are not an independent upstream signature verification.
Re-run the helper when intentionally upgrading. Nothing installs or upgrades
Claude Code during a Slurm job.

If your cluster does not support `--fakeroot`, use the locally supported
Apptainer build mode instead. Image builds need temporary space beyond the final
SIF size.

## Interactive use and authentication

```bash
AGENT=claude bash scripts/in-container.sh claude auth login
AGENT=claude bash scripts/in-container.sh claude auth status
AGENT=claude bash scripts/in-container.sh
```

Complete the browser login flow. Claude Code stores Linux login credentials in
`interactive/claude/home/.claude/.credentials.json`; the container entry point
keeps this home separate from OpenCode and Codex. Protect this file as a secret.
An Anthropic Console/API login may incur API charges separate from a Claude
subscription.

To use an Anthropic Console API key instead, create a key in the Console and
provide it as `ANTHROPIC_API_KEY` to Claude Code. The wrapper uses Apptainer's
`APPTAINERENV_` convention to pass it through `--cleanenv`; this does not save
the key in the image or run directory. For an interactive session:

```bash
read -rsp 'Anthropic API key: ' CLAUDE_API_KEY
printf '\n'
export APPTAINERENV_ANTHROPIC_API_KEY="$CLAUDE_API_KEY"
unset CLAUDE_API_KEY
AGENT=claude bash scripts/in-container.sh claude
```

On first use, approve the key when prompted. In later sessions, set the
environment variable again; `ANTHROPIC_API_KEY` takes precedence over a saved
subscription OAuth login.

The default interactive workspace is `interactive/claude/work`. Set `RUN_DIR`
to use a different home and workspace. For an interactive GPU session, request
a GPU first, then set `USE_GPU=1`:

```bash
srun --account=project_2008161 --partition=gputest \
  --nodes=1 --ntasks=1 --cpus-per-task=72 \
  --gres=gpu:gh200:1 --time=0-00:15:00 \
  --pty env AGENT=claude USE_GPU=1 bash scripts/in-container.sh
```

`USE_GPU=1` enables Apptainer's `--nv` option; it does not allocate a GPU.

## GPU check and batch jobs

Create `logs/` and submit from the repository root, since Slurm uses the submit
directory to locate `env.sh`:

```bash
mkdir -p logs
sbatch --export=ALL,AGENT=claude scripts/gpu-check.sh
```

Submit a translation experiment with a Claude model alias or model ID available
to your account:

```bash
sbatch scripts/claude.sh sonnet configs/smollm3-swedish.example.json

# Optional effort level: low, medium, high, xhigh, or max.
sbatch scripts/claude.sh sonnet configs/smollm3-swedish.example.json high
```

The batch launcher supports the Console API key without an OAuth login file.
To submit with a key, enter it silently in the shell, export it for Slurm, and
remove it from the current shell after the job is submitted:

```bash
read -rsp 'Anthropic API key: ' CLAUDE_API_KEY
printf '\n'
export APPTAINERENV_ANTHROPIC_API_KEY="$CLAUDE_API_KEY"
unset CLAUDE_API_KEY
sbatch --export=ALL scripts/claude.sh sonnet configs/smollm3-swedish.example.json
unset APPTAINERENV_ANTHROPIC_API_KEY
```

The key is injected into the container by Apptainer and takes precedence over
any saved OAuth credential. Without the key, the launcher uses the interactive
OAuth credential and its concurrency lock as described below.

The launcher renders and snapshots the prompt and experiment configuration,
initializes the timer, and runs `claude -p` with JSON event output. It stores
events in `runs/claude-JOB_ID/agent.jsonl`, errors in `agent.err`, and the final
assistant response in `work/agent-final.md`. Each run gets a separate home and
workspace. The launcher serializes access to the interactive OAuth credential
and persists a refreshed credential after the job exits; a concurrent Claude
batch job using the same login fails immediately rather than waiting for a GPU.

Batch jobs use Claude Code's permission bypass because no one can answer
interactive prompts. This grants the agent autonomous tool execution in the
job environment. Apptainer containment is not a VM security boundary; submit
only trusted prompts. Models and datasets are mounted read-only, while the run
home and workspace are writable.

The default job uses the repository's 15-minute gputest allocation. Override
partition/time at submission for longer experiments and keep the experiment
`num_hours` consistent with the Slurm allocation. `models/` and `data/` must
exist because the container entry point mounts them.

## Timer and translation evaluation

The Claude launcher copies `evaluate.py` and `timer.sh` into the run workspace.
Use the same vLLM evaluation workflow described in the
[OpenCode guide](opencode.md#timer-and-translation-evaluation); the evaluator,
metrics, dataset layout, and few-shot data rules are shared across agents.
