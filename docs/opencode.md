# OpenCode on Roihu

OpenCode is the default agent in this repository. It runs in an Apptainer image
based on vLLM 0.19.1 and uses the shared prompt template, experiment JSON,
evaluation tool, and timer. For the parallel Codex integration, see
[Codex on Roihu](codex.md).

## Build once

Run the following from the repository root on Roihu. Set `TMPDIR` to a
cluster-provided writable location before sourcing `env.sh`.

```bash
source env.sh
mkdir -p containers build-opencode models data logs

# Downloads OpenCode 1.18.30 for Linux ARM64 and records its local checksum.
bash scripts/download-opencode.sh 1.18.30

# First obtain the prepared vLLM base image if it is not already present.
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu

apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/opencode.sif opencode.def
bash scripts/in-container.sh opencode --version
```

The download helper fetches the official `opencode-linux-arm64.tar.gz` release
asset, extracts only its `opencode` executable, and writes
`build-opencode/opencode.sha256`. This is a local provenance check, not an
independent upstream signature verification. Keep the archive and checksum with
the experiment records. Re-run the helper when intentionally upgrading OpenCode;
nothing downloads or upgrades the CLI during a job.

The final image copies the executable to `/usr/local/bin/opencode`, records its
checksum, reuses the vLLM/PyTorch base environment, and installs SacreBLEU 2.5.1.
Build tests validate the CLI and Python evaluation dependencies. GPU inference
must still be checked in a Slurm allocation.

If your cluster does not support `--fakeroot`, use the locally supported
Apptainer build mode instead. Image builds need temporary space beyond the final
SIF size.

## Interactive use and authentication

```bash
bash scripts/in-container.sh opencode --version
bash scripts/in-container.sh opencode auth login
bash scripts/in-container.sh
```

Follow the login prompts to select and authenticate a provider. Credentials are
stored under `interactive/home/.local/share/opencode/auth.json`. List currently
available models with:

```bash
bash scripts/in-container.sh opencode models > opencode_models.txt
```

Put interactive task inputs in `interactive/work/`; generated files are saved
there too. The container entry point uses `--cleanenv --contain` and mounts:

| Host path | Container path | Purpose |
| --- | --- | --- |
| `$RUN_DIR/home` | `/home/agent` | Credentials, configuration, caches, sessions |
| `$RUN_DIR/work` | `/workspace` | Task files and outputs |
| `$HF_HOME` | `/hf-cache` | Shared Hugging Face cache |
| `$TMPDIR/opencode-${SLURM_JOB_ID:-interactive}` | `/tmp` | Runtime temporary files |

For interactive GPU work, request a GPU first, then set `USE_GPU=1`:

```bash
srun --account=project_2008161 --partition=gputest \
  --nodes=1 --ntasks=1 --cpus-per-task=72 \
  --gres=gpu:gh200:1 --time=0-00:15:00 \
  --pty env USE_GPU=1 bash scripts/in-container.sh
```

`USE_GPU=1` enables Apptainer's `--nv` option; it does not allocate a GPU.

## GPU check and batch jobs

Create `logs/` and submit from the repository root, since Slurm uses the submit
directory to locate `env.sh`:

```bash
mkdir -p logs
sbatch scripts/gpu-check.sh
```

The check validates CUDA availability and a GPU matrix computation. Inspect it
with `squeue -u "$USER"` and `cat logs/gpu-check-JOB_ID.out`.

To submit an agent task, first authenticate interactively and choose a complete
`provider/model` identifier from the model list. Copy and adapt the example
experiment configuration, then preview its rendered prompt:

```bash
cp configs/smollm3-swedish.example.json configs/my-experiment.json
python3 scripts/render-prompt.py --template prompt.md \
  --config configs/my-experiment.json --output /tmp/prompt.preview.md

MODEL_ID='provider/model'
sbatch scripts/opencode.sh "$MODEL_ID" configs/my-experiment.json

# Optional reasoning variant, when supported by the selected model.
sbatch scripts/opencode.sh "$MODEL_ID" configs/my-experiment.json high
```

The optional argument is passed as `opencode run --variant`; available variants
depend on the provider/model. The launcher creates `runs/opencode-JOB_ID/`,
copies only `auth.json` into an isolated job home, snapshots and renders the
prompt/configuration, initializes the timer, and writes OpenCode events to
`agent.jsonl` and errors to `agent.err`. It enables automatic tool permissions,
so submit only trusted experiments.

```bash
tail -f runs/opencode-JOB_ID/agent.jsonl
cat runs/opencode-JOB_ID/agent.err
scancel JOB_ID
```

An empty `logs/opencode-JOB_ID.out` is normal: agent output is redirected to the
run directory. Queued jobs snapshot prompt/configuration/credentials when they
start, not when submitted.