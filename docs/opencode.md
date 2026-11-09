# OpenCode on Roihu

OpenCode is the repository's default agent. Follow the
[shared workflow](agent-common.md) for environment setup, the base image, GPU
allocation, submission rules, and logs. Azure Kimi K3, DeepSeek V4.1 Flash, and
GLM 5.3 configuration is in [Azure models](azure-models.md#opencode).

## Build once

After the [shared setup](agent-common.md#prepare-the-environment):

```bash
bash scripts/download-opencode.sh 1.19.5
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/opencode.sif opencode.def
AGENT=opencode bash scripts/in-container.sh opencode --version
```

The helper downloads the official Linux ARM64 release archive, extracts the
executable, and records a local SHA-256 in `build-opencode/`. The image verifies
the checksum and checks the CLI and Python evaluation dependencies.

## Interactive use and authentication

```bash
AGENT=opencode bash scripts/in-container.sh opencode auth login
AGENT=opencode bash scripts/in-container.sh opencode models
AGENT=opencode bash scripts/in-container.sh
```

Follow the provider login prompts. Credentials are in
`interactive/home/.local/share/opencode/auth.json`; custom providers are defined
in `interactive/home/.config/opencode/opencode.json`. Put task inputs in
`interactive/work/`. Use a complete `provider/model` identifier from the model
list. Azure providers with explicit API-key references need no provider login;
the batch launcher still requires the local `auth.json` file.

## Submit experiments

```bash
sbatch --export=ALL,AGENT=opencode scripts/gpu-check.sh

MODEL_ID='provider/model'
bash scripts/submit-agent.sh opencode "$MODEL_ID" \
  configs/smollm3-swedish.example.json high
```

The optional fourth argument becomes `opencode run --variant LEVEL`. The selected
provider/model must define that variant. For Azure models, use the explicit
[variant mappings](azure-models.md#effort).

## Runtime and credentials

The launcher runs `opencode run --format json` with automatic tool permissions.
It copies `auth.json` and snapshots only the selected provider definition from
`opencode.json`, preserving endpoints, deployment IDs, credentials, and variants.
Other interactive settings and sessions are not copied.
Environment-variable credentials require `APPTAINERENV_*` forwarding.
`APPTAINERENV_OPENCODE_CONFIG_CONTENT` overrides saved provider settings; clear
stale overrides when using the saved configuration.

Agent events go to `agent.jsonl`, and internal logs go to `agent.err`. This
launcher does not create `work/agent-final.md`; inspect the event stream for the
assistant response. Shared output paths and monitoring commands are in the
[common guide](agent-common.md#outputs-and-monitoring).

## Validation and references

Historical Azure connectivity, tool-call, and effort-forwarding checks used
OpenCode **1.19.2**; see [results and logs](azure-models.md#validation).
The build example above selects **1.19.5** and does not establish that the same
runtime checks were repeated on that version.

- [Configuration](https://opencode.ai/docs/config/)
- [Custom providers](https://opencode.ai/docs/providers/#custom-provider)
- [Model variants](https://opencode.ai/docs/models/#variants)
