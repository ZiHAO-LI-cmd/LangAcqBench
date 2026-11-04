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
bash scripts/download-antigravity.sh 1.4.6 arm64

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
bash scripts/download-antigravity.sh 1.4.6 arm64 /path/to/saved/release.json
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

Save the key once in the repository's ignored `.env` file:

```bash
# Run from the repository root; preserve an existing .env.
(umask 077; cp -n .env.example .env)
chmod 600 .env
${EDITOR:-vi} .env
```

Fill in the Gemini key (the same file can also hold `ANTHROPIC_API_KEY`):

```dotenv
GEMINI_API_KEY=your-gemini-api-key
```

The shared `env.sh` automatically reads this file on interactive startup and at
batch job startup, exporting `APPTAINERENV_GEMINI_API_KEY`. No manual `export`
or image rebuild is needed. Keep `.env` private; Git already ignores it, and the
loader does not copy it into job homes or the container image.

Only Anthropic/Gemini key variables, with or without the `APPTAINERENV_` prefix,
are loaded. Use one `KEY=value` per line; optional `export` and surrounding
single/double quotes are accepted. Values are literal: no shell commands,
variable expansion, escape processing, or inline comments. Use separate comment
lines. Nonempty environment values win: `APPTAINERENV_GEMINI_API_KEY`, then
`GEMINI_API_KEY`, then the file's prefixed/unprefixed values. Unset old shell
overrides when switching back to the file. To choose another file, set
`LANGACQBENCH_ENV_FILE=/absolute/path/to/keys.env` for the launch (export it
before direct `sbatch`). A missing file is allowed for manual-key workflows.

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

After filling in `.env`, select a model slug reported by `agy models` for your
provider:

```bash
MODEL_SLUG='replace-with-a-model-slug-from-agy-models'

sbatch --export=ALL,AGENT=antigravity scripts/gpu-check.sh

bash scripts/submit-agent.sh antigravity "$MODEL_SLUG" \
  configs/smollm3-swedish.example.json high

bash scripts/submit-agent.sh antigravity "$MODEL_SLUG" \
  configs/smollm3-swedish.train-only.example.json
```

The submission helper derives Slurm duration from `num_hours`, rounds up to a
minute, and selects `gputest` for at most 15 minutes or `gpumedium` otherwise.
Direct `sbatch scripts/antigravity.sh MODEL CONFIG [EFFORT]` keeps the launcher's
15-minute defaults. Jobs read `.env` at startup, so keep the file available on
the shared filesystem until queued jobs start. Edits affect future startups;
running jobs retain their loaded key. If you use exported keys or a custom
`LANGACQBENCH_ENV_FILE`, Slurm must forward those variables (normally `ALL`).

The optional effort is passed as `--effort`. Recognized levels are `low`,
`medium`, `high`, `xhigh`, and `max`; availability depends on the selected
model. See the official [effort reference](https://antigravity.google/docs/cli/commands/effort/).

For Gemini 4 Argon, CLI **1.4.6** accepts `low`, `medium`, and `high`:

```bash
bash scripts/submit-agent.sh antigravity gemini-4-argon \
  configs/smollm3-swedish.train-only.example.json high
```

`REASONING_OR_EFFORT_LEVEL` in the helper's usage is the optional fourth
positional argument, not an environment variable. The helper forwards it as
the third argument to `antigravity.sh`, which invokes
`agy --model gemini-4-argon --effort high`. For this model, `xhigh` and `max`
pass the launcher's generic level check but are rejected by the CLI. Omit the
fourth argument to leave effort selection to the CLI; with fresh batch settings,
the bare `gemini-4-argon` model selected `medium` in the validation below.
When using a suffixed model such as `gemini-4-argon-high`, keep the fourth
argument consistent with that suffix or omit it. A conflicting level is rejected
by the CLI; prefer the bare model name when selecting effort separately.

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

The initial integration received static syntax checks and diff review.
On **2026-10-23**, the updated container reported CLI **1.4.6**, and
`agy models` listed the Argon low/medium/high variants. Read-only `/effort`
commands confirmed these three levels and rejected `xhigh` and `max`.

The unchanged submission, batch, preparation, and container scripts were then
executed in an isolated fixture with simulated `sbatch`/`srun`, the real SIF
and CLI, a dummy API key, and a local Gemini-compatible HTTP endpoint. Captured
requests to `models/gemini-4-argon:streamGenerateContent` contained:

| Fourth argument | `generationConfig.thinkingConfig.thinkingLevel` | Result |
| --- | --- | --- |
| `low` | `LOW` | Passed |
| `medium` | `MEDIUM` | Passed |
| `high` | `HIGH` | Passed |
| omitted, bare model | `MEDIUM` | Passed with no `--effort` flag |
| `high` or omitted, model `gemini-4-argon-high` | `HIGH` | Passed |
| `low`, model `gemini-4-argon-high` | No generation request | Rejected: conflicting model suffix and effort |
| `xhigh` / `max` | No generation request | Rejected by CLI |
| `invalid` | No generation request | Rejected by batch script |

Successful cases also produced the expected `work/agent-final.md` from the
local endpoint's response. The persistent interactive settings remained
unchanged. Local evidence and the replay script are under
`runs/antigravity-effort-hmibt34l/` (ignored by Git).

These checks verify argument forwarding and actual HTTP request construction.
They did not submit Slurm jobs, enable GPUs, or call Google's inference API;
remote key/model access and full training experiments were not tested.
Review upstream references when changing versions; the
[download page](https://antigravity.google/download/?os=linux) and current
manifest can report different versions.
