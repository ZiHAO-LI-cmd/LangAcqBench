# Codex on Roihu

Codex uses the same vLLM 0.19.1 base, SacreBLEU dependency, task prompt,
experiment JSON, evaluation tool and timer as OpenCode. No Node.js installation
is required for the standalone ARM64 executable. This is a separate CLI, not
an OpenCode provider. OpenCode remains the default for existing commands.

## Build once (repository root, Roihu-GPU)

Prepare `containers/vllm-0-19-1-base.sif` as described in the main README.
Use an explicit version from https://github.com/openai/codex/releases.
The following stable release was available when this integration was prepared:

```bash
source env.sh
mkdir -p containers models data logs
bash scripts/download-codex.sh 0.155.1
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/codex.sif codex.def
AGENT=codex bash scripts/in-container.sh codex --version
```

The download helper records the selected version and a local binary checksum in
`build-codex/`. This checksum is provenance for the downloaded file, not an
independent upstream signature verification. Keep these materials with experiment
records. The SIF records its installed binary checksum and Python package list.
Nothing installs or upgrades Codex during a job. Building repacks the entire base
image; use suitable allocated resources and local temporary disk space.

## Interactive use and authentication

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
mkdir -p logs
sbatch --export=ALL,AGENT=codex scripts/gpu-check.sh

# Substitute a model ID available to your Codex account (no OpenCode provider/ prefix).
sbatch scripts/codex.sh YOUR_CODEX_MODEL configs/smollm3-swedish.example.json
```

The default job uses the repository's 15-minute gputest allocation. Override
partition/time at submission for longer experiments and keep the experiment
`num_hours` consistent with the Slurm allocation. Outputs are in
`runs/codex-JOB_ID/`: `agent.jsonl`, `agent.err`, independent `home/`, and `work/`
containing the rendered prompt, experiment JSON, timer/evaluator and
`agent-final.md` (the final assistant message).

Batch execution uses `codex exec --json` with the prompt on stdin. It skips the
Git-repository check because `/workspace` is a generated experiment directory.
It explicitly disables Codex approvals and its inner sandbox, matching the
unattended OpenCode workflow and avoiding unsupported nested sandboxing on HPC.
Run only trusted experiments. Apptainer containment is not a VM security boundary;
the agent can modify its writable home/work and the shared HF cache. Models and
datasets remain mounted read-only.

## Login refresh and concurrent jobs

The batch runner copies only `auth.json` to the job home, never previous sessions
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

Local checks cover shell syntax and mocked container/job orchestration, including
OpenCode defaults, Codex selection, prompt delivery, exit status and auth refresh.
They do not contact a model or validate a real SIF. Run the build test, login,
GPU check and one short experiment on Roihu before a sweep. `models/` and `data/`
must exist because the container entry point mounts them.

References: [Codex authentication](https://developers.openai.com/codex/auth),
[non-interactive execution](https://developers.openai.com/codex/noninteractive),
[CLI reference](https://developers.openai.com/codex/cli/reference).
