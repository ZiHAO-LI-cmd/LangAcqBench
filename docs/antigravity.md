# Antigravity CLI on Roihu

Antigravity CLI uses the native `agy` executable. This integration adds an
Apptainer definition and Slurm launcher using the shared vLLM 0.19.1 base,
experiment configs, prompts, timer, and evaluator. Both `standard` and
`train_only` reuse the existing preparation and mount rules.

Only scripts, the container definition, and documentation were prepared.
No CLI binary was downloaded, installed, or executed; no image was built,
login attempted, or job submitted. The commands below are for you to run.

## Prepare the CLI and image

Run from the repository root, with the cluster's writable `TMPDIR` set before
sourcing `env.sh`:

```bash
source env.sh
mkdir -p containers models data runs

# Explicit version, ARM64 by default for GH200. Does not execute agy.
bash scripts/download-antigravity.sh 1.4.0 arm64

# If the shared base image is not already available:
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu

apptainer build --fakeroot --bind="$TMPDIR:/tmp" \
  containers/antigravity.sif antigravity.def
AGENT=antigravity bash scripts/in-container.sh agy --version
```

The helper requires Bash, curl, Python 3 and GNU file utilities. It follows the
manifest service referenced by the [official bootstrapper](https://antigravity.google/cli/install.sh),
without running that bootstrapper or `agy install`. The Linux ARM64 manifest
reported **1.4.0** when inspected on 2026-10-16; the helper requires its version
to match your argument and stops if the current release has changed.

It checks the payload against the manifest's SHA-512, copies only the regular
`antigravity` archive member (or the flat binary), checks the ELF architecture,
and saves `agy`, `payload`, `release.json`, `version.txt`, `platform.txt`, and
`agy.sha256` in ignored `build-antigravity/`. The manifest and checksum come
from the same publisher; this is corruption detection, not independent signing.
The image verifies the binary checksum and records its Python packages.

Archive the build inputs for reproducibility. A saved manifest can be supplied
later while its upstream payload remains available:

```bash
bash scripts/download-antigravity.sh 1.4.0 arm64 /path/to/saved/release.json
```

`amd64` (also `x64`) selects the other Linux artifact. The base image, build
host and runtime must match the selected architecture. Use appropriate cluster
build resources and the supported build mode if `--fakeroot` is unavailable.
Rebuild explicitly for upgrades. The SIF's packaged binary is read-only;
upstream updater behavior inside Apptainer has not been verified.

## API key and interactive use

The supplied batch runner uses Gemini API key authentication. Official
[authentication instructions](https://antigravity.google/docs/install?tab=cli)
require both `modelProvider: gemini` in settings and `GEMINI_API_KEY` in the
process environment. A key alone does not select this provider.

For interactive use, create the provider settings once:

```bash
mkdir -p interactive/antigravity/home/.gemini/antigravity-cli
chmod 700 interactive/antigravity/home
chmod 700 interactive/antigravity/home/.gemini
chmod 700 interactive/antigravity/home/.gemini/antigravity-cli
# For a new home; merge modelProvider into existing settings if present.
cat > interactive/antigravity/home/.gemini/antigravity-cli/settings.json <<'JSON'
{
  "modelProvider": "gemini"
}
JSON
chmod 600 interactive/antigravity/home/.gemini/antigravity-cli/settings.json

# Read without putting the key into shell history or a command argument.
read -r -s -p 'Gemini API key: ' APPTAINERENV_GEMINI_API_KEY
printf '\n'
export APPTAINERENV_GEMINI_API_KEY

AGENT=antigravity bash scripts/in-container.sh agy models
AGENT=antigravity bash scripts/in-container.sh
```

`APPTAINERENV_GEMINI_API_KEY` forwards the key through `--cleanenv` as
`GEMINI_API_KEY`. The persistent home/work are `interactive/antigravity/home`
and `interactive/antigravity/work`; `RUN_DIR` overrides their parent. Settings
reside in `/home/agent/.gemini/antigravity-cli/settings.json` inside the image.
`AGENT=antigravity` selects `containers/antigravity.sif`; no command defaults
to `agy`. Explicit commands use `agy`, `python3`, `bash`, etc.

Account OAuth is an upstream alternative with SSH URL/code login and system
keyring storage. The wrapper does not provision D-Bus/keyring services or
forward host keyring sockets. OAuth in this container is unverified, and the
batch runner does not copy OAuth credentials. API-key requests use the Gemini
API and its billing/access rules, rather than a signed-in account session.

## Submit experiments

Keep the exported key in the submitting shell. Select a model slug reported
by `agy models` for your provider:

```bash
MODEL_SLUG='replace-with-a-model-slug-from-agy-models'

sbatch --export=ALL,AGENT=antigravity scripts/gpu-check.sh

bash scripts/submit-agent.sh antigravity "$MODEL_SLUG" \
  configs/smollm3-swedish.example.json high

bash scripts/submit-agent.sh antigravity "$MODEL_SLUG" \
  configs/smollm3-swedish.train-only.example.json

# After your submissions; Slurm has already captured the exported environment.
unset APPTAINERENV_GEMINI_API_KEY
```

The submission helper derives Slurm duration from `num_hours`, rounds up to a
minute, and selects `gputest` for at most 15 minutes or `gpumedium` otherwise.
Direct `sbatch scripts/antigravity.sh MODEL CONFIG [EFFORT]` keeps the launcher's
15-minute defaults. Slurm must export the submitting environment (normally
`ALL`); restricted export policies require explicit key forwarding.

The optional effort is passed as `--effort`. Recognized levels are `low`,
`medium`, `high`, `xhigh`, and `max`; availability depends on the selected
model. See the official [effort reference](https://antigravity.google/docs/cli/commands/effort/).

Each job creates an isolated home/work under
`runs/antigravity-EXPERIMENT-MODEL-JOB_ID/`, snapshots the experiment, and
creates minimal provider settings. It does not copy interactive hooks,
plugins, custom model definitions, or past sessions. The key stays in the
environment, not in generated settings or command arguments. Optional endpoint
overrides require `APPTAINERENV_GOOGLE_GEMINI_BASE_URL`.

The launcher uses [headless mode](https://antigravity.google/docs/cli/headless/)
with `--print`, `--model`, and `--output-format stream-json`, directing the
agent to read `/workspace/prompt.md`. `--print-timeout` follows `num_hours`
instead of the CLI's five-minute default. `--dangerously-skip-permissions`
permits unattended tools. Final text comes from `event=result` →
`result.response`; the CLI exit status is preserved.

Batch settings disable the nested terminal sandbox and enable access outside
the workspace so tools can use `/models`, `/data`, `/hf-cache`, `/tmp` and CUDA
inside Apptainer. Artifact review is set to `always-proceed`. These options
follow the [settings reference](https://antigravity.google/docs/settings?tab=cli).
Submit trusted experiment prompts: they can run commands and write the job
home/work and, in standard mode, the shared HF cache. Model/data mounts remain
read-only, and `train_only` retains its restricted mounts and private HF cache.

Outputs include `agent.jsonl`, `agent.err`, `work/agent-final.md` when a final
response exists, and Slurm logs. The summary reports runtime and exit status;
USD cost is unavailable because this integration does not infer billing from
token counts. Treat job homes, logs, and exported credentials as private.

## Validation

Only static syntax checks and diff review were performed. Release download
and extraction, SIF build/runtime compatibility, provider/model access, GPU
execution, and end-to-end experiments remain untested. When you choose to run
the commands, start with the image's version/import tests, the GPU check, and
one short experiment before a sweep. Review upstream references when changing
versions; the [download page](https://antigravity.google/download/?os=linux)
and current manifest can report different versions.
