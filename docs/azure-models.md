# Azure Models: Configuration, Usage, and Validation

This guide covers Azure model configuration, interactive use, Slurm submission,
and validation results for OpenCode, Kimi Code, and Grok Build on Roihu. The
records are current as of **2026-10-21** and apply to **OpenCode 1.19.2**,
**Kimi Code 2.2.0 (native CLI)**, and **Grok Build 1.0.62**.

- [Deployments and model identifiers](#model-catalog)
- [Persistent configuration and credentials](#credentials)
- [Reasoning effort parameters](#effort)
- [OpenCode](#opencode) · [Kimi Code](#kimi-code) · [Grok Build](#grok-build)
- [Direct API calls](#direct-api)
- [Validation results and logs](#validation) · [Troubleshooting](#troubleshooting)

<a id="model-catalog"></a>

## Deployments and Model Identifiers

All five deployments share the following endpoint:

| Parameter | Value |
| --- | --- |
| API base URL | `https://lab-swe-resource.services.ai.azure.com/openai/v1` |
| Chat Completions URL | `https://lab-swe-resource.services.ai.azure.com/openai/v1/chat/completions` |
| Authentication | `Authorization: Bearer <API_KEY>`, verified |

| Model | Azure deployment / API `model` | TPM | RPM |
| --- | --- | --- | --- |
| Kimi K3 | `FW-Kimi-K3` | 250,000 | 250 |
| DeepSeek V4.1 Flash | `DeepSeek-V4.1-Flash` | 1,000,000 | 1,000 |
| GLM 5.3 | `FW-GLM-5.3` | 125,000 | 125 |
| GLM 5.3 Flash | `FW-GLM-5.3-Flash` | 125,000 | 125 |
| Grok 4.7 | `grok-4.7` | 10,000,000 | 10,000 |

| Model | OpenCode identifier | Kimi Code alias | Grok Build alias |
| --- | --- | --- | --- |
| Kimi K3 | `azure-kimi/kimi-k3` | `kimi-k3` | — |
| DeepSeek V4.1 Flash | `azure-deepseek/deepseek-v4.1-flash` | — | — |
| GLM 5.3 | `azure-glm/glm-5.3` | — | — |
| GLM 5.3 Flash | `azure-glm/glm-5.3-flash` | — | — |
| Grok 4.7 | — | — | `azure-grok-4.7` |

The table lists the combinations currently configured and validated. API requests
use the Azure deployment name; local configuration maps each CLI alias to that
deployment. Set the client base URL to `/openai/v1`; the client appends
`/chat/completions`. These examples use the Azure v1 API and need no `api-version`
parameter. See the [Azure v1 API documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/api-version-lifecycle?tabs=key).

TPM/RPM values are user-provided deployment quotas. They have not been load-tested
or configured as client rate limits. They do not describe context length, and
each parallel job does not receive its own quota.

<a id="credentials"></a>

## Persistent Configuration and Credentials

The existing interactive configurations store API keys locally, so launching
through the repository's container wrapper requires no new login. Configuration
files and backups are under the Git-ignored `interactive/` directory, with file
permissions set to `600`. Examples in this guide use environment-variable
references for portability and sharing; they contain no real credentials.

| Agent | Persistent host configuration | Container configuration |
| --- | --- | --- |
| OpenCode | `interactive/home/.config/opencode/opencode.json` | `/home/agent/.config/opencode/opencode.json` |
| Kimi Code | `interactive/kimi/home/.kimi-code/config.toml` | `/home/agent/.kimi-code/config.toml` |
| Grok Build | `interactive/grok/home/.grok/config.toml` | `/home/agent/.grok/config.toml` |

Interactive sessions and Kimi/Grok batch jobs reuse the saved configuration and
keys. OpenCode batch jobs require an [additional provider override](#opencode-batch).
For direct API calls or the environment-variable examples, first run:

```bash
read -r -s -p 'Azure API key: ' AZURE_API_KEY
printf '\n'
export AZURE_API_KEY

# in-container.sh uses --cleanenv; forward the key explicitly to Apptainer.
export APPTAINERENV_AZURE_API_KEY="$AZURE_API_KEY"
```

`in-container.sh` uses `--cleanenv`: the host's `AZURE_API_KEY` is used for direct
API calls, while `APPTAINERENV_AZURE_API_KEY` forwards it into the container.
Set these again in each new shell when using environment-variable authentication.
The variable name must match the configuration. Older configurations referencing
`AZURE_KIMI_API_KEY` still need `APPTAINERENV_AZURE_KIMI_API_KEY`.

For container, `TMPDIR`, and directory setup, see [OpenCode](opencode.md),
[Kimi Code](kimi.md), and [Grok Build](grok.md).

<a id="effort"></a>

## Reasoning Effort: `REASONING_OR_EFFORT_LEVEL`

This is the submission helper's optional fourth **positional argument**. There
is no need to set an environment variable with that name:

```text
scripts/submit-agent.sh AGENT MODEL EXPERIMENT_CONFIG [REASONING_OR_EFFORT_LEVEL]
```

| Agent / model | Configured and validated levels | How the argument is passed | When omitted |
| --- | --- | --- | --- |
| OpenCode: Kimi, DeepSeek, GLM | `low`, `high`, `max` | `--variant LEVEL` → `variants.LEVEL.reasoningEffort` → API `reasoning_effort` | Uses model settings; currently `high` for Kimi K3 |
| Kimi Code: Kimi K3 | `low`, `high`, `max` | Enables `[thinking]` and sets `effort` in the job's configuration copy | Preserves the original configuration; `high` in the example |
| Grok Build: Grok 4.7 | `low`, `medium`, `high`, `xhigh` | `--reasoning-effort LEVEL` → API `reasoning_effort` | Configured default is `high` |

OpenCode needs `variants`, Kimi Code needs `support_efforts`, and Grok Build
needs `reasoning_efforts`. Without those definitions, a CLI may exit successfully
without sending the effort field. See [validation results](#validation) for the
observed failures and fixes. Use `xhigh` for Grok 4.7; substituting `max` returns
HTTP 400 from this Azure deployment.

<a id="opencode"></a>

## OpenCode 1.19.2

### Persistent Configuration

Repository paths are listed in the [configuration table](#credentials). A native
installation reads `~/.config/opencode/opencode.json` by default. The current
default model is `azure-kimi/kimi-k3`.

The standalone example below covers all four models. Merge the provider/model
tables into an existing configuration while preserving other connections. If
`opencode.jsonc` exists, check it for conflicting settings as well:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "model": "azure-kimi/kimi-k3",
  "provider": {
    "azure-kimi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Azure Kimi",
      "options": {
        "baseURL": "https://lab-swe-resource.services.ai.azure.com/openai/v1",
        "apiKey": "{env:AZURE_API_KEY}"
      },
      "models": {
        "kimi-k3": {
          "id": "FW-Kimi-K3",
          "name": "Kimi K3",
          "options": {"reasoningEffort": "high"},
          "variants": {
            "low": {"reasoningEffort": "low"},
            "high": {"reasoningEffort": "high"},
            "max": {"reasoningEffort": "max"}
          }
        }
      }
    },
    "azure-deepseek": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Azure DeepSeek",
      "options": {
        "baseURL": "https://lab-swe-resource.services.ai.azure.com/openai/v1",
        "apiKey": "{env:AZURE_API_KEY}"
      },
      "models": {
        "deepseek-v4.1-flash": {
          "id": "DeepSeek-V4.1-Flash",
          "name": "DeepSeek V4.1 Flash (Azure)",
          "variants": {
            "low": {"reasoningEffort": "low"},
            "high": {"reasoningEffort": "high"},
            "max": {"reasoningEffort": "max"}
          }
        }
      }
    },
    "azure-glm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Azure GLM",
      "options": {
        "baseURL": "https://lab-swe-resource.services.ai.azure.com/openai/v1",
        "apiKey": "{env:AZURE_API_KEY}"
      },
      "models": {
        "glm-5.3": {
          "id": "FW-GLM-5.3",
          "name": "GLM 5.3 (Azure)",
          "variants": {
            "low": {"reasoningEffort": "low"},
            "high": {"reasoningEffort": "high"},
            "max": {"reasoningEffort": "max"}
          }
        },
        "glm-5.3-flash": {
          "id": "FW-GLM-5.3-Flash",
          "name": "GLM 5.3 Flash (Azure)",
          "variants": {
            "low": {"reasoningEffort": "low"},
            "high": {"reasoningEffort": "high"},
            "max": {"reasoningEffort": "max"}
          }
        }
      }
    }
  }
}
```

Keys in the `models` table are local aliases; `id` is the deployment name sent
to the API. When `options.apiKey` explicitly references an environment variable,
these providers need no `auth login`.

All four models define `low`, `high`, and `max` variants. Kimi K3 has a model-level
default of `high`; DeepSeek and GLM have no added model-level effort default or
unverified context limit. See [custom providers](https://opencode.ai/docs/providers/#custom-provider)
and [configuration environment variables](https://opencode.ai/docs/config/#env-vars).

### Interactive Sessions and Single Requests

```bash
# Check local model registration only.
bash scripts/in-container.sh opencode models azure-kimi
bash scripts/in-container.sh opencode models azure-deepseek
bash scripts/in-container.sh opencode models azure-glm

# Start an interactive session with a selected model.
bash scripts/in-container.sh opencode --model azure-kimi/kimi-k3
bash scripts/in-container.sh opencode --model azure-deepseek/deepseek-v4.1-flash
bash scripts/in-container.sh opencode --model azure-glm/glm-5.3
bash scripts/in-container.sh opencode --model azure-glm/glm-5.3-flash

# Single request; replace the --model identifier to use another model.
bash scripts/in-container.sh opencode run --model azure-glm/glm-5.3-flash \
  --format json 'Reply with exactly AZURE_MODEL_OK.'
```

Use `/models` to switch models in an existing OpenCode session. Restart if needed
to reload configuration. To fix the effort for a single request, add
`--variant high` (or `low` or `max`) to `opencode run`.

<a id="opencode-batch"></a>

### Slurm: Supply the Provider Before Submission

`scripts/opencode.sh` copies only `auth.json` from the interactive home, then
generates an `opencode.json` containing basic settings in the job home. It
**does not copy custom providers**, so passing only a model identifier to the
submission script leaves its definition missing.

Supply the selected provider through `OPENCODE_CONFIG_CONTENT`. First prepare
`AZURE_API_KEY` and `APPTAINERENV_AZURE_API_KEY` as described above. The following
example replaces that provider's credential with an environment-variable
reference in memory, so it also works with configurations that store keys locally:

```bash
# Use any complete OpenCode model identifier from the table.
AZURE_MODEL='azure-glm/glm-5.3-flash'
AZURE_PROVIDER_CONFIG="$(python3 - "$AZURE_MODEL" <<'PY'
import json
import sys
from pathlib import Path

config = json.loads(Path('interactive/home/.config/opencode/opencode.json').read_text())
provider_id, model_id = sys.argv[1].split('/', 1)
provider = config['provider'][provider_id]
if model_id not in provider['models']:
    raise SystemExit('The selected model is not configured in this provider.')
provider['options']['apiKey'] = '{env:AZURE_API_KEY}'
print(json.dumps({'provider': {provider_id: provider}}))
PY
)" && export APPTAINERENV_OPENCODE_CONFIG_CONTENT="$AZURE_PROVIDER_CONFIG"
test -n "$APPTAINERENV_OPENCODE_CONFIG_CONTENT"

# The batch script requires this file even when authentication uses an environment variable.
# Create an empty credential object only if the file is missing; preserve existing credentials.
python3 - <<'PY'
from pathlib import Path
path = Path('interactive/home/.local/share/opencode/auth.json')
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
if not path.exists():
    with path.open('x') as stream:
        stream.write('{}\n')
    path.chmod(0o600)
PY

scripts/submit-agent.sh opencode "$AZURE_MODEL" \
  configs/smollm3-swedish.example.json high

# Clear the temporary provider override from the submitting shell afterward.
unset APPTAINERENV_OPENCODE_CONFIG_CONTENT AZURE_PROVIDER_CONFIG AZURE_MODEL
```

The Slurm submission environment must contain both `APPTAINERENV_*` variables.
The helper exports the environment by default; do not discard them with an outer
`--export=NONE`. This supplies the provider without requiring the job to access
the interactive home. Container validation of this override used Kimi K3; a full
Slurm experiment was not run.

<a id="kimi-code"></a>

## Kimi Code 2.2.0: Kimi K3

### Persistent Configuration

Repository paths are listed in the [configuration table](#credentials). The
native CLI reads `~/.kimi-code/config.toml` by default. The following is a minimal
standalone configuration. When merging it into an existing file, preserve other
connections and merge `default_model` and `[thinking]` as well:

```toml
default_model = "kimi-k3"

[providers.azure-kimi]
type = "openai"
base_url = "https://lab-swe-resource.services.ai.azure.com/openai/v1"
api_key_env = "AZURE_API_KEY"

[models.kimi-k3]
provider = "azure-kimi"
model = "FW-Kimi-K3"
max_context_size = 131072
capabilities = ["thinking"]
support_efforts = ["low", "high", "max"]
default_effort = "high"

[thinking]
enabled = true
effort = "high"
```

`131072` is the existing client-side context budget, not a verified server-side
limit. `api_key_env` reads an environment variable and is an alternative to
`api_key`. Exporting only `OPENAI_API_KEY` or `KIMI_API_KEY` does not automatically
provide credentials for this provider.

The native 2.2.0 CLI uses `type = "openai"`. The older Python `kimi-cli` settings
`openai_legacy`, `~/.kimi/config.toml`, and its environment-variable conventions
do not apply. See the [2.2.0 provider configuration](https://github.com/MoonshotAI/kimi-code/blob/%40moonshot-ai/kimi-code%402.2.0/docs/en/configuration/providers.md)
and [credential environment variables](https://github.com/MoonshotAI/kimi-code/blob/%40moonshot-ai/kimi-code%402.2.0/docs/en/configuration/env-vars.md).

### Interactive Sessions, Single Requests, and Slurm

```bash
# List providers; this does not validate inference requests.
AGENT=kimi bash scripts/in-container.sh kimi provider list --json

# Single request and interactive use.
AGENT=kimi bash scripts/in-container.sh kimi --model kimi-k3 \
  --prompt 'Reply with exactly AZURE_KIMI_OK.' --output-format stream-json
AGENT=kimi bash scripts/in-container.sh kimi --model kimi-k3

# Slurm experiment; this consumes GPU allocation and model API usage.
scripts/submit-agent.sh kimi kimi-k3 configs/smollm3-swedish.example.json max
```

The Kimi batch script copies this `config.toml` and reuses saved keys. Export
and forward a credential at submission time only when using the environment-variable
configuration. No Kimi subscription OAuth login is required.

The launcher uses Python 3.12 in the container to run `scripts/set-kimi-effort.py`.
Only the job's configuration copy gets `[thinking].enabled = true` and
`effort = "max"` in the example above; omitting the argument preserves the
original settings. This needs neither a new native CLI `--effort` argument nor
an image rebuild.

The model must explicitly declare `support_efforts` (`low/high/max` above).
Unsupported values fail before the CLI starts. The helper edits a regular
`[thinking]` table and rejects TOML layouts it cannot safely update. The override
does not change the interactive configuration or its credentials; see
[validation results and logs](#validation).

<a id="grok-build"></a>

## Grok Build 1.0.62: Grok 4.7

### Persistent Configuration

The local persistent configuration stores a model-level `api_key` and defaults
to `azure-grok-4.7`. No new login or credential environment variable is needed.
See the [configuration table](#credentials) for paths and permissions.

The model alias contains a period, so use `[model."azure-grok-4.7"]` to prevent
TOML from interpreting it as nested tables. API `model` is the deployment name;
the base URL excludes the `/chat/completions` suffix appended by the client.
See [Grok custom models](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/11-custom-models.md)
and [Azure endpoints](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/endpoints).

The complete example below uses an environment variable. The current local
configuration uses its saved model-level `api_key`; no key is embedded in this
guide or the repository's examples:

```toml
[cli]
auto_update = false

[models]
default = "azure-grok-4.7"

[model."azure-grok-4.7"]
name = "Azure Grok 4.7"
model = "grok-4.7"
base_url = "https://lab-swe-resource.services.ai.azure.com/openai/v1"
api_backend = "chat_completions"
env_key = "AZURE_API_KEY"
reasoning_efforts = [
    { value = "low" },
    { value = "medium" },
    { value = "high", default = true },
    { value = "xhigh" },
]
```

`env_key` reads the Bearer credential from the named environment variable and
takes precedence over account login credentials. A model-level `api_key` takes
precedence over `env_key`. To switch to environment-variable authentication,
remove that model's saved `api_key`, merge the example, and forward the key as
described under [credentials](#credentials).

Context and output limits have not been verified, so the example does not guess
`context_window`. Set it according to the deployment documentation before long
experiments. Grok defaults a new custom model to 200,000 tokens when no context
window is specified; that is not a verified limit for this Azure deployment.

### Interactive Sessions, Single Requests, and Slurm

```bash
# List local model definitions; this does not validate inference requests.
AGENT=grok bash scripts/in-container.sh grok models

# Interactive use; omit the command to use the saved default model.
AGENT=grok bash scripts/in-container.sh grok --model azure-grok-4.7
AGENT=grok bash scripts/in-container.sh

# Single request.
AGENT=grok bash scripts/in-container.sh grok --model azure-grok-4.7 \
  --single 'Reply with exactly AZURE_GROK_OK.' \
  --reasoning-effort high --output-format json --no-auto-update

# Slurm experiment.
scripts/submit-agent.sh grok azure-grok-4.7 configs/smollm3-swedish.example.json xhigh
```

`scripts/grok.sh` copies the persistent interactive `config.toml` into the job
home with mode `600`, including model definitions and saved keys. Submission
therefore needs no `GROK_CONFIG_FILE`. That variable remains available to select
another configuration explicitly; relative paths resolve against
`SLURM_SUBMIT_DIR`. The job does not copy interactive OAuth `auth.json` or session
directories. These host-side configuration and script changes need no image rebuild.

<a id="direct-api"></a>

## Direct API Calls

Export the host's `AZURE_API_KEY` as described under [credentials](#credentials).
These examples use Kimi K3. For another model, replace `model` with its Azure
deployment name from the [model table](#model-catalog).

### curl: Non-streaming and Streaming

Supply the authentication header through standard input to keep the expanded
key out of curl's command-line arguments:

```bash
printf 'Authorization: Bearer %s\n' "$AZURE_API_KEY" |
  curl --fail-with-body --silent --show-error --max-time 120 \
    --header @- \
    --header 'Content-Type: application/json' \
    'https://lab-swe-resource.services.ai.azure.com/openai/v1/chat/completions' \
    --data '{
      "model": "FW-Kimi-K3",
      "messages": [{"role": "user", "content": "Reply with exactly AZURE_KIMI_OK."}],
      "max_tokens": 1024,
      "stream": false
    }'
```

The expected `choices[0].message.content` is `AZURE_KIMI_OK`. For streaming,
set `stream` to `true` and add `--no-buffer` to curl. Each SSE event starts with
`data:`; response text appears in `choices[].delta.content`, and the stream ends
with `data: [DONE]`. The tested Kimi K3 response also included `reasoning_content`,
which should be handled separately from the final answer.

### Python: Standard Library Only

```bash
python3 - <<'PY'
import json
import os
import urllib.request

payload = {
    "model": "FW-Kimi-K3",
    "messages": [{"role": "user", "content": "Reply with exactly AZURE_KIMI_OK."}],
    "max_tokens": 1024,
    "stream": False,
}
request = urllib.request.Request(
    "https://lab-swe-resource.services.ai.azure.com/openai/v1/chat/completions",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Authorization": "Bearer " + os.environ["AZURE_API_KEY"],
        "Content-Type": "application/json",
    },
)
with urllib.request.urlopen(request, timeout=120) as response:
    result = json.load(response)
print(result["choices"][0]["message"].get("content"))
print("model:", result["model"])
print("usage:", result.get("usage"))
PY
```

Reasoning tokens consume the output budget. If `finish_reason=length` and the
answer is empty, increase `max_tokens`; an unfinished reasoning response does
not necessarily mean the connection failed.

<a id="validation"></a>

## Validation Results and Logs (2026-10-21)

### Connectivity and Tool Calls

| Model | API requests | CLI validation |
| --- | --- | --- |
| Kimi K3 | Non-streaming and SSE both returned HTTP 200 and `AZURE_KIMI_OK`; SSE ended with `[DONE]`; function calling returned the correct function name and JSON arguments | Kimi Code `Read` and OpenCode `read` both read a file and returned `AZURE_KIMI_TOOL_OK`, exit code 0 |
| DeepSeek V4.1 Flash | HTTP 200, correct response deployment, `AZURE_MODEL_OK` | OpenCode `read` returned `AZURE_MODEL_TOOL_OK`, exit code 0 |
| GLM 5.3 | HTTP 200, correct response deployment, `AZURE_MODEL_OK` | OpenCode `read` returned `AZURE_MODEL_TOOL_OK`, exit code 0 |
| GLM 5.3 Flash | HTTP 200, correct response deployment, `AZURE_MODEL_OK` | OpenCode `read` returned `AZURE_MODEL_TOOL_OK`, exit code 0 |
| Grok 4.7 | All four documented efforts returned HTTP 200 and `GROK_EFFORT_OK` | All four Grok CLI efforts returned `GROK_CLI_EFFORT_OK`, exit code 0; a full tool-call cycle was not tested |

CLI tests used copied configurations in separate `RUN_DIR` directories without
changing the original interactive configuration. The tool tests above had empty
stderr. Kimi K3 also passed environment-variable authentication tests in both
CLIs and a container test combining OpenCode's basic job configuration with
`OPENCODE_CONFIG_CONTENT`. `GET /openai/v1/models` returned HTTP 200, but the
catalog response is not proof that a deployment can serve inference requests.

DeepSeek and GLM were not tested with separate SSE requests; their streaming
compatibility was verified through OpenCode calls.

### OpenCode and Kimi Code Reasoning Effort

Custom OpenCode models need explicit variant mappings. Initially, DeepSeek and
GLM had no `variants`: `--variant high` could exit successfully while the main
request omitted `reasoning_effort`. The local configurations now include
`low/high/max` mappings for all three models. The SDK translates JSON
`reasoningEffort` into API `reasoning_effort`; naming a variant alone does not
ensure that the field is sent. See [OpenCode variants](https://opencode.ai/docs/models/#variants)
and the [1.19.2 request option merge implementation](https://github.com/anomalyco/opencode/blob/v1.19.2/packages/opencode/src/session/llm/request.ts).

- A local test endpoint captured 12 OpenCode cases: four models at three effort
  levels. Each main request's `reasoning_effort` matched `--variant`. Auxiliary
  session-title requests may use another effort and must be checked separately.
- Direct requests to all four Azure deployments at `low/high/max` returned
  HTTP 200 and `EFFORT_API_OK` in all 12 cases. Each model also completed a real
  file-read tool cycle through OpenCode with `--variant high`, sending
  `reasoning_effort=high` and exiting with code 0.
- Invalid-effort controls returned HTTP 400 for Kimi and both GLM deployments,
  but HTTP 200 for DeepSeek. Request success alone does not validate an arbitrary
  effort string; only the models' documented `low/high/max` values are configured.
- A local check using a substitute `sbatch` confirmed that the submission helper
  forwards its fourth argument unchanged without submitting a job. Kimi Code
  tests with isolated configuration also confirmed that all three
  `[thinking].effort` values map to the request field.
- The Kimi launcher supports the fourth argument by editing the job's
  configuration copy and validating the model's `support_efforts` before startup.
  Twelve automated checks cover configuration preservation, enabling thinking,
  all three levels, invalid values, and unsupported values. Captured real Kimi
  CLI requests confirmed the three values produced by the helper. A real Azure
  Kimi Code call using the helper's `max` override returned `KIMI_EFFORT_MAX_OK`,
  exit code 0, and empty stderr, with the interactive configuration unchanged.

Model effort references: [Kimi K3](https://huggingface.co/moonshotai/Kimi-K3),
[DeepSeek](https://api-docs.deepseek.com/guides/thinking_mode/), and
[GLM 5.3 / Flash](https://github.com/zai-org/GLM-5).

### Grok 4.7 Reasoning Effort

Real Chat Completions requests to the current Azure `grok-4.7` deployment produced:

| `reasoning_effort` | HTTP status | Result |
| --- | --- | --- |
| Omitted | 200 | Returned `GROK_EFFORT_OK` |
| `low`, `medium`, `high`, `xhigh` | All 200 | All returned `GROK_EFFORT_OK` |
| `minimal` | 200 | Accepted by the endpoint, but not one of the four documented levels; not configured |
| `none`, `max` | Both 400 | Rejected by the endpoint |
| Invalid value `invalid_effort_probe` | 400 | Control request rejected |

Azure and xAI both document `low/medium/high/xhigh`, with `high` as the default.
See [Azure Grok parameters](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/use-foundry-models-grok)
and [xAI reasoning](https://docs.x.ai/developers/model-capabilities/text/reasoning).

Capturing requests from the installed Grok CLI revealed that the initial custom
model configuration lacked `reasoning_efforts`. The CLI warned and ignored
`--reasoning-effort` even though it exited with code 0; the main request omitted
the field. The local persistent configuration and the example above now declare
all four levels, with `high` as the default. See the
[Grok reasoning_efforts reference](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/26-config-reference.md#modelid).

After the fix, a local forwarding service recorded only sanitized request fields
and forwarded the actual requests to Azure. All four CLI main requests carried
the requested `reasoning_effort` and received HTTP 200. Each CLI run returned
`GROK_CLI_EFFORT_OK`, exit code 0, and empty stderr. Later auxiliary requests may
use `low`; check them separately from the initial request executing the user's
prompt. The forwarding service sent requests only to this Azure deployment.

### Log Index

These records are in Git-ignored directories:

| Content | Path |
| --- | --- |
| Kimi K3 connectivity and tool calls | `runs/azure-kimi-connection-check-20261021/` |
| DeepSeek / GLM connectivity and tool calls | `runs/azure-opencode-model-check-20261021/` |
| OpenCode / Kimi effort request summaries | `runs/azure-effort-check-20261021/`, including `kimi-helper-results.json` |
| Kimi launcher configuration checks | `runs/kimi-effort-launcher-check-20261021/`; automated checks: [`tests/test_kimi_effort.py`](../tests/test_kimi_effort.py) |
| Grok API effort matrix | `runs/azure-grok-effort-check-20261021/api-results.json` |
| Grok CLI requests before / after the fix | `cli-request-summary.json` / `cli-fixed-request-summary.json` in the same directory |

### Validation Scope

These checks establish endpoint compatibility and client parameter forwarding.
They do not verify the underlying model weights, full context capacity, image
input, long training runs, or throughput limits. No Slurm experiment was
submitted, and the Grok checks did not run GPU tasks. Differences in quality,
latency, or reasoning budgets across effort levels were not evaluated; reasoning
token counts from short prompts are insufficient to establish those differences.

<a id="troubleshooting"></a>

## Troubleshooting

- **401/403:** Check the saved key. For environment-variable authentication,
  confirm that the corresponding variable reaches the container. Do not print
  the environment or use shell `set -x` to debug credentials.
- **404 / deployment not found:** API `model` must use the Azure deployment name.
  Do not append `/chat/completions` twice. A `/models` catalog response does not
  prove the deployment can serve requests; verify with an actual POST.
- **Local model not found:** Use the aliases in the [model table](#model-catalog).
  OpenCode batch jobs also need the provider override described above.
- **Effort ignored:** Check OpenCode `variants`, Kimi `support_efforts`, or Grok
  `reasoning_efforts`, and inspect the main request field rather than just the
  process exit code.
- **Grok `max` returns 400:** Use `xhigh` for Grok 4.7; see the [effort table](#effort).
- **429:** Respect `Retry-After`, retry with backoff, and reduce concurrency or
  output budgets. Quotas apply per deployment, not per client. Reasoning,
  subsequent tool-call turns, and parallel jobs all share the budget. No
  throughput load test was performed.
- **Credential management:** Local configuration may contain plaintext keys.
  Replace them with environment-variable references before sharing. Do not
  commit `interactive/`, job homes, credentials, or raw request logs containing keys.
