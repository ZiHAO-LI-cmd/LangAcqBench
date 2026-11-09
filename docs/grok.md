# Grok Build on Roihu

Grok Build uses the native `grok` executable. Follow the
[shared workflow](agent-common.md) for environment setup, the base image, GPU
allocation, submission rules, and logs. Azure Grok 4.7 configuration is in
[Azure models](azure-models.md#grok-build).

## Build once

After the [shared setup](agent-common.md#prepare-the-environment):

```bash
bash scripts/download-grok.sh 1.0.70 arm64
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/grok.sif grok.def
AGENT=grok bash scripts/in-container.sh grok --version
```

The helper downloads the requested version's flat binary from the official
artifact locations without executing it. It checks ELF architecture and records
the URL, version, platform, and local SHA-256 in `build-grok/`. It accepts
`arm64`/`aarch64` or `amd64`/`x64`/`x86_64`, with an optional trusted SHA-256 as
the third argument. Without that digest, the local checksum records build input
integrity rather than upstream authenticity. The image verifies the checksum
and disables updates with `GROK_DISABLE_AUTOUPDATER=1`.

## Interactive use and authentication

For the default xAI endpoint, read and forward the API key:

```bash
read -r -s -p 'xAI API key: ' APPTAINERENV_XAI_API_KEY
printf '\n'
export APPTAINERENV_XAI_API_KEY
AGENT=grok bash scripts/in-container.sh
```

Interactive account login is also available:

```bash
AGENT=grok bash scripts/in-container.sh grok login --device-auth
```

Stored account tokens take precedence over `XAI_API_KEY`. Configuration and
credentials live in `interactive/grok/home/.grok/`; task files use
`interactive/grok/work/`. Batch jobs reuse `config.toml` and saved API keys,
but do not copy interactive OAuth `auth.json` or sessions. A plain host
`XAI_API_KEY` is not forwarded through `--cleanenv`.

## Submit experiments

Inspect the installed CLI's `/model` and `/effort` menus for supported values:

```bash
sbatch --export=ALL,AGENT=grok scripts/gpu-check.sh

MODEL_ID='replace-with-a-model-id-from-the-installed-grok-model-menu'
bash scripts/submit-agent.sh grok "$MODEL_ID" \
  configs/smollm3-swedish.example.json high
```

The optional fourth argument becomes `--reasoning-effort LEVEL`. The launcher
accepts `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, and `max`, subject to
the model's declared levels. Omit it for the configured default. Azure Grok 4.7
uses `low/medium/high/xhigh`; `max` was rejected by the tested deployment.

## Runtime and credentials

The launcher copies the persistent `config.toml` into the private job home with
mode `600`. `GROK_CONFIG_FILE` selects another config; relative paths resolve
against `SLURM_SUBMIT_DIR`. Without a saved or explicit config, it creates
minimal settings for the default xAI endpoint. Referenced hooks/plugins must
be suitable for batch use; their files are not copied.

Headless execution uses `--prompt-file /workspace/prompt.md`,
`--output-format streaming-messages-json`, and `--yolo --sandbox off`.
The terminal `type: result` record supplies `work/agent-final.md` from its string
`result` field and USD cost from `total_cost_usd`, when present. Missing cost is
reported as unavailable. The launcher preserves the CLI exit status.

## Validation and references

Historical Azure effort requests and CLI checks used Grok Build **1.0.62**;
see [results and logs](azure-models.md#validation). They did not cover a full
Grok tool-call cycle or GPU experiment. The build example selects **1.0.70**;
it does not establish that those checks were repeated on the newer version.

- [Official releases and installation](https://github.com/xai-org/grok-build#installing-the-released-binary)
- [Authentication](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md)
- [Headless mode](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/14-headless-mode.md)
