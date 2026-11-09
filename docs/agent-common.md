# Shared agent workflow on Roihu

OpenCode, Codex, Claude Code, Kimi Code, Antigravity CLI, and Grok Build share
an Apptainer vLLM 0.19.1 base, experiment configs, prompt renderer, timer, and
evaluator. Use this guide for common setup, then follow the selected CLI guide:
[OpenCode](opencode.md), [Codex](codex.md), [Claude](claude.md),
[Kimi](kimi.md), [Antigravity](antigravity.md), or [Grok](grok.md).
Provider configuration and API checks are in [Azure models](azure-models.md).

## Prepare the environment

Run commands from the repository root on Roihu. Check the cluster paths in
`env.sh` and set `TMPDIR` to a cluster-provided writable directory before
sourcing it:

```bash
source env.sh
mkdir -p containers models data runs

# Obtain the shared base once, if absent.
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu
```

Each CLI guide specifies a pinned download and image build. The build examples
target Linux ARM64 on GH200; the CLI, base image, and build/runtime architecture
must match. Use allocated build resources with enough temporary space to repack
the base image. If `--fakeroot` is unavailable, use the cluster's supported build
mode. Upgrades require an explicit download and rebuild; updating a host CLI
does not update the executable inside a SIF.

Keep `build-AGENT/` inputs with experiment records. Publisher checksums detect
corruption but are not independent signatures; local checksums record the files
used. The CLI guides describe which checks each downloader performs.

## Interactive sessions

`AGENT` selects `containers/AGENT.sif` and the default CLI. It defaults to
`opencode`; Antigravity's command is `agy`. An explicit command can run a shell
or Python instead:

```bash
AGENT=claude bash scripts/in-container.sh
AGENT=claude bash scripts/in-container.sh bash
```

OpenCode stores its persistent home/work under `interactive/`; other agents use
`interactive/AGENT/`. Set `RUN_DIR` to override that parent. Inside the container,
the home is `/home/agent`, the workspace is `/workspace`, models are mounted at
`/models` read-only, and runtime temporary files use `/tmp`.

For interactive GPU use, allocate a GPU before enabling `USE_GPU=1`:

```bash
srun --account=project_2008161 --partition=gputest \
  --nodes=1 --ntasks=1 --cpus-per-task=72 \
  --gres=gpu:gh200:1 --time=0-00:15:00 \
  --pty env AGENT=claude USE_GPU=1 bash scripts/in-container.sh
```

Replace the account and agent as needed. `USE_GPU=1` enables Apptainer's `--nv`;
it does not allocate a GPU.

## API keys and clean environments

The entry point uses `--cleanenv`. Forward host credentials with
`APPTAINERENV_NAME` to make them available inside the container as `NAME`.
The repository's `.env` loader supports Anthropic and Gemini keys only:

```bash
# Create once; preserve an existing file.
(umask 077; cp -n .env.example .env)
chmod 600 .env
${EDITOR:-vi} .env
```

Fill only the keys you use:

```dotenv
ANTHROPIC_API_KEY=your-anthropic-api-key
GEMINI_API_KEY=your-gemini-api-key
```

`env.sh` loads the file on interactive and batch startup and exports the
corresponding `APPTAINERENV_*` variables. The file stays on the host; it is
Git-ignored and is not copied into images or job homes. No image rebuild is
needed when changing keys.

Use literal `KEY=value`, optionally with `export` or surrounding quotes. Shell
commands, variable expansion, escape processing, and inline comments are not
supported; put comments on separate lines. Nonempty values take priority in
this order: prefixed environment variable, unprefixed environment variable,
prefixed file entry, unprefixed file entry. Unset old shell overrides to return
to file values.

Set `LANGACQBENCH_ENV_FILE=/absolute/path/to/keys.env` to choose another file;
export it before direct `sbatch`. A missing file is allowed for OAuth or manually
exported keys. Keep the file on the shared filesystem until queued jobs start.
Running jobs retain their loaded values. Azure and xAI keys require their own
saved configuration or explicit environment forwarding; `.env` does not load them.

## Submit experiments

Configure authentication using the CLI guide, then check GPU access:

```bash
sbatch --export=ALL,AGENT=claude scripts/gpu-check.sh
# Inspect runs/gpu-check-JOB_ID/gpu-check-JOB_ID.out.
```

Choose an agent, a supported model identifier, and an experiment JSON:

```text
bash scripts/submit-agent.sh AGENT MODEL EXPERIMENT_CONFIG [REASONING_OR_EFFORT_LEVEL]
```

The optional fourth positional argument selects effort; it is not an environment
variable. CLI guides describe how it is passed and which model restrictions
apply. To preview an adapted config before submission:

```bash
cp configs/smollm3-swedish.example.json configs/my-experiment.json
python3 scripts/render-prompt.py --template prompt.md \
  --config configs/my-experiment.json --output /tmp/prompt.preview.md
```

The helper validates the config, sets Slurm time from `num_hours` rounded up to
whole minutes, and selects `gputest` for at most 15 minutes or `gpumedium` above
that. It accepts config paths from any working directory and submits from the
repository root. Direct `sbatch scripts/AGENT.sh MODEL CONFIG [EFFORT]` should run
from the root and retains the script's 15-minute `gputest` defaults unless
Slurm flags override them. Check the selected script's account setting.
Slurm must forward required environment variables, normally with `--export=ALL`.

Jobs snapshot prompts, config, and credentials when they start. Each gets its
own home/work. `standard` mounts `/data` read-only and uses the shared HF cache;
`train_only` exposes only configured training data and uses a private HF cache
with stricter mount isolation. Both mount models read-only. Launchers enable
unattended tools in writable job directories; submit trusted experiment prompts.

## Outputs and monitoring

The helper creates `runs/AGENT-EXPERIMENT-MODEL-JOB_ID/`, using shortened,
lowercase, path-safe config/model labels. Direct submissions use the Slurm job
name instead. Common files are:

| Path inside the run directory | Content |
| --- | --- |
| `home/` | Private CLI configuration, credentials, and sessions |
| `work/` | Snapshotted experiment, rendered prompt, tools, and outputs |
| `agent.jsonl` | Agent events and tool activity |
| `agent.err` | CLI diagnostics |
| `work/agent-final.md` | Final assistant response, when the launcher saves one |
| `JOB_NAME-JOB_ID.out`, `JOB_NAME-JOB_ID.err` | Slurm logs and job summary |

```bash
squeue -u "$USER"
tail -f runs/RUN_NAME/agent.jsonl
cat runs/RUN_NAME/agent.err
scancel JOB_ID
```

An empty Slurm stdout log during execution can be normal because agent events
are redirected. Summaries report elapsed time, exit status, and agent-reported
USD cost when available; they do not include GPU cost. Exit code 0 or a final
assistant message alone does not establish experiment completion: inspect the
requested model artifacts and training/evaluation logs.

Treat interactive homes, run homes, credentials, and logs as private. OAuth
refresh locks and credential copy-back rules differ by CLI; see its guide.
