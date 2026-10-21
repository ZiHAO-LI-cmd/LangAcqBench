# Kimi Code on Roihu

Kimi Code runs as a separate CLI using the same vLLM 0.19.1 base image,
experiment configurations, prompt templates, timer, and translation evaluator
as the other agents. The integration targets the native **Kimi Code 2.2.0**
release (`MoonshotAI/kimi-code`), with ARM64 as the download default for Roihu's
GH200 nodes. It does not use the older Python `kimi-cli` distribution.

For the verified Azure `FW-Kimi-K3` connection, configuration, and API examples,
see [Azure models](azure-models.md).

The initial integration was checked statically. The separate Azure guide above
records subsequent container and model-call verification. Build and Slurm
commands below are operating instructions, not records of completed jobs.

## Prepare and build

Run from the repository root. Set `TMPDIR` to a writable temporary directory
provided by the cluster before sourcing `env.sh`.

```bash
source env.sh
mkdir -p containers models data runs

# Explicit version; downloads and verifies files without executing Kimi.
bash scripts/download-kimi.sh 2.2.0

# Obtain the shared base image if it is not already present.
apptainer pull containers/vllm-0-19-1-base.sif \
  docker://satama.csc.fi/r_installation_aida/vllm:0.19.1_cuda12.9_roihu

apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/kimi.sif kimi.def
AGENT=kimi bash scripts/in-container.sh kimi --version
```

The helper requires Bash, curl, Python 3, and standard GNU file utilities. It
fetches the official `kimi-code-linux-arm64.zip` and companion `.sha256` from
the explicit release tag `@moonshot-ai/kimi-code@2.2.0`. It verifies the archive
against that checksum before extracting only the `kimi` executable. No Node.js,
uv, pip installation, or upstream installer is needed to prepare the CLI.
The image build separately installs SacreBLEU, as the other agent images do.

`build-kimi/` retains the archive, upstream checksum, binary, local binary
checksum, version, and platform. Checksums from the same release detect file
corruption; they are not independent signature verification. The image records
the version/platform, verifies the prepared binary checksum, and saves its
Python package list. Auto-update checks and installation are disabled with
`KIMI_CODE_NO_AUTO_UPDATE=1`. Upgrades require an explicit download and rebuild.

For a different matching Linux environment, the helper accepts an explicit
architecture: `bash scripts/download-kimi.sh 2.2.0 x64`. This only selects the
CLI artifact; the base image and build/runtime host must also match. Build the
Roihu ARM64 image on appropriate allocated resources with sufficient temporary
space. If `--fakeroot` is unavailable, use the cluster's supported build mode.

## Login and interactive use

```bash
# Device-code OAuth login: open the printed URL in your browser.
AGENT=kimi bash scripts/in-container.sh kimi login

# Inspect configured provider/model aliases without invoking a model.
AGENT=kimi bash scripts/in-container.sh kimi provider list --json

# Start the terminal UI. /login also offers provider setup.
AGENT=kimi bash scripts/in-container.sh
```

The default persistent home is `interactive/kimi/home`, and the workspace is
`interactive/kimi/work`. Configuration lives in
`interactive/kimi/home/.kimi-code/config.toml`; OAuth tokens live under its
`credentials/` directory. `KIMI_CODE_HOME` is set inside the image to
`/home/agent/.kimi-code`. Setting `RUN_DIR` overrides the home/work location,
as with the other agents. `AGENT=kimi` selects `containers/kimi.sif` even for
commands such as `python3` or `bash`.

Use the model alias present in your configuration, for example
`kimi-code/kimi-for-coding`, rather than assuming a raw API model ID works.
For an API-key provider, configure it using the interactive `/login` flow or
the official configuration guide. The runner copies `config.toml` and OAuth
credential JSON files into each job; it also supports configurations with a
saved API key and no OAuth token files. Treat the configuration and run homes
as secrets. Provider configuration referencing environment variables needs
those variables forwarded using `APPTAINERENV_<NAME>` because the wrapper uses
`--cleanenv`; do not put keys in committed configs, prompts, or command arguments.

## GPU and batch experiments

```bash
mkdir -p runs
sbatch --export=ALL,AGENT=kimi scripts/gpu-check.sh

scripts/submit-agent.sh kimi kimi-code/kimi-for-coding \
  configs/smollm3-swedish.example.json

# Override thinking effort for this job only.
scripts/submit-agent.sh kimi kimi-k3 configs/smollm3-swedish.example.json high
```

The submission helper uses `num_hours` to set the Slurm time, rounded up to a
whole minute. It selects `gputest` for up to 15 minutes and `gpumedium` for longer
jobs. Direct `sbatch scripts/kimi.sh MODEL_ALIAS CONFIG` retains the script's
15-minute `gputest` defaults. The optional fourth argument overrides thinking
effort for that job. The launcher edits only the copied job `config.toml`, sets
`[thinking].enabled = true`, and writes the requested `[thinking].effort` before
starting Kimi. Omitting it preserves the copied configuration unchanged.

Kimi 2.2.0 has no `--effort` CLI flag. The helper
[`scripts/set-kimi-effort.py`](../scripts/set-kimi-effort.py) uses the container's
Python 3.12 and `tomllib`; no additional package or image rebuild is needed.
The selected model must explicitly declare `support_efforts`, and the requested
value must be in that list. For Azure Kimi K3, use `low`, `high`, or `max`.
The launcher rejects invalid or unsupported levels before model execution.
Use a plain `[thinking]` table with bare `enabled` / `effort` keys; the helper
rejects layouts it cannot safely edit and checks that all other parsed settings
are preserved. It never writes the override back to the interactive home.
`kimi-k3` in the example must be an alias defined in your configuration.

Each job gets `runs/kimi-EXPERIMENT-MODEL-JOB_ID/` with isolated `home/` and
`work/`, full JSONL output in `agent.jsonl`, stderr in `agent.err`, and matching
Slurm `.out`/`.err` files. The workspace contains the snapshotted experiment,
rendered `prompt.md`, timer, and evaluation tools appropriate to the experiment
mode. Both `standard` and `train_only` use the existing shared preparation and
mount rules. Models and datasets are mounted read-only; `models/` and `data/`
must exist before using the container entry point.

The launcher uses `kimi --model ALIAS --prompt ... --output-format stream-json`
and instructs Kimi to read `/workspace/prompt.md`. It avoids assuming stdin
prompt support or placing the full experiment prompt in a command argument.
In 2.2.0, print mode already runs with automatic permissions; combining it with
`--yolo` or `--auto` is invalid. Only submit trusted experiments: the CLI can
execute tools and modify writable job directories and, in standard mode, the
shared HF cache. Apptainer containment is not a VM security boundary.

The last assistant text message without tool calls is saved to
`work/agent-final.md`, if one was emitted. The CLI's exit status is preserved;
an interrupted run may have no final answer. The shared summary reports elapsed
time and exit status; cost remains unavailable because this integration does
not derive billing from Kimi's message stream.

## Credentials and concurrent runs

The runner acquires a nonblocking lock at
`interactive/kimi/home/.kimi-code/batch.lock` before copying configuration and
tokens. Another Kimi batch job using this home fails immediately. Job sessions,
plugins, and previous workspace state are not copied. The copied configuration
can still reference hooks, MCP servers, or external files: ensure it is suitable
for unattended experiments and contains no paths requiring the interactive home.

On normal exit, refreshed credential JSON files are saved back atomically per
file, under the same lock. Job configuration changes are not copied back. Do
not log in/out, edit the shared configuration, or run interactive Kimi with that
login while a batch job is active; interactive commands do not acquire this
batch lock. SIGKILL and node failure cannot save refreshed tokens, so a fresh
login may be needed afterward. For concurrent experiments, provision separate
authentication homes and adapt `KIMI_AUTH_HOME` in a local launcher; do not remove
the lock and duplicate rotating OAuth tokens across jobs.

## Validation and references

The initial integration received static shell/Python syntax checks and diff
review. Subsequent Azure API, container CLI, and tool-call checks are recorded in
[Azure models](azure-models.md); they do not validate OAuth login, GPU access,
or full Slurm experiments. Run the build's test, configure authentication, and
try one short experiment before a sweep. Other versions may change asset names,
configuration paths, permission behavior, or JSONL format; review their official
references before upgrading.

The effort override also has 12 automated checks in
[`tests/test_kimi_effort.py`](../tests/test_kimi_effort.py), including launcher
execution with local Slurm/container substitutes. Real Kimi 2.2.0 request
capture verifies `low` / `high` / `max` after applying the helper. These checks
do not submit jobs or allocate GPUs. A further real Azure Kimi Code call using
the helper's `max` override returned `KIMI_EFFORT_MAX_OK` with exit status 0 and
empty stderr; the interactive config was verified unchanged.

- [Official releases](https://github.com/MoonshotAI/kimi-code/releases)
- [2.2.0 command reference](https://github.com/MoonshotAI/kimi-code/blob/%40moonshot-ai/kimi-code%402.2.0/docs/en/reference/kimi-command.md)
- [Configuration guide](https://moonshotai.github.io/kimi-code/en/configuration/config-files)
- [2.2.0 native packaging](https://github.com/MoonshotAI/kimi-code/blob/%40moonshot-ai/kimi-code%402.2.0/apps/kimi-code/scripts/native/package.mjs)
