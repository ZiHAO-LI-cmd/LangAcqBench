# Azure models on Roihu

This guide covers deployment identifiers, provider configuration, API calls,
and historical validation for OpenCode, Kimi Code, Grok Build, and Codex.
Use the [shared workflow](agent-common.md) and CLI guides for container builds,
GPU allocation, authentication lifecycle, and common Slurm/logging behavior.

Validation records date from **2026-10-21–2026-10-22**, with a Terra check on
**2026-11-02**. They used **OpenCode 1.19.2**, native **Kimi Code 2.2.0**,
**Grok Build 1.0.62**, and **Codex 0.163.0**. Newer versions in the CLI build
examples are not covered by these historical results.

The two deployments added on **2026-11-10** were checked with **OpenCode
1.19.5** and **Kimi Code 2.5.2**; see [validation](#validation).

- [Deployments](#model-catalog) · [Credentials](#credentials) · [Effort](#effort)
- [OpenCode](#opencode) · [Kimi Code](#kimi-code) · [Grok Build](#grok-build) · [Codex](#codex)
- [Direct API calls](#direct-api) · [Validation and logs](#validation) · [Troubleshooting](#troubleshooting)

<a id="model-catalog"></a>

## Deployments and model identifiers

The recorded configuration uses this Azure resource:

| Parameter | Value |
| --- | --- |
| API base URL | `https://lab-swe-resource.services.ai.azure.com/openai/v1` |
| Chat Completions URL | `https://lab-swe-resource.services.ai.azure.com/openai/v1/chat/completions` |
| Responses URL (Codex) | `https://lab-swe-resource.services.ai.azure.com/openai/v1/responses` |
| Authentication | `Authorization: Bearer <API_KEY>`, verified |

| Model | Azure deployment / API `model` | TPM | RPM |
| --- | --- | --- | --- |
| Kimi K3 | `FW-Kimi-K3` | 250,000 | 250 |
| Kimi K3.1 Pro | `Kimi-K3.1-Pro` | 1,000,000 | 1000 |
| DeepSeek V4.1 Flash | `DeepSeek-V4.1-Flash` | 1,000,000 | 1,000 |
| DeepSeek V4.1 Flash 1017 | `DeepSeek-V4.1-Flash-1017` | 1,000,000 | 1,000 |
| GLM 5.3 | `FW-GLM-5.3` | 500,000 | 500 |
| Grok 4.7 | `grok-4.7` | 10,000,000 | 10,000 |
| GPT-6 Astra | `gpt-6-astra` | 10,000,000 | 10,000 |
| GPT-6.1 Sol | `gpt-6.1-sol` | 10,000,000 | 10,000 |
| GPT-6.1 Terra | `gpt-6.1-terra` | 10,000,000 | 10,000 |
| GPT-6 Luna | `gpt-6-luna` | 10,000,000 | 10,000 |

| Model | OpenCode identifier | Kimi Code alias | Grok Build alias | Codex submission selector |
| --- | --- | --- | --- | --- |
| Kimi K3 | `azure-kimi/kimi-k3` | `kimi-k3` | — | — |
| Kimi K3.1 Pro | `azure-kimi/kimi-k3.1-pro` | `kimi-k3.1-pro` | — | — |
| DeepSeek V4.1 Flash | `azure-deepseek/deepseek-v4.1-flash` | — | — | — |
| DeepSeek V4.1 Flash 1017 | `azure-deepseek/deepseek-v4.1-flash-1017` | — | — | — |
| GLM 5.3 | `azure-glm/glm-5.3` | — | — | — |
| Grok 4.7 | — | — | `azure-grok-4.7` | — |
| GPT-6 Astra | — | — | — | `azure/gpt-6-astra` |
| GPT-6.1 Sol | — | — | — | `azure/gpt-6.1-sol` |
| GPT-6.1 Terra | — | — | — | `azure/gpt-6.1-terra` |
| GPT-6 Luna | — | — | — | `azure/gpt-6-luna` |

API `model` uses the Azure deployment name; local aliases map to that name.
Set the provider base to `/openai/v1`: OpenCode, Kimi, and Grok append
`/chat/completions`, while Codex uses `/responses`. These v1 examples need no
`api-version` parameter. See [Azure v1 API documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/api-version-lifecycle?tabs=key).

TPM/RPM values are user-provided deployment quotas, not measured throughput,
context lengths, or per-job allowances. GLM 5.3 Flash was removed from the
OpenCode configuration on **2026-10-22**; its checks below are historical.

<a id="credentials"></a>

## Configuration and credentials

| Agent | Persistent host configuration | Container configuration |
| --- | --- | --- |
| OpenCode | `interactive/home/.config/opencode/opencode.json` | `/home/agent/.config/opencode/opencode.json` |
| Kimi Code | `interactive/kimi/home/.kimi-code/config.toml` | `/home/agent/.kimi-code/config.toml` |
| Grok Build | `interactive/grok/home/.grok/config.toml` | `/home/agent/.grok/config.toml` |
| Codex Azure profile | `interactive/codex/home/.codex/azure.config.toml` | `/home/agent/.codex/azure.config.toml` |

The saved setup used local keys in Git-ignored files with mode `600`. The
examples below use environment references instead. Merge them into existing
configs while preserving other providers; they contain no real credentials.

For these examples or direct API calls, set the host key and container forwarding
in each submitting shell:

```bash
read -r -s -p 'Azure API key: ' AZURE_API_KEY
printf '\n'
export AZURE_API_KEY
export APPTAINERENV_AZURE_API_KEY="$AZURE_API_KEY"
```

Host API calls read `AZURE_API_KEY`; `APPTAINERENV_AZURE_API_KEY` forwards it
through `--cleanenv`. The variable must match the config: older references to
`AZURE_KIMI_API_KEY` require `APPTAINERENV_AZURE_KIMI_API_KEY`. The shared `.env`
loader does not load Azure keys. Saved inline credentials do not need these
exports; review each client's precedence rules below.

<a id="effort"></a>

## Reasoning effort

Effort is the submission helper's optional fourth positional argument:

```text
bash scripts/submit-agent.sh AGENT MODEL EXPERIMENT_CONFIG [REASONING_OR_EFFORT_LEVEL]
```

| Client / deployment | Verified levels | Mapping | When omitted |
| --- | --- | --- | --- |
| OpenCode: Kimi K3 / K3.1 Pro, DeepSeek V4.1 Flash / Flash 1017, GLM | `low`, `high`, `max` | `--variant` → `variants.LEVEL.reasoningEffort` → API `reasoning_effort` | Model settings; Kimi examples use `high` |
| Kimi Code: Kimi K3 / K3.1 Pro | `low`, `high`, `max` | Enables `[thinking]` and sets `effort` in the job config copy | Preserves config; example uses `high` |
| Grok Build: Grok 4.7 | `low`, `medium`, `high`, `xhigh` | `--reasoning-effort` → API `reasoning_effort` | Configured default `high` |
| Codex: four GPT deployments | `low` API checks; `max` tool tests and request captures | `-c model_reasoning_effort=...` → Responses `reasoning.effort` | Azure profile uses `medium` |

A successful exit alone does not prove effort forwarding. Custom OpenCode
models need `variants`, Kimi needs `support_efforts`, and Grok needs
`reasoning_efforts`. Grok 4.7 rejected `none` and `max`; use its configured levels.
The full Codex effort matrix was not tested; launcher-accepted values are listed
in the [Codex guide](codex.md#submit-experiments).

<a id="opencode"></a>

## OpenCode

### Configuration

Merge these provider definitions into `opencode.json`; also check any
`opencode.jsonc` for conflicts. The model keys are local aliases, and `id` is
sent as the deployment name:

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
        },
        "kimi-k3.1-pro": {
          "id": "Kimi-K3.1-Pro",
          "name": "Kimi K3.1 Pro (Azure)",
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
        },
        "deepseek-v4.1-flash-1017": {
          "id": "DeepSeek-V4.1-Flash-1017",
          "name": "DeepSeek V4.1 Flash 1017 (Azure)",
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
        }
      }
    }
  }
}
```

Kimi has an explicit default effort of `high`; DeepSeek and GLM define variants
without an added model-level default or unverified context limit. Explicit
`options.apiKey` references need no provider `auth login`.
See [custom providers](https://opencode.ai/docs/providers/#custom-provider)
and [environment references](https://opencode.ai/docs/config/#env-vars).

### Usage

```bash
# Check registration; replace azure-kimi with azure-deepseek or azure-glm.
AGENT=opencode bash scripts/in-container.sh opencode models azure-kimi
AGENT=opencode bash scripts/in-container.sh opencode --model azure-kimi/kimi-k3
AGENT=opencode bash scripts/in-container.sh opencode run \
  --model azure-kimi/kimi-k3 --variant high --format json \
  'Reply with exactly AZURE_MODEL_OK.'

bash scripts/submit-agent.sh opencode azure-kimi/kimi-k3 \
  configs/smollm3-swedish.train-only.example.json high
```

Use identifiers from the [model table](#model-catalog) for DeepSeek or GLM.
Use `/models` to switch interactively; restart to reload config changes.

The 2026-11-10 additions preserve the old aliases and default model. Both new
aliases reuse their existing Azure provider and saved credential. Select them
with the existing submission helper:

```bash
AGENT=opencode bash scripts/in-container.sh opencode \
  --model azure-deepseek/deepseek-v4.1-flash-1017
AGENT=opencode bash scripts/in-container.sh opencode \
  --model azure-kimi/kimi-k3.1-pro

bash scripts/submit-agent.sh opencode azure-deepseek/deepseek-v4.1-flash-1017 \
  configs/smollm3-swedish.json high
bash scripts/submit-agent.sh opencode azure-kimi/kimi-k3.1-pro \
  configs/smollm3-swedish.json high
```

<a id="opencode-batch"></a>

### Batch configuration

The launcher copies `auth.json` and snapshots the selected provider from the
persistent `opencode.json`. It preserves the endpoint, deployment mapping,
credential reference, and variants. `auth.json` is still required even for
custom providers; environment references still need forwarded variables.
`APPTAINERENV_OPENCODE_CONFIG_CONTENT` takes precedence over saved settings.

If a custom provider is absent from the job config, OpenCode may emit
`Unexpected server error` while `agent.err` identifies
`ProviderModelNotFoundError`. Authentication alone does not define a provider.

<a id="kimi-code"></a>

## Kimi Code

### Configuration

Merge `default_model`, the provider/model tables, and `[thinking]` into
`config.toml`:

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

[models."kimi-k3.1-pro"]
provider = "azure-kimi"
model = "Kimi-K3.1-Pro"
max_context_size = 131072
capabilities = ["thinking"]
support_efforts = ["low", "high", "max"]
default_effort = "high"

[thinking]
enabled = true
effort = "high"
```

`max_context_size = 131072` is the existing client budget, not a verified server
limit. `api_key_env` is an alternative to a saved `api_key`; exporting unrelated
`OPENAI_API_KEY` or `KIMI_API_KEY` does not supply this provider's credential.
The native CLI uses `type = "openai"` and `.kimi-code/`; older Python `kimi-cli`
settings such as `openai_legacy` and `.kimi/` do not apply.
See the tested [2.2.0 provider configuration](https://github.com/MoonshotAI/kimi-code/blob/%40moonshot-ai/kimi-code%402.2.0/docs/en/configuration/providers.md).

### Usage

```bash
AGENT=kimi bash scripts/in-container.sh kimi provider list --json
AGENT=kimi bash scripts/in-container.sh kimi --model kimi-k3
AGENT=kimi bash scripts/in-container.sh kimi --model kimi-k3 \
  --prompt 'Reply with exactly AZURE_KIMI_OK.' --output-format stream-json

bash scripts/submit-agent.sh kimi kimi-k3 \
  configs/smollm3-swedish.example.json max

AGENT=kimi bash scripts/in-container.sh kimi --model kimi-k3.1-pro
bash scripts/submit-agent.sh kimi kimi-k3.1-pro \
  configs/smollm3-swedish.json max
```

Batch jobs copy the saved config and reuse its key or forwarded environment
reference, without subscription OAuth. The fourth argument changes only the
job's `[thinking]` table and must match `support_efforts`; see the
[Kimi launcher rules](kimi.md#submit-experiments).

<a id="grok-build"></a>

## Grok Build

### Configuration

The quoted model-table name preserves the period in `azure-grok-4.7`:

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

A model-level saved `api_key` takes precedence over `env_key`, which takes
precedence over account credentials. Remove the saved key to use this environment
example. The recorded setup defaults to `azure-grok-4.7` with a saved key.
No context limit has been verified; Grok's 200,000-token custom-model default
is a client assumption, not a measured deployment limit.
See [custom models](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/11-custom-models.md).

### Usage

```bash
AGENT=grok bash scripts/in-container.sh grok models
AGENT=grok bash scripts/in-container.sh grok --model azure-grok-4.7
AGENT=grok bash scripts/in-container.sh grok --model azure-grok-4.7 \
  --single 'Reply with exactly AZURE_GROK_OK.' \
  --reasoning-effort high --output-format json --no-auto-update

bash scripts/submit-agent.sh grok azure-grok-4.7 \
  configs/smollm3-swedish.example.json xhigh
```

The launcher copies the persistent config with mode `600`; `GROK_CONFIG_FILE`
is needed only to select another config. It does not reuse interactive OAuth
or sessions. See [Grok runtime rules](grok.md#runtime-and-credentials).

<a id="codex"></a>

## Codex

### Configuration

Save this as `interactive/codex/home/.codex/azure.config.toml` with mode `600`.
The tested 0.163.0 profile format uses a separate `<name>.config.toml` selected
with `--profile <name>`, rather than a `[profiles.azure]` table:

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

Codex uses Responses and HTTP/SSE transport. Use `/openai/v1` as the base,
`wire_api = "responses"`, and `requires_openai_auth = false` for provider-key
authentication. The recorded private profile uses `experimental_bearer_token`;
remove that token before using `env_key` and forwarding `AZURE_API_KEY`.
The saved default is `gpt-6.1-sol` at `medium`. Keep the base config and OAuth
state separate. See the [configuration reference](https://developers.openai.com/codex/config-reference/).

### Usage

```bash
AGENT=codex bash scripts/in-container.sh codex --profile azure --model gpt-6.1-terra
AGENT=codex bash scripts/in-container.sh codex exec --profile azure \
  --model gpt-6.1-terra -c 'model_reasoning_effort="max"' \
  --skip-git-repo-check --json 'Reply with exactly AZURE_CODEX_API_OK.'

bash scripts/submit-agent.sh codex azure/gpt-6.1-terra \
  configs/smollm3-swedish.example.json max
```

Replace Terra with any GPT deployment in the [model table](#model-catalog).
The batch selector's `azure/` prefix is stripped before API calls. Azure jobs
copy the provider profile as the private job's `config.toml`; they need neither
`auth.json` nor the shared OAuth lock. Unprefixed selectors follow the original
OpenAI authentication path; see [Codex credential rules](codex.md#runtime-and-credentials).

<a id="direct-api"></a>

## Direct API calls

Set the host key using the [credential instructions](#credentials). Pass the
expanded Bearer header through stdin to keep it out of curl's arguments.

### Chat Completions

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

Expected text is `choices[0].message.content`. For SSE, set `stream` to `true`
and add `--no-buffer`; text arrives in `choices[].delta.content`, ending with
`data: [DONE]`. Kimi may emit separate `reasoning_content`. Reasoning consumes
the output budget: if `finish_reason=length` with no final answer, increase
`max_tokens` before diagnosing a connectivity failure.

### Responses

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

Replace `model` with another GPT deployment as needed. Responses text is under
`output[]` message items and their `content[]` entries with `type: "output_text"`.
It does not use Chat Completions `choices`.

<a id="validation"></a>

## Validation and logs

### 2026-11-14 deployment correction

The current user-provided Kimi K3.1 Pro deployment name is `Kimi-K3.1-Pro`.
A direct Chat Completions request using the existing local credential and
`reasoning_effort: "high"` returned HTTP 200 and `API_OK`. The previous
`FW-Kimi-K3.1-Pro` name returned HTTP 404 / `DeploymentNotFound`, matching
the startup failure in Slurm job `3069440`; training did not start.
The saved Kimi Code and OpenCode mappings and examples now use the current
deployment name while retaining their existing local aliases and defaults.
An isolated Kimi Code check using the corrected saved configuration also
returned a random marker from `/workspace/check.txt` and exited 0. Session
records show two requests for `Kimi-K3.1-Pro` at `high` effort; this CLI check
did not capture HTTP request bodies. It left the saved configuration unchanged
and used no GPU allocation or Slurm job.
The November 10 checks below retain the deployment name recorded at that time.

### 2026-11-10 additions

Both `DeepSeek-V4.1-Flash-1017` and `FW-Kimi-K3.1-Pro` returned HTTP 200 and
`AZURE_MODEL_OK` in direct non-streaming Chat Completions calls at each of
`low`, `high`, and `max` (six requests).

OpenCode **1.19.5** read a randomly generated marker file through its `read`
tool and returned the marker with each new model. Captured main requests used
the exact deployment IDs, `stream: true`, and `reasoning_effort: "high"` across
both tool turns, with HTTP 200 responses. Native Kimi Code **2.5.2** passed the
same file-read check using `kimi-k3.1-pro` and its `Read` tool; the job-copy
effort helper set `max`, and both captured requests carried
`reasoning_effort: "max"` and returned HTTP 200.

Tests used isolated config copies and left the persistent configurations
unchanged during validation. These results establish request acceptance,
streaming, tool execution, and effort forwarding; they do not measure how
effort affects reasoning, server context limits, or TPM/RPM throughput. The
Kimi alias retains the existing 131,072-token client budget. No Slurm job was
submitted.

### Historical results

| Deployment / client | Verified behavior | Date |
| --- | --- | --- |
| Kimi K3 / OpenCode and native Kimi | Non-streaming and SSE HTTP 200; function calling; real file-read tools in both CLIs; `low/high/max` API and main-request effort capture | 2026-10-21 |
| DeepSeek V4.1 Flash / OpenCode | HTTP 200; file-read tool; `low/high/max` API and request capture; streaming through CLI | 2026-10-21 |
| GLM 5.3 and historical GLM 5.3 Flash / OpenCode | HTTP 200; file-read tools; `low/high/max` API and request capture; streaming through CLI | 2026-10-21 |
| Grok 4.7 / Grok Build 1.0.62 | All four configured efforts returned HTTP 200 through API and CLI; main-request captures matched the selected effort | 2026-10-21 |
| Astra, Sol, Luna / Codex 0.163.0 | Responses HTTP 200 and `completed` at `low`; real file-read tools at `max`; captured SSE requests used `reasoning.effort: "max"`; no fallback metadata warnings | 2026-10-22 |
| Terra / Codex 0.163.0 | Responses HTTP 200 and `AZURE_TERRA_API_OK` at `low`; random-marker file read at `max`; both captured SSE requests carried `reasoning.effort: "max"` and returned HTTP 200 | 2026-11-02 |

CLI tests used isolated configuration copies; persistent configurations and
OAuth state were unchanged. Codex tests returned random file markers absent
from the prompt. Earlier Codex 0.155.1 tool checks succeeded but showed Sol/Luna
fallback metadata warnings; these disappeared in the 0.163.0 retest without
adding catalog or context overrides.

### Parameter checks and limits

- OpenCode initially omitted effort for custom models without `variants`, even
  on successful exits. Twelve captures checked four models at three levels;
  direct API calls passed all twelve cases, and each model passed a real file
  read at `high`. Check main requests separately from auxiliary title requests.
- Kimi captures verified the three values after applying the job-only helper.
  A real `max` override returned `KIMI_EFFORT_MAX_OK` with exit 0 and unchanged
  interactive config. Offline checks cover preservation and unsupported values.
- Grok initially ignored effort when `reasoning_efforts` was missing. After the
  mapping was added, all four main-request captures matched. Azure rejected
  `none`, `max`, and an invalid control; it accepted `minimal`, which remains
  outside the configured four levels. Auxiliary requests may use `low`.
- Invalid-effort controls returned HTTP 400 for Kimi and both GLM deployments,
  but HTTP 200 for DeepSeek. Success does not establish support for arbitrary
  effort strings. Codex's full effort matrix was not run.

These checks establish endpoint compatibility and parameter forwarding. They
exclude full context capacity, image input, compaction, throughput quotas,
quality comparisons, and long training experiments. No Slurm/GPU experiment
was submitted as part of these checks. Grok's full tool-call cycle was not
tested; DeepSeek/GLM had CLI streaming checks rather than separate direct SSE
checks. Model-list registration alone is not inference validation.

### Evidence index

Evidence directories are Git-ignored. Historical CLI versions are listed at the
start of this guide; build instructions for newer versions are separate.

| Evidence | Path |
| --- | --- |
| Flash 1017 / Kimi K3.1 Pro API and CLI checks | `runs/azure-models-check-20261110/`: `api-results.json`, `cli-results.json`, `request-summary.json`, per-client `agent.jsonl` / `agent.err`, `check_api.py`, and `check_cli.py` |
| Kimi connectivity and file-read tools | `runs/azure-kimi-connection-check-20261021/` |
| DeepSeek / GLM connectivity and tools | `runs/azure-opencode-model-check-20261021/` |
| OpenCode / Kimi effort captures | `runs/azure-effort-check-20261021/`, including `kimi-helper-results.json` |
| Kimi launcher checks | `runs/kimi-effort-launcher-check-20261021/`; [`test_kimi_effort.py`](../tests/test_kimi_effort.py) |
| Grok API and CLI captures | `runs/azure-grok-effort-check-20261021/`: `api-results.json`, `cli-request-summary.json`, `cli-fixed-request-summary.json` |
| Initial Codex API, tools, and effort | `runs/azure-codex-check-20261021/`: `api-results.json`, `cli-results.json`, `cli-effort-request-summary.json` |
| Codex 0.163.0 retest | `runs/azure-codex-retest-20261022/`: `summary.json`, `api-results.json`, `cli-results.json`, `request-summary.json`, per-model logs, and `retest.py` |
| Codex Terra check | `runs/azure-codex-terra-check-20261102/`: `api-results.json`, `cli-results.json`, `request-summary.json`, `cli-max/agent.jsonl`, and `check_cli.py` |
| Codex launcher routing checks | [`test_codex_azure.py`](../tests/test_codex_azure.py) |

<a id="troubleshooting"></a>

## Troubleshooting

| Symptom | Check |
| --- | --- |
| HTTP 401/403 | Saved key or matching forwarded environment variable; avoid printing secrets or using `set -x` |
| HTTP 404 / deployment missing | API `model` must be the deployment name; use the resource base URL without doubling endpoint suffixes |
| OpenCode model not found | Selected provider must be in the job config; inspect `agent.err` for `ProviderModelNotFoundError` |
| Effort ignored | Inspect the main request and the client's `variants`, `support_efforts`, or `reasoning_efforts`; Codex uses Responses `reasoning.effort` |
| Codex wrong endpoint/auth | Select `--profile azure` interactively or `azure/DEPLOYMENT` for batch; use `/openai/v1` with `wire_api = "responses"` |
| Grok `max` rejected | Use a configured level such as `xhigh` |
| HTTP 429 | Respect `Retry-After`, back off, and reduce concurrency/output budgets; deployment quotas are shared across clients and tool turns |

Before sharing local configs, replace saved keys with environment references.
Keep credentials, run homes, and raw request logs out of Git.
