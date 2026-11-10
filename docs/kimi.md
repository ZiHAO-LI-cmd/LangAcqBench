# Kimi Code on Roihu

This integration uses the native `MoonshotAI/kimi-code` CLI. Follow the
[shared workflow](agent-common.md) for environment setup, the base image, GPU
allocation, submission rules, and logs. Azure Kimi K3 / K3.1 Pro configuration is in
[Azure models](azure-models.md#kimi-code).

## Build once

After the [shared setup](agent-common.md#prepare-the-environment):

```bash
bash scripts/downloads/download-kimi.sh 2.5.2
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/kimi.sif kimi.def
AGENT=kimi bash scripts/in-container.sh kimi --version
```

The helper downloads the official Linux ARM64 archive and companion `.sha256`
from the explicit release tag, verifies it, and extracts the executable without
running it. It records the archive, checksums, version, and platform in
`build-kimi/`. An optional second argument `x64` selects the other architecture.
The image verifies the prepared checksum and disables updates with
`KIMI_CODE_NO_AUTO_UPDATE=1`.

## Interactive use and authentication

```bash
AGENT=kimi bash scripts/in-container.sh kimi login
AGENT=kimi bash scripts/in-container.sh kimi provider list --json
AGENT=kimi bash scripts/in-container.sh
```

Complete device-code login in a browser, or use `/login` for provider setup.
Configuration is in `interactive/kimi/home/.kimi-code/config.toml`, OAuth JSON
files are under its `credentials/` directory, and task files use
`interactive/kimi/work/`. Inside the image, `KIMI_CODE_HOME` is
`/home/agent/.kimi-code`.

Use a configured model alias, such as `kimi-code/kimi-for-coding`, rather than
assuming a raw API model ID works. API-key configurations can run without OAuth
token files; environment references require `APPTAINERENV_NAME` forwarding.

## Submit experiments

```bash
sbatch --export=ALL,AGENT=kimi scripts/gpu-check.sh

bash scripts/submit-agent.sh kimi kimi-code/kimi-for-coding \
  configs/smollm3-swedish.example.json

# Requires the Azure alias and support_efforts configuration.
bash scripts/submit-agent.sh kimi kimi-k3 \
  configs/smollm3-swedish.example.json high
```

The optional fourth argument is applied by
[`set-kimi-effort.py`](../scripts/lib/set-kimi-effort.py) to the job's config copy:
it enables `[thinking]` and sets `effort`. The model must declare the requested
level in `support_efforts`; Azure Kimi K3 and K3.1 Pro use `low`, `high`, or `max`. Omission
preserves the copied config. The helper requires a regular `[thinking]` table
and rejects TOML layouts it cannot safely edit. It does not alter the interactive
configuration or add a native `--effort` flag.

## Runtime and credentials

The launcher uses `--prompt` to ask Kimi to read `/workspace/prompt.md` and
`--output-format stream-json`. Print mode supplies automatic permissions;
the launcher does not combine it with `--yolo` or `--auto`. It saves the last
assistant text without tool calls to `work/agent-final.md`, when present, and
preserves the CLI exit status. USD cost is unavailable from this integration.

The runner locks the shared `.kimi-code/batch.lock`, copies `config.toml` and
credential JSON files, and rejects another batch job using the same home.
Refreshed credentials are saved back atomically per file on exit; config
changes and sessions are not copied back. Hooks, MCP servers, or external paths
referenced by the copied config must be suitable for the batch environment.

Avoid interactive use, login/logout, or config edits while that batch home is
locked. SIGKILL or node failure can prevent token copy-back. Parallel runs
require separate authentication homes and an adapted `KIMI_AUTH_HOME`; do not
remove the lock and duplicate rotating tokens.

## Validation and references

Historical Azure API, file-read tool, and `low/high/max` request captures used
native Kimi Code **2.2.0**; see [results and logs](azure-models.md#validation).
[`test_kimi_effort.py`](../tests/test_kimi_effort.py) covers job-only effort
changes and unsupported settings. Kimi K3.1 Pro passed a streaming file-read
check and captured `max` effort forwarding with **2.5.2** on **2026-11-10**.
This check did not cover OAuth login, a full Slurm experiment, or a repeat of
the historical Kimi K3 tests.

- [Official releases](https://github.com/MoonshotAI/kimi-code/releases)
- [Configuration guide](https://moonshotai.github.io/kimi-code/en/configuration/config-files)
- [2.5.2 command reference](https://github.com/MoonshotAI/kimi-code/blob/%40moonshot-ai/kimi-code%402.5.2/docs/en/reference/kimi-command.md)
