# Apptainer + OpenCode + Slurm Setup and Operation Guide

This guide covers environment setup, authentication, GPU checks, and job submission. Commands use the current cluster configuration and should be run from the repository root unless stated otherwise.

## 1. Environment and Directory Layout

The current local environment:

| Component | Configuration |
| --- | --- |
| CPU architecture | ARM64 / aarch64 |
| Container runtime | Apptainer (image build metadata records version 1.4.5) |
| OpenCode | 1.18.30 |
| PyTorch | 2.10.0+cu129 (vLLM base) |
| GPU | NVIDIA GH200 120GB |
| Slurm account / partition | `project_2008161` / `gputest` |
| Default job resources | 1 node, 1 task, 72 CPUs, 1 GH200 GPU, 15 minutes |

The host must provide `apptainer`, Slurm commands, and a writable temporary directory. Downloading images, authenticating with model providers, and calling models require access to the corresponding network services.

```text
.
├── env.sh                     # Host paths and cache configuration
├── opencode.def               # Container build definition
├── build-opencode/            # OpenCode binary, archive, and checksum
├── containers/                # Base and final container images
├── scripts/
│   ├── in-container.sh        # Shared container entry point
│   ├── gpu-check.sh           # Slurm GPU check
│   └── opencode.sh            # Slurm OpenCode job
├── prompt.md                 # Batch job prompt
├── opencode_models.txt        # Model list snapshot; can be regenerated
├── interactive/               # Home and work directories for interactive sessions
├── runs/                      # Separate directory for each batch job
└── logs/                      # Slurm standard output and error logs
```

Container images, downloaded binaries, interactive directories, run outputs, and logs are excluded by `.gitignore`. After cloning the repository, prepare the images and runtime directories locally.

## 2. Configure Paths

Update the paths in `env.sh` to match your deployment:

```bash
export PROJECT_ROOT=/scratch/project_2008161/zihao/LangAcqBench
export APPTAINER_CACHEDIR=/scratch/project_2008161/cache/apptainer-cache
export HF_HOME=/scratch/project_2008161/cache/huggingface
```

`env.sh` also sets `APPTAINER_TMPDIR` to `$TMPDIR/apptainer-build` and creates the cache directories.

```bash
cd /scratch/project_2008161/zihao/LangAcqBench
# TMPDIR should point to a cluster-provided writable directory with enough space.
: "${TMPDIR:?Set the cluster-provided temporary directory first}"
source env.sh
mkdir -p containers build-opencode logs
```

If `TMPDIR` is not set in the current shell, configure it according to your cluster's conventions before running `source env.sh`. Image builds need space for unpacked files and intermediate artifacts, so temporary storage requirements exceed the final SIF file size.

When moving to another account or partition, also update the `#SBATCH` directives in `scripts/gpu-check.sh` and `scripts/opencode.sh`.

## 3. Prepare and Build the Container

If a working `containers/opencode.sif` already exists, skip to section 4.

### 3.1 Prepare the vLLM Base Image

The build uses the prepared vLLM 0.19.1 base image. Pull it from an environment with access to this registry:

```bash
source env.sh
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu
```

The local image contains vLLM 0.19.1, PyTorch 2.10.0+cu129, and the main training dependencies for ARM64. The older `containers/pytorch-base.sif` is not used by this definition.

### 3.2 Prepare the OpenCode Binary

Obtain the **OpenCode 1.18.30 Linux ARM64 release archive** and save it as:

```text
build-opencode/opencode-linux-arm64.tar.gz
```

The repository does not currently include an automatic download script. Obtain the release archive yourself or copy the existing build materials. The executable inside the current archive is named `opencode`.

```bash
tar -xzf build-opencode/opencode-linux-arm64.tar.gz -C build-opencode
chmod +x build-opencode/opencode
sha256sum -c build-opencode/opencode.sha256
./build-opencode/opencode --version
```

The checksum file corresponds to the binary currently in use. If you intentionally upgrade OpenCode, verify the new file's source and version before updating the checksum:

```bash
sha256sum ./build-opencode/opencode > build-opencode/opencode.sha256
```

### 3.3 Build the Final Image

On a node that supports unprivileged Apptainer builds, run from the repository root:

```bash
apptainer build containers/opencode.sif opencode.def
```

`opencode.def` uses `containers/vllm-0-19-1-base.sif`, copies OpenCode to `/usr/local/bin/opencode`, and records its checksum in `/opt/opencode/binary.sha256`. It reuses the base image's vLLM/PyTorch stack and adds SacreBLEU 2.5.1. Installed Python versions are recorded in `/opt/opencode/python-requirements.txt`. `vllm-python` is a compatibility wrapper for `/usr/bin/python3`; training and evaluation share the base environment. Build tests check OpenCode and import the evaluation packages. GPU inference must be checked separately through Slurm.

If the cluster requires fakeroot builds and has enabled that support for your user, use:

```bash
apptainer build --fakeroot containers/opencode.sif opencode.def
```

## 4. Container Entry Point and Authentication

Run routine container commands through `scripts/in-container.sh`:

```bash
bash scripts/in-container.sh opencode --version
bash scripts/in-container.sh python3 -c 'import torch; print(torch.__version__)'
bash scripts/in-container.sh opencode auth login
```

Follow the login prompts to select a model provider and authenticate. The default credential location is:

```text
interactive/home/.local/share/opencode/auth.json
```

List the currently available models and update the local snapshot:

```bash
bash scripts/in-container.sh opencode models > opencode_models.txt
```

Running the entry point without a command starts the OpenCode interactive interface:

```bash
bash scripts/in-container.sh
```

Place input files for interactive tasks in `interactive/work/`. Generated files are also saved there.

### Container Directory Mappings

The entry script defaults to `RUN_DIR=$PROJECT_ROOT/interactive`. Batch jobs set their own `RUN_DIR`.

| Host path | Container path | Purpose |
| --- | --- | --- |
| `$RUN_DIR/home` | `/home/agent` | Configuration, authentication, caches, and session state |
| `$RUN_DIR/work` | `/workspace` | Working directory and task files |
| `$HF_HOME` | `/hf-cache` | Shared Hugging Face cache |
| `$TMPDIR/opencode-${SLURM_JOB_ID:-interactive}` | `/tmp` | Runtime temporary files |

The script uses `--cleanenv --contain` and explicitly sets the HF and XDG paths inside the container. The repository root is not explicitly bound as the working directory; tasks should access inputs and outputs through `/workspace`. Do not assume that host environment variables are automatically passed into the container.

## 5. Check GPU Access

**Submit jobs from the repository root and create `logs/` first.** The scripts use `SLURM_SUBMIT_DIR` to locate `env.sh`, and Slurm must open its log files before the job script starts.

```bash
mkdir -p logs
sbatch scripts/gpu-check.sh
```

Use the job ID returned by `sbatch` to check status and results:

```bash
squeue -u "$USER"
# Replace 123456 with the actual job ID.
cat logs/gpu-check-123456.out
cat logs/gpu-check-123456.err
```

The script checks `torch.cuda.is_available()`, performs a matrix computation on the GPU, and synchronizes to wait for completion. An existing local test log shows:

```text
PyTorch: 2.10.0+cu130
GPU: NVIDIA GH200 120GB
GPU computation OK: ...
```

For interactive GPU use, request resources and start the container:

```bash
srun --account=project_2008161 --partition=gputest \
  --nodes=1 --ntasks=1 --cpus-per-task=72 \
  --gres=gpu:gh200:1 --time=0-00:15:00 \
  --pty env USE_GPU=1 bash scripts/in-container.sh
```

`USE_GPU=1` enables Apptainer's `--nv` option and passes `CUDA_VISIBLE_DEVICES` into the container when Slurm has set it. Setting `USE_GPU=1` alone does not allocate GPU resources.

## 6. Submit an OpenCode Batch Job

1. Complete authentication in section 4 and select a full `provider/model` identifier from the model list.
2. Keep `prompt.md` as a reusable template. Copy `configs/smollm3-swedish.example.json` to an experiment JSON file and edit its model, container model path, languages, translation directions, benchmark, time budget, and GPU description. Rendering requires Python 3 on the submission/compute host and uses only its standard library. Preview the final prompt before submission:

```bash
python3 scripts/render-prompt.py --template prompt.md \
  --config configs/smollm3-swedish.example.json --output /tmp/prompt.preview.md
```

Missing/unknown fields, empty values, unresolved placeholders, and invalid time budgets fail before the agent starts. Lists are rendered as comma-separated text. Ordinary JSON braces in the template are preserved. The config's `num_hours` is an agent budget; it does not change Slurm's `--time`. Set the Slurm allocation separately if needed. `gpu_info` describes expected resources; it is not automatic hardware detection.
3. Submit the job from the repository root:

```bash
mkdir -p logs
# Replace the placeholder with an actual identifier from the current model list.
MODEL_ID='provider/model'
sbatch scripts/opencode.sh "$MODEL_ID" configs/smollm3-swedish.example.json
```

The script:

- Creates `runs/opencode-<job-id>/home` and `work`.
- Copies `auth.json` from the interactive environment into the job's own home directory.
- Writes a configuration that disables automatic updates and sets `permission: allow` so the task can execute tool operations automatically.
- Snapshots the prompt template and experiment JSON, renders the final `prompt.md`, and calls `opencode run --model ... --format json`.
- Enables GPU access and writes the event stream and errors to `agent.jsonl` and `agent.err`, respectively.

The template, experiment config, and credentials are copied **when the job starts executing**. Editing them while a job is queued affects jobs that have not started yet. Each job retains `prompt.template.md`, `experiment.json`, and the rendered `prompt.md` for inspection. The launcher also copies `evaluate.py`, `timer.sh`, and `requirements-eval.txt` into the workspace and initializes `.timer.json` before agent startup. The timer starts at batch-script entry, excluding queue time, and caps the configured budget at the Slurm end time when available.

### Inspect Results

```text
runs/opencode-<job-id>/
├── agent.jsonl                # OpenCode JSON event stream
├── agent.err                  # OpenCode / srun error output
├── home/                      # Job-specific configuration, credentials, and sessions
└── work/
    ├── prompt.template.md    # Template snapshot
    ├── experiment.json       # Experiment configuration snapshot
    ├── prompt.md             # Rendered prompt used for this job
    └── ...                    # Generated code, reports, and weights
```

```bash
# Replace 123456 with the actual job ID.
tail -f runs/opencode-123456/agent.jsonl
cat runs/opencode-123456/agent.err
ls -lh runs/opencode-123456/work
cat logs/opencode-123456.err
```

OpenCode output is redirected into `runs/`, so an empty `logs/opencode-<job-id>.out` can be normal. For the current example prompt, the task report should be at `work/report.md`.

To cancel a job:

```bash
scancel 123456
```

## 7. Timer and Translation Evaluation

The batch launcher initializes the timer automatically. Inside the agent workspace:

```bash
bash timer.sh
bash timer.sh --json
```

For a manually prepared workspace, copy `timer.sh` there and initialize it once with `bash timer.sh --init --config experiment.json`. The state is stored beside the script, so subsequent calls do not reset the clock. `--deadline UNIX_TIMESTAMP` can cap the configured budget at a scheduler deadline. Expired timers report zero; the timer reports time and does not kill processes (Slurm enforces its allocation).

Rebuild `opencode.sif` using the updated `opencode.def`. The recipe extends the prepared vLLM 0.19.1 / PyTorch 2.10.0+cu129 base image and adds SacreBLEU. Both `python3 evaluate.py` and `vllm-python evaluate.py` use the same Python environment; the latter is retained for existing prompts and commands. No separate `/opt/vllm` environment or second vLLM installation is needed. The existing SIF is unchanged until rebuilt; GPU inference still needs verification on an allocated node.

Inference uses [vLLM's offline LLM API](https://docs.vllm.ai/en/latest/api/vllm/entrypoints/llm/) for local causal language models. LoRA adapters use `--base-model /models/BASE` and vLLM's `LoRARequest`; other adapter types must be merged first. Model and tokenizer paths must be local directories; remote custom code is disabled.

The evaluator expects `/data/test/DATASET/LANGUAGE_CODE.parquet` with a `text` column and, preferably, a shared sentence ID. Supply language names explicitly for the translation instruction:

```bash
vllm-python evaluate.py --model /workspace/final_model \
  --languages eng_Latn=English swe_Latn=Swedish \
  --dev-dir /data/dev --n-shot 3 \
  --output /workspace/translation_metrics.json
```

By default, it evaluates all ordered pairs of configured languages in all Parquet dataset subdirectories. To restrict the evaluation, use `--datasets bouquet` or `--directions eng_Latn:swe_Latn`. Inference uses vLLM with greedy decoding (`temperature=0`), a 256-token output limit, and the tokenizer chat template if present. `--batch-size` defaults to 64; `--tensor-parallel-size`, `--gpu-memory-utilization`, and `--max-model-len` control the engine. `--max-lora-rank` defaults to 64 for adapter evaluation. `--prompt-format auto|plain|chat` controls formatting.

Translation defaults to **3-shot** (`--n-shot 3`). Examples come exclusively from `/data/dev/DATASET/LANGUAGE_CODE.parquet`, using the same dataset and language pair as the test group. `--dev-dir` changes this root; `--seed` defaults to 0. Unique aligned pairs are sampled deterministically, reused for every test sentence in a group, and reversed for the opposite direction. Chat prompts use alternating user/assistant demonstration turns; plain prompts use labeled source/translation examples. `--n-shot 0` disables demonstrations and requires no dev files. Missing, misaligned, or insufficient dev examples cause an error rather than silently reducing the shot count. The dev files must be independently confirmed disjoint from the test set; pointing the dev path into the test directory (including symlinks) is rejected. The report records selected dev row indices and file hashes for reproducibility. Test reference translations are never added to prompts or exported.

Test and few-shot dev alignment are checked for every selected dataset/direction before loading weights. IDs (`id`, `sentence_id`, `sample_id`, or an explicit `--id-column`) must be unique and have identical sets across the two files. Without IDs, files are paired directly by row order; the supplied parallel data is expected to be aligned, and row counts must match. `--validate-only` checks test alignment and few-shot availability without model loading or metric computation.


Metrics are computed with SacreBLEU 2.5.1: `BLEU(tokenize="flores200")` and `CHRF(char_order=6, word_order=2, beta=2)` (chrF++). See the [SacreBLEU documentation](https://github.com/mjpost/sacrebleu). FLORES200 BLEU requires SentencePiece and downloads its tokenizer model on first use into SacreBLEU's cache (`SACREBLEU`, default `~/.sacrebleu`); prepopulate this cache if evaluation will run offline. Tokenizer failures are errors, with no fallback to another BLEU tokenizer.

The JSON output includes per-dataset/per-direction scores on a 0–100 scale, metric signatures, file hashes, generation settings, package versions, and an unweighted macro average across evaluated groups. Macro averages are not pooled corpus BLEU. Use fixed prompts and settings across model comparisons, and keep final test scores out of training/model selection.

Implementation checks use synthetic data and a mocked vLLM interface for prompt construction, deterministic selection, adapter requests, and metric output. Actual vLLM GPU inference must be verified in the compatible evaluation environment before a benchmark run.
