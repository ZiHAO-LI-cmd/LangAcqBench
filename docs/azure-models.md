# Azure Models: Configuration, Usage, and Validation

This guide covers Azure model configuration, interactive use, Slurm submission,
and validation results for OpenCode, Kimi Code, Grok Build, and Codex on Roihu. The
records cover **2026-10-21–2026-10-22** and apply to **OpenCode 1.19.2**,
**Kimi Code 2.2.0 (native CLI)**, **Grok Build 1.0.62**, and **Codex 0.163.0**.
The initial Codex 0.155.1 results are retained below for comparison.

- [Deployments and model identifiers](#model-catalog)
- [Persistent configuration and credentials](#credentials)
- [Reasoning effort parameters](#effort)
- [OpenCode](#opencode) · [Kimi Code](#kimi-code) · [Grok Build](#grok-build) · [Codex](#codex)
- [Direct API calls](#direct-api)
- [Validation results and logs](#validation) · [Troubleshooting](#troubleshooting)

<a id="model-catalog"></a>

## Deployments and Model Identifiers

All eight deployments use the same Azure resource and API base URL:

| Parameter | Value |
| --- | --- |
| API base URL | `https://lab-swe-resource.services.ai.azure.com/openai/v1` |
| Chat Completions URL | `https://lab-swe-resource.services.ai.azure.com/openai/v1/chat/completions` |
| Responses URL (Codex) | `https://lab-swe-resource.services.ai.azure.com/openai/v1/responses` |
| Authentication | `Authorization: Bearer <API_KEY>`, verified |

| Model | Azure deployment / API `model` | TPM | RPM |
| --- | --- | --- | --- |
| Kimi K3 | `FW-Kimi-K3` | 250,000 | 250 |
| DeepSeek V4.1 Flash | `DeepSeek-V4.1-Flash` | 1,000,000 | 1,000 |
| GLM 5.3 | `FW-GLM-5.3` | 125,000 | 125 |
| GLM 5.3 Flash | `FW-GLM-5.3-Flash` | 125,000 | 125 |
| Grok 4.7 | `grok-4.7` | 10,000,000 | 10,000 |
| GPT-6 Astra | `gpt-6-astra` | 10,000,000 | 10,000 |
| GPT-6.1 Sol | `gpt-6.1-sol` | 10,000,000 | 10,000 |
| GPT-6 Luna | `gpt-6-luna` | 10,000,000 | 10,000 |

| Model | OpenCode identifier | Kimi Code alias | Grok Build alias | Codex submission selector |
| --- | --- | --- | --- | --- |
| Kimi K3 | `azure-kimi/kimi-k3` | `kimi-k3` | — | — |
| DeepSeek V4.1 Flash | `azure-deepseek/deepseek-v4.1-flash` | — | — | — |
| GLM 5.3 | `azure-glm/glm-5.3` | — | — | — |
| GLM 5.3 Flash | `azure-glm/glm-5.3-flash` | — | — | — |
| Grok 4.7 | — | — | `azure-grok-4.7` | — |
| GPT-6 Astra | — | — | — | `azure/gpt-6-astra` |
| GPT-6.1 Sol | — | — | — | `azure/gpt-6.1-sol` |
| GPT-6 Luna | — | — | — | `azure/gpt-6-luna` |

The table lists the combinations currently configured and validated. API requests
use the Azure deployment name; local configuration maps each CLI alias to that
deployment. Set the client base URL to `/openai/v1`. OpenCode, Kimi, and Grok append
`/chat/completions`; Codex uses `/responses`. These Azure v1 examples need no `api-version`
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
| Codex Azure profile | `interactive/codex/home/.codex/azure.config.toml` | `/home/agent/.codex/azure.config.toml` |

Interactive sessions and Kimi/Grok/Codex Azure batch jobs reuse the saved configuration and
keys. OpenCode batch jobs snapshot the [selected provider configuration](#opencode-batch).
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
[Kimi Code](kimi.md), [Grok Build](grok.md), and [Codex](codex.md).

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
| Codex: the three GPT deployments | `low` API checks and `max` tool tests / request capture verified on 0.163.0 | `-c model_reasoning_effort=...` → Responses `reasoning.effort` | Azure profile defaults to `medium` |

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

### Slurm: Selected Provider Configuration

`scripts/opencode.sh` copies `auth.json` and the selected provider definition from
`interactive/home/.config/opencode/opencode.json` into the isolated job home.
This preserves the endpoint, deployment mapping, API key configuration, and
reasoning variants without copying unrelated interactive settings.

With the saved local credentials, submit directly:

```bash
scripts/submit-agent.sh opencode azure-glm/glm-5.3 \
  configs/smollm3-swedish.train-only.example.json high
```

If the provider uses `{env:AZURE_API_KEY}`, the submission environment must still
contain `APPTAINERENV_AZURE_API_KEY`, as described above. Explicit
`APPTAINERENV_OPENCODE_CONFIG_CONTENT` overrides remain supported and take
precedence over the saved provider settings. Clear stale overrides when intending
to use the saved configuration. The batch script still requires `auth.json`.

Previously the launcher copied only `auth.json`, leaving custom providers absent
unless supplied through an environment override. A local reproduction on 1.19.2
showed that a missing `azure-glm/glm-5.3` definition produces a generic
`Unexpected server error` event; internal logs reveal
`ProviderModelNotFoundError`. The launcher now captures internal error logs in
`agent.err`. This fix does not retry API failures automatically.

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

<a id="codex"></a>

## Codex 0.163.0: GPT-6 Astra, GPT-6.1 Sol, and GPT-6 Luna

### Persistent Azure Profile

The private `azure.config.toml` profile stores the Azure key in the provider's
`experimental_bearer_token` field (mode `600`, under Git-ignored `interactive/`).
The existing base `config.toml`, default model, and ChatGPT OAuth credentials are
preserved. Select the Azure profile explicitly for interactive use.

Codex 0.163.0 uses separate `$CODEX_HOME/<name>.config.toml` profile files,
selected with `--profile <name>`. Do not put this example in a `[profiles.azure]`
table. The following portable example uses an environment variable instead of a
saved credential:

```toml
model = "gpt-6.1-sol"
model_provider = "azure"
model_reasoning_effort = "medium"
cli_auth_credentials_store = "file"

[model_providers.azure]
name = "Azure OpenAI"
base_url = "https://lab-swe-resource.services.ai.azure.com/openai/v1"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
env_key = "AZURE_API_KEY"
```

Use the resource base URL, not the supplied `/chat/completions` URL: Codex needs
Responses for its tool workflow. All three deployments were verified through
`/openai/v1/responses`. `requires_openai_auth = false` uses the provider key rather
than a ChatGPT login; `supports_websockets = false` selects HTTP/SSE transport.
See the [official Codex configuration reference](https://developers.openai.com/codex/config-reference/).

The current local profile uses a saved `experimental_bearer_token`. To use the
example's `env_key` instead, remove that token and forward `AZURE_API_KEY` as
explained under [credentials](#credentials). Neither key is written into tracked
files or the container image.

### Interactive Sessions and Single Requests

```bash
# The Azure profile defaults to gpt-6.1-sol at medium effort.
AGENT=codex bash scripts/in-container.sh codex --profile azure

# Choose any of the three Azure deployments.
AGENT=codex bash scripts/in-container.sh codex --profile azure --model gpt-6-astra
AGENT=codex bash scripts/in-container.sh codex --profile azure --model gpt-6.1-sol
AGENT=codex bash scripts/in-container.sh codex --profile azure --model gpt-6-luna

# A single request with an explicit effort.
AGENT=codex bash scripts/in-container.sh codex exec --profile azure \
  --model gpt-6-astra -c 'model_reasoning_effort="max"' \
  --skip-git-repo-check --json 'Reply with exactly AZURE_CODEX_API_OK.'
```

### Slurm: Select Azure with the `azure/` Prefix

```bash
scripts/submit-agent.sh codex azure/gpt-6-astra configs/smollm3-swedish.example.json max
scripts/submit-agent.sh codex azure/gpt-6.1-sol configs/smollm3-swedish.example.json max
scripts/submit-agent.sh codex azure/gpt-6-luna configs/smollm3-swedish.example.json max
```

The prefix is a repository launcher selector, not part of the Azure deployment
name or a native Codex model ID. The launcher strips it and copies only
`azure.config.toml` into the job home as `config.toml` (mode `600`). Azure jobs
need no `auth.json`, OAuth refresh, or shared login lock, and do not modify the
existing OAuth state. Each job gets its own configuration and session directory.
Unprefixed models retain the existing OpenAI authentication and refresh path.
No image rebuild or credential environment variable is needed with the saved key.

The launcher accepts `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`;
model support still applies. Official GPT-6 guidance lists `low/medium/high/xhigh/max`
for Astra and Sol, with `none` also available for Luna. `minimal` is not supported
by these GPT-6 models. The 0.163.0 retest verified `low` with direct API calls and
`max` with real file-read tools and captured Responses requests for all three
deployments. The original 0.155.1 checks also tested tools at `low`. An exhaustive
matrix of every effort was not run. See [GPT-6 guidance](https://developers.openai.com/api/docs/guides/latest-model).

Codex 0.155.1 reported fallback model metadata for GPT-6.1 Sol and GPT-6 Luna in
initial tool checks. Those warnings were absent in the 0.163.0 retest for all
three models. No metadata catalog or context override was added to suppress
them. Full context limits, compaction, and model-specific defaults remain untested.

<a id="direct-api"></a>

## Direct API Calls

Export the host's `AZURE_API_KEY` as described under [credentials](#credentials).
The Chat Completions examples below use Kimi K3; for another deployment using
that API, replace `model` with its name from the [model table](#model-catalog).
The Codex deployments use Responses, as shown after the Python example.

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

### Responses: Codex Deployments

```bash
printf 'Authorization: Bearer %s\n' "$AZURE_API_KEY" |
  curl --fail-with-body --silent --show-error --max-time 120 \
    --header @- \
    --header 'Content-Type: application/json' \
    'https://lab-swe-resource.services.ai.azure.com/openai/v1/responses' \
    --data '{
      "model": "gpt-6-astra",
      "input": "Reply with exactly AZURE_CODEX_API_OK.",
      "reasoning": {"effort": "low"},
      "max_output_tokens": 1024,
      "store": false
    }'
```

Replace `model` with `gpt-6.1-sol` or `gpt-6-luna` for the other deployments.
Responses text is in `output[]` message items, under `content[]` entries with
`type: "output_text"`; it does not use Chat Completions `choices`.

<a id="validation"></a>

## Validation Results and Logs (2026-10-21–2026-10-22)

### Connectivity and Tool Calls

| Model | API requests | CLI validation |
| --- | --- | --- |
| Kimi K3 | Non-streaming and SSE both returned HTTP 200 and `AZURE_KIMI_OK`; SSE ended with `[DONE]`; function calling returned the correct function name and JSON arguments | Kimi Code `Read` and OpenCode `read` both read a file and returned `AZURE_KIMI_TOOL_OK`, exit code 0 |
| DeepSeek V4.1 Flash | HTTP 200, correct response deployment, `AZURE_MODEL_OK` | OpenCode `read` returned `AZURE_MODEL_TOOL_OK`, exit code 0 |
| GLM 5.3 | HTTP 200, correct response deployment, `AZURE_MODEL_OK` | OpenCode `read` returned `AZURE_MODEL_TOOL_OK`, exit code 0 |
| GLM 5.3 Flash | HTTP 200, correct response deployment, `AZURE_MODEL_OK` | OpenCode `read` returned `AZURE_MODEL_TOOL_OK`, exit code 0 |
| Grok 4.7 | All four documented efforts returned HTTP 200 and `GROK_EFFORT_OK` | All four Grok CLI efforts returned `GROK_CLI_EFFORT_OK`, exit code 0; a full tool-call cycle was not tested |
| GPT-6 Astra | Responses returned HTTP 200, `completed`, and `AZURE_CODEX_RETEST_API_OK` at `low` on 2026-10-22 | Codex 0.163.0 read the test file at `max` and returned its exact contents, exit code 0; no metadata warning |
| GPT-6.1 Sol | Responses returned HTTP 200, `completed`, and `AZURE_CODEX_RETEST_API_OK` at `low` on 2026-10-22 | Codex 0.163.0 read the test file at `max` and returned its exact contents, exit code 0; no metadata warning |
| GPT-6 Luna | Responses returned HTTP 200, `completed`, and `AZURE_CODEX_RETEST_API_OK` at `low` on 2026-10-22 | Codex 0.163.0 read the test file at `max` and returned its exact contents, exit code 0; no metadata warning |

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

### Codex Azure Responses and Reasoning Effort

#### Codex 0.163.0 retest: 2026-10-22

The installed container and local build metadata both report **0.163.0**.
All three deployments passed fresh direct Responses API calls at `low`:
HTTP 200, status `completed`, and exact text `AZURE_CODEX_RETEST_API_OK`.

Using fresh run homes, Codex loaded a copy of the Azure profile and read a test
file containing a random marker not included in the prompt. All three runs
executed a successful shell file-read tool, returned the exact marker, and
exited with code 0. Requests were forwarded to the real Azure endpoint with
only sanitized fields recorded. Every captured model request used the correct
deployment, `stream: true`, and `reasoning.effort: "max"`, with Azure HTTP 200.

No fallback metadata warnings appeared in stdout or stderr for Astra, Sol, or
Luna. Stderr contained only the benign `Reading additional input from stdin...`
diagnostic. The persistent Azure profile, base configuration, and OAuth file
were unchanged, verified by file hashes. The five offline launcher checks also
passed again. No GPU work or Slurm submission was performed, and the launcher
needed no changes for the updated CLI.

#### Initial Codex 0.155.1 checks: 2026-10-21

All three requested GPT deployments passed a direct Responses API check at `low`:
HTTP 200, response status `completed`, and exact text `AZURE_CODEX_API_OK`.
Codex 0.155.1 then used the private Azure profile in isolated run homes to read
`/workspace/connection-check.txt`. Each run completed a shell tool call with exit
code 0 and returned the model-specific file contents exactly.

A separate local forwarding service captured real Codex requests at `max` and
sent them to the same Azure `/openai/v1/responses` endpoint. For all three models,
the request used the correct deployment name, `stream: true`, and
`reasoning.effort: "max"`; Azure returned HTTP 200 and Codex returned
`CODEX_EFFORT_OK` with exit code 0. The full effort matrix and quality differences
were not tested. The CLI prints a benign `Reading additional input from stdin...`
diagnostic; its stderr was not empty.

Five offline launcher checks cover Azure profile copying and mode `600`, prefix
removal, effort forwarding, preservation of OAuth state and child exit codes,
missing-profile errors, and the original unprefixed OAuth refresh path. See
[`tests/test_codex_azure.py`](../tests/test_codex_azure.py). No Slurm job was submitted.

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
| Codex Responses API checks | `runs/azure-codex-check-20261021/api-results.json` |
| Codex file-read tool checks | `runs/azure-codex-check-20261021/cli-results.json`, with per-model `agent.jsonl`, `agent.err`, and `work/agent-final.md` |
| Codex captured `max` requests | `runs/azure-codex-check-20261021/cli-effort-request-summary.json` |
| Codex 0.163.0 retest | `runs/azure-codex-retest-20261022/summary.json`, `api-results.json`, `cli-results.json`, and `request-summary.json` |
| Codex 0.163.0 per-model tool logs | `runs/azure-codex-retest-20261022/cli-MODEL/agent.jsonl`, `agent.err`, and `work/agent-final.md`; retest harness: `retest.py` in the parent directory |

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
  `reasoning_efforts`. Codex uses `model_reasoning_effort` and the Responses
  `reasoning.effort` field. Inspect the main request rather than just the exit code.
- **Codex uses the wrong endpoint:** Select `--profile azure` interactively or
  `azure/DEPLOYMENT` in the batch helper. Use `/openai/v1` as the provider base URL,
  with `wire_api = "responses"`; do not configure `/chat/completions` as its base.
- **Grok `max` returns 400:** Use `xhigh` for Grok 4.7; see the [effort table](#effort).
- **429:** Respect `Retry-After`, retry with backoff, and reduce concurrency or
  output budgets. Quotas apply per deployment, not per client. Reasoning,
  subsequent tool-call turns, and parallel jobs all share the budget. No
  throughput load test was performed.
- **Credential management:** Local configuration may contain plaintext keys.
  Replace them with environment-variable references before sharing. Do not
  commit `interactive/`, job homes, credentials, or raw request logs containing keys.
