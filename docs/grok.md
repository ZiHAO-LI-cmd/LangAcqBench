# Grok Build on Roihu

Grok Build uses the native `grok` executable. This integration uses the shared
vLLM 0.19.1 base, experiment configuration, prompt renderer, timer and evaluator.
Both `standard` and `train_only` follow the existing preparation and mount rules.
Select it with `AGENT=grok` and the unified submission helper's `grok` argument.

The initial integration prepared scripts, a container definition and documentation.
The user has since installed the container. Provider configuration and runtime
validation are recorded in [Azure models](azure-models.md#grok-build).

## Prepare the CLI and image

Run from the repository root with the cluster's writable `TMPDIR` already set:

```bash
source env.sh
mkdir -p containers models data runs

# Explicit version; ARM64 is the default for GH200. Does not execute grok.
bash scripts/download-grok.sh 1.0.62 arm64

# If the shared base image is not already available:
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu

apptainer build --fakeroot --bind="$TMPDIR:/tmp" \
  containers/grok.sif grok.def
AGENT=grok bash scripts/in-container.sh grok --version
AGENT=grok bash scripts/in-container.sh grok --help
```

The official [release installation instructions](https://github.com/xai-org/grok-build#installing-the-released-binary)
link to the [bootstrapper](https://x.ai/cli/install.sh). The helper follows its
versioned Linux artifact locations, trying `https://x.ai/cli/` first and its
official GCS fallback second. It fetches the flat uncompressed binary directly;
it does not run the bootstrapper, create host PATH links, edit shell startup
files or execute the binary. The [stable pointer](https://x.ai/cli/stable)
reported **1.0.62** when inspected on 2026-10-21. The helper never substitutes
the current stable release for the requested version.

Requirements are Bash, curl, Python 3 and GNU file utilities. Architecture
aliases `arm64`/`aarch64` select `linux-aarch64`;
`amd64`/`x64`/`x86_64` select `linux-x86_64`. The binary's ELF class, byte order
and machine architecture are checked without running it. The base image,
build host and runtime must match the selected architecture. Use the cluster's
supported build mode if `--fakeroot` is unavailable.

The helper saves `grok`, `version.txt`, `platform.txt`, `url.txt` and
`grok.sha256` under ignored `build-grok/`. Archive these inputs to reproduce
the image. The official bootstrapper does not supply a release digest in its
download flow; the recorded local SHA-256 detects subsequent changes to the
build input, and is not an upstream authenticity check. If you have a trusted
SHA-256 for that exact version and architecture, supply it as a third argument:

```bash
EXPECTED_SHA256='replace-with-the-trusted-64-character-hex-digest'
bash scripts/download-grok.sh 1.0.62 arm64 "$EXPECTED_SHA256"
```

The image verifies the saved checksum, records installed Python packages, and
its build test runs `grok --version` and checks Python imports. Auto-updates
are disabled through `GROK_DISABLE_AUTOUPDATER=1`; rebuild explicitly to upgrade.

## Authentication and interactive use

For the default xAI endpoint, the batch launcher can use `XAI_API_KEY`, documented in the official
[authentication guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md).
Forward it through Apptainer's `--cleanenv` with `APPTAINERENV_XAI_API_KEY`:

```bash
# Read without placing the key in shell history or command arguments.
read -r -s -p 'xAI API key: ' APPTAINERENV_XAI_API_KEY
printf '\n'
export APPTAINERENV_XAI_API_KEY

AGENT=grok bash scripts/in-container.sh
```

The default command is `grok`, image is `containers/grok.sif`, and persistent
interactive home/work are `interactive/grok/home` and `interactive/grok/work`.
`RUN_DIR` overrides their parent. Inside the container, Grok configuration and
credentials live under `/home/agent/.grok/`.

For interactive account login, the upstream alternative for SSH is:

```bash
AGENT=grok bash scripts/in-container.sh grok login --device-auth
```

Stored session tokens take precedence over `XAI_API_KEY`. The supplied batch
launcher creates a fresh home and copies the persistent interactive `config.toml`,
including model definitions and saved API keys. Configuration may also reference
hooks or plugins; review configured commands before batch use. It does not copy
interactive `auth.json`, session directories or plugin files. Interactive OAuth
authentication is not reused for batch jobs. Plain host
`XAI_API_KEY` alone is not forwarded by this wrapper's `--cleanenv`. Keep job
homes and logs private, as with the other agents.

An explicit `GROK_CONFIG_FILE` overrides the persistent configuration; relative
paths resolve against `SLURM_SUBMIT_DIR`. Without either an explicit or
persistent config, the launcher generates minimal settings for the default
xAI endpoint.

Azure model configuration, credentials and usage are documented in
[Azure models: Grok Build](azure-models.md#grok-build).

## Submit experiments

Use the image's `--help` to verify the documented flags for your pinned release.
In the interactive TUI, inspect `/model` and `/effort` and select a model ID and
effort supported by your installed release and credentials. The API's model
list alone does not establish CLI support. Keep the API key exported in the
submitting shell:

```bash
MODEL_ID='replace-with-a-model-id-from-the-installed-grok-model-menu'

sbatch --export=ALL,AGENT=grok scripts/gpu-check.sh

bash scripts/submit-agent.sh grok "$MODEL_ID" \
  configs/smollm3-swedish.example.json high

bash scripts/submit-agent.sh grok "$MODEL_ID" \
  configs/smollm3-swedish.train-only.example.json

# After submission, Slurm has captured the exported environment.
unset APPTAINERENV_XAI_API_KEY
```

The optional effort passes `--reasoning-effort` and accepts the canonical
levels `none`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`. A model
supports only the levels advertised by its own menu; omit the argument to use
the CLI default. Model-specific named effort options are not mapped by this
launcher. See the official
[headless reference](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/14-headless-mode.md).

The shared submission helper derives duration from `num_hours`, rounds up to
a minute, and selects `gputest` for at most 15 minutes or `gpumedium` otherwise.
Direct `sbatch scripts/grok.sh MODEL CONFIG [EFFORT]` retains the launcher's
15-minute defaults. Slurm must export the submitting environment (normally
`ALL`); restrictive export policies require explicit key forwarding.

Each job uses its own `runs/grok-EXPERIMENT-MODEL-JOB_ID/home` and `work`, with
a snapshot of the experiment and rendered prompt. The launcher reads that
prompt with `--prompt-file /workspace/prompt.md` and uses
`--output-format streaming-messages-json`. It disables automatic updates and
enables unattended tools using `--yolo --sandbox off`. The shared timer and
Slurm allocation bound the experiment. Permissions and nested sandbox behavior
are described in the official
[headless guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/14-headless-mode.md)
and [sandbox guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/18-sandbox.md).

Unattended tools can write the job home/work, temporary space and, in standard
mode, the shared HF cache. Model/data mounts remain read-only. `train_only`
retains its restricted training mounts and private HF cache. Submit trusted
experiment prompts, as for the existing agent launchers.

## Outputs and validation

- `agent.jsonl`: streamed Messages-format events, including tool activity and
  a terminal `type: result` record when the CLI completes.
- `agent.err`: CLI and runtime diagnostics.
- `work/agent-final.md`: the terminal result's string `result` field, when present.
- Slurm logs: job runtime, exit status and the agent-reported USD cost when
  the terminal result includes `total_cost_usd`. Missing cost is reported as
  unavailable; it is never inferred from tokens or treated as zero.

The launcher preserves the CLI exit status. The official cost field covers
the prompt's reported model usage and excludes GPU cost; incomplete or absent
upstream billing information can leave it unset.

The initial integration passed static Bash/Python syntax checks, container
shell-section checks, documentation example syntax checks and diff review.
Provider-specific runtime validation is recorded in
[Azure models](azure-models.md#grok-build). GPU execution and full experiments
remain untested. The flag and event descriptions were checked against the
official source-tree documentation; inspect your pinned binary's help before
running a short experiment or starting a sweep.
