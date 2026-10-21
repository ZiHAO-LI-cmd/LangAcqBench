# Codex on Roihu

Codex uses the same vLLM 0.19.1 base, SacreBLEU dependency, task prompt,
experiment JSON, evaluation tool and timer as OpenCode. No Node.js installation
is required for the standalone ARM64 executable. This is a separate CLI, not
an OpenCode provider. OpenCode remains the default for existing commands.

## Build once (repository root, Roihu-GPU)

Prepare `containers/vllm-0-19-1-base.sif` as described in the
[OpenCode guide](opencode.md#build-once).
Use an explicit version from https://github.com/openai/codex/releases.
The following version was validated in the Azure retest on 2026-10-22:

```bash
source env.sh
mkdir -p containers models data runs
bash scripts/download-codex.sh 0.163.0
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/codex.sif codex.def
AGENT=codex bash scripts/in-container.sh codex --version
```

The download helper fetches both `codex` and `codex-code-mode-host` from the same
release and records the selected version and local binary checksums in
`build-codex/`. This checksum is provenance for the downloaded file, not an
independent upstream signature verification. Keep these materials with experiment
records. The SIF records both installed binary checksums and the Python package list.
Its build test checks that the code-mode host can load; copying only the main
`codex` binary is insufficient for tool execution.
Nothing installs or upgrades Codex during a job. Building repacks the entire base
image; use suitable allocated resources and local temporary disk space.

## Interactive use and authentication

For Azure `gpt-6-astra`, `gpt-6.1-sol`, and `gpt-6-luna`, use the saved Azure
profile and API key described in [Azure models](azure-models.md#codex). The existing
base configuration and OpenAI login are preserved. Azure interactive use is:

```bash
AGENT=codex bash scripts/in-container.sh codex --profile azure --model gpt-6.1-sol
```

The login instructions below apply to the original OpenAI authentication path.

```bash
# File-backed auth avoids depending on a desktop keyring in the container.
AGENT=codex bash scripts/in-container.sh codex \
  -c 'cli_auth_credentials_store="file"' login --device-auth
AGENT=codex bash scripts/in-container.sh codex login status
AGENT=codex bash scripts/in-container.sh
```

For API-key login instead, use the same container entry point with
`codex -c 'cli_auth_credentials_store="file"' login --with-api-key`, supplying
the key on stdin from your secret manager. Never put a key in a command argument,
image, committed config or prompt. API billing is separate from ChatGPT access.

Codex defaults to `interactive/codex/home` and `interactive/codex/work`.
Its credentials are stored in `interactive/codex/home/.codex/auth.json`.
The existing OpenCode home at `interactive/home` is unchanged. Explicit RUN_DIR
still overrides the default; `AGENT=codex` selects the image even when running
`python3` or `bash` rather than the Codex command.

## GPU and batch jobs

```bash
mkdir -p runs
sbatch --export=ALL,AGENT=codex scripts/gpu-check.sh

# Substitute a model ID available to your Codex account (no OpenCode provider/ prefix).
scripts/submit-agent.sh codex YOUR_CODEX_MODEL configs/smollm3-swedish.example.json

# Optional fourth argument: reasoning effort.
scripts/submit-agent.sh codex YOUR_CODEX_MODEL configs/smollm3-swedish.example.json high

# Azure: the launcher selects the saved Azure profile and strips azure/.
scripts/submit-agent.sh codex azure/gpt-6.1-sol configs/smollm3-swedish.example.json max
```

The optional effort argument sets `model_reasoning_effort` via Codex's `-c` flag.
The launcher accepts `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`;
the selected model must support the requested level. Omitting it preserves the
CLI/model default. See the [Codex configuration reference](https://developers.openai.com/codex/config-reference/).

The submit helper sets the Slurm time from `num_hours`, rounded up to a whole
minute. It selects `gputest` for at most 15 minutes and `gpumedium` for longer
jobs. Direct `sbatch scripts/codex.sh ...` still uses the script's 15-minute
`gputest` defaults. Outputs are in
`runs/codex-EXPERIMENT-MODEL-JOB_ID/`, with matching
`runs/codex-EXPERIMENT-MODEL-JOB_ID/codex-EXPERIMENT-MODEL-JOB_ID.{out,err}`. `EXPERIMENT` is the config
filename without `.json`; names are lowercased and shortened if needed. Each
run contains `agent.jsonl`, `agent.err`, independent `home/`, and `work/`
containing the rendered prompt, experiment JSON, timer/evaluator and
`agent-final.md` (the final assistant message).

Batch execution uses `codex exec --json` with the prompt on stdin. It skips the
Git-repository check because `/workspace` is a generated experiment directory.
It explicitly disables Codex approvals and its inner sandbox, matching the
unattended OpenCode workflow and avoiding unsupported nested sandboxing on HPC.
Run only trusted experiments. Apptainer containment is not a VM security boundary;
the agent can modify its writable home/work and the shared HF cache. Models and
datasets remain mounted read-only.

## Authentication and concurrent jobs

Azure-prefixed jobs copy the self-contained
`interactive/codex/home/.codex/azure.config.toml` profile to the private job home
as `config.toml` with mode `600`. They use the saved Azure key and Responses API,
without copying or refreshing OAuth credentials or taking the shared OAuth lock.
Each Azure job has independent configuration and session state.

For unprefixed models, the batch runner copies only `auth.json` to the job home, never previous sessions
or arbitrary interactive settings. It writes a clean file-auth configuration.
On exit, it atomically saves refreshed credentials back to the interactive login,
while retaining the job's separate session history. A nonblocking `flock` prevents
two batch jobs from consuming/overwriting the same rotating credentials: the
second job fails explicitly instead of waiting on a paid GPU allocation.

Do not log in/out or run interactive Codex using this login while a batch job is
active (interactive commands do not acquire that lock). SIGKILL/node failure
cannot run the exit handler; if login becomes invalid, log in again. For parallel
experiments, provision separate authentication state and adapt the auth source;
do not remove the lock and duplicate an OAuth refresh token across jobs.

## Validation and limitations

The initial local checks covered shell syntax and mocked container/job orchestration, including
OpenCode defaults, Codex selection, prompt delivery, exit status and auth refresh.
The Azure integration additionally passed real Responses API requests and Codex
file-read tool checks for all three deployments, plus captured `max` effort
requests. The 2026-10-22 retest confirmed Codex **0.163.0** works for all three
models at `max`, with no fallback metadata warnings. The earlier Sol/Luna
warnings from 0.155.1, current results, and offline authentication-routing tests
are documented in
[Azure models](azure-models.md#validation). GPU jobs and full experiments remain
untested. Run the build test, authentication checks, GPU check, and one short
experiment before a sweep. `models/` and `data/`
must exist because the container entry point mounts them.

References: [Codex authentication](https://developers.openai.com/codex/auth),
[non-interactive execution](https://developers.openai.com/codex/noninteractive),
[CLI reference](https://developers.openai.com/codex/cli/reference).
