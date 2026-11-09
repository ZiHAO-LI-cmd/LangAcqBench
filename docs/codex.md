# Codex on Roihu

Codex runs as a standalone native CLI. Follow the [shared workflow](agent-common.md)
for environment setup, the base image, GPU allocation, submission rules, and logs.
Azure deployment configuration is in [Azure models](azure-models.md#codex).

## Build once

After the [shared setup](agent-common.md#prepare-the-environment):

```bash
bash scripts/downloads/download-codex.sh 0.167.0
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/codex.sif codex.def
AGENT=codex bash scripts/in-container.sh codex --version
```

The helper downloads the complete official ARM64 package, verifies its release
checksum, and records package-file checksums under `build-codex/`. Keep the
package intact: tool execution needs its companion executables and resources.
The image build verifies package-file checksums, prints the CLI version, and
checks Python evaluation dependencies.

## Interactive use and authentication

For OpenAI login, use file-backed credentials to avoid a desktop keyring:

```bash
AGENT=codex bash scripts/in-container.sh codex \
  -c 'cli_auth_credentials_store="file"' login --device-auth
AGENT=codex bash scripts/in-container.sh codex login status
AGENT=codex bash scripts/in-container.sh
```

For API-key login, run the same entry point with
`codex -c 'cli_auth_credentials_store="file"' login --with-api-key` and supply the
key on stdin from your secret manager. API billing is separate from ChatGPT
access. Credentials live in `interactive/codex/home/.codex/auth.json`, and task
files use `interactive/codex/work/`.

For Azure, configure the [separate provider profile](azure-models.md#codex) and
select it explicitly:

```bash
AGENT=codex bash scripts/in-container.sh codex --profile azure --model gpt-6.1-terra
```

## Submit experiments

```bash
sbatch --export=ALL,AGENT=codex scripts/gpu-check.sh

# OpenAI account model ID.
bash scripts/submit-agent.sh codex YOUR_CODEX_MODEL \
  configs/smollm3-swedish.example.json high

# Azure deployment selector.
bash scripts/submit-agent.sh codex azure/gpt-6.1-terra \
  configs/smollm3-swedish.example.json max
```

The optional fourth argument sets `model_reasoning_effort` through `-c`. The
launcher accepts `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`;
model support still applies. Omitting it preserves the CLI/profile default.

## Runtime and credentials

The launcher runs `codex exec --json` with the prompt on stdin, skips the Git
repository check for the generated workspace, and disables approvals and the
inner sandbox for unattended execution. The last assistant response is saved to
`work/agent-final.md`.

| Model selector | Batch authentication |
| --- | --- |
| `azure/DEPLOYMENT` | Strips `azure/` and copies `azure.config.toml` into the job home as `config.toml` with mode `600`; uses Responses without the OAuth lock |
| Unprefixed model | Copies only `auth.json`, writes a clean file-auth config, locks the shared login, and atomically saves refreshed credentials on exit |

Unprefixed jobs using the same login fail immediately if its nonblocking lock is
held. Avoid interactive use, login, or logout with that login while a batch job
is active. SIGKILL or node failure can prevent credential copy-back. Parallel
OAuth jobs require separate authentication state and an adapted auth source;
removing the lock and duplicating rotating tokens is not sufficient. Azure jobs
have independent configuration and sessions without modifying the OAuth state.

## Validation and references

Historical Azure Responses, file-read tool, and captured effort checks used
Codex **0.163.0**, including Terra on **2026-11-02**; see
[results and logs](azure-models.md#validation). The build example selects
**0.167.0**; those historical results do not validate the newer package.

- [Authentication](https://developers.openai.com/codex/auth)
- [Non-interactive execution](https://developers.openai.com/codex/noninteractive)
- [CLI reference](https://developers.openai.com/codex/cli/reference)
- [Configuration reference](https://developers.openai.com/codex/config-reference/)
