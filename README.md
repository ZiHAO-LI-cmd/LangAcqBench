# Apptainer + OpenCode + Slurm Setup and Operation Guide

This guide covers environment setup, authentication, GPU checks, and job submission. Commands use the current cluster configuration and should be run from the repository root unless stated otherwise.

## 1. Environment and Directory Layout

The current local environment:

| Component | Configuration |
| --- | --- |
| CPU architecture | ARM64 / aarch64 |
| Container runtime | Apptainer (image build metadata records version 1.4.5) |
| OpenCode | 1.18.30 |
| PyTorch | 2.10.0+cu130 |
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
├── prompt.txt                 # Batch job prompt
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

### 3.1 Prepare the PyTorch Base Image

The local metadata for the current `pytorch-base.sif` records the following source. Pull it from an environment with access to this registry:

```bash
source env.sh
apptainer pull containers/pytorch-base.sif \
  docker://satama.csc.fi/r_installation_aida/pytorch-base:2.10_cuda13_roihu
```

Alternatively, place an existing PyTorch SIF compatible with the target node architecture at `containers/pytorch-base.sif`.

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

`opencode.def` uses the local PyTorch image, copies the binary to `/usr/local/bin/opencode`, and saves `/opt/opencode/binary.sha256` inside the image. Build tests check the OpenCode version and import PyTorch. GPU availability must be checked separately through Slurm.

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
2. Edit `prompt.txt` in the repository root to describe the task and output files.
3. Submit the job from the repository root:

```bash
mkdir -p logs
# Replace the placeholder with an actual identifier from the current model list.
MODEL_ID='provider/model'
sbatch scripts/opencode.sh "$MODEL_ID"
```

The script:

- Creates `runs/opencode-<job-id>/home` and `work`.
- Copies `auth.json` from the interactive environment into the job's own home directory.
- Writes a configuration that disables automatic updates and sets `permission: allow` so the task can execute tool operations automatically.
- Copies `prompt.txt` into the working directory and calls `opencode run --model ... --format json`.
- Enables GPU access and writes the event stream and errors to `agent.jsonl` and `agent.err`, respectively.

The prompt and credentials are copied **when the job starts executing**. Editing `prompt.txt` while a job is queued affects jobs that have not started yet. The current script copies only the prompt as task input. Add other input files to the working directory separately, for example by adding a copy step before the `srun` call in `scripts/opencode.sh`.

### Inspect Results

```text
runs/opencode-<job-id>/
├── agent.jsonl                # OpenCode JSON event stream
├── agent.err                  # OpenCode / srun error output
├── home/                      # Job-specific configuration, credentials, and sessions
└── work/
    ├── prompt.txt             # Copy of the prompt used for this job
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

## 7. Troubleshooting

| Symptom | What to check |
| --- | --- |
| `System TMPDIR Not Set` | Set a writable `TMPDIR` with enough space in the shell or job environment before sourcing `env.sh`. |
| Cannot find `env.sh` or `prompt.txt` | Run `sbatch` from the repository root and check `PROJECT_ROOT`. |
| Slurm cannot open log files | Run `mkdir -p logs` before submission and check directory write permissions. |
| Cannot find `containers/opencode.sif` | Prepare and build the image, and check the repository path in `env.sh`. |
| Batch job fails to start after login | Check that `interactive/home/.local/share/opencode/auth.json` exists. The job copies only this credential file, not the full interactive configuration. |
| Model is unavailable or access is denied | Regenerate the model list and check the `provider/model` identifier and authentication for that provider. |
| `CUDA unavailable` | Confirm that the job has a GPU allocation and `USE_GPU=1`, then inspect the GPU check logs. |
| Job times out | The default limit is 15 minutes. Adjust `#SBATCH --time` and resource requests within the partition's limits. |
| Container version is unchanged after updating the binary | The binary is copied into the SIF during the build. Rebuild the image. |

`interactive/home/` and `runs/*/home/` contain login credentials. When sharing results, select only the required work files and reports. Run outputs are excluded from Git; move code or reports that should be retained into an appropriate tracked location before committing them.
