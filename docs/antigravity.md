# Antigravity CLI on Roihu

Antigravity CLI uses the native `agy` executable with Gemini API-key
configuration. Follow the [shared workflow](agent-common.md) for environment
setup, the base image, GPU allocation, submission rules, and logs.

## Build once

After the [shared setup](agent-common.md#prepare-the-environment):

```bash
bash scripts/download-antigravity.sh 1.5.3 arm64
apptainer build --fakeroot --bind="$TMPDIR:/tmp" \
  containers/antigravity.sif antigravity.def
AGENT=antigravity bash scripts/in-container.sh agy --version
```

The helper follows the official bootstrapper's manifest service without running
the bootstrapper or `agy install`. It requires the manifest version to match the
requested version, verifies the payload's SHA-512, extracts only the executable,
and checks its ELF architecture. It records the payload, manifest, binary,
version, platform, and local checksum in `build-antigravity/`.

An optional third argument supplies an archived manifest while its upstream
payload remains available; the second argument also accepts `amd64`/`x64`:

```bash
bash scripts/download-antigravity.sh 1.5.3 arm64 /path/to/saved/release.json
```

The SIF's packaged binary is read-only; in-container updater behavior is
unverified. Download and rebuild explicitly when upgrading.

## Interactive use and authentication

Set `GEMINI_API_KEY` in the ignored `.env` using the
[shared key setup](agent-common.md#api-keys-and-clean-environments). A key alone
does not select the Gemini provider; create these settings for a new home
(merge `modelProvider` if the file already exists):

```bash
mkdir -p interactive/antigravity/home/.gemini/antigravity-cli
chmod 700 interactive/antigravity/home \
  interactive/antigravity/home/.gemini \
  interactive/antigravity/home/.gemini/antigravity-cli
cat > interactive/antigravity/home/.gemini/antigravity-cli/settings.json <<'JSON'
{
  "modelProvider": "gemini"
}
JSON
chmod 600 interactive/antigravity/home/.gemini/antigravity-cli/settings.json

AGENT=antigravity bash scripts/in-container.sh agy models
AGENT=antigravity bash scripts/in-container.sh
```

Task files use `interactive/antigravity/work/`. Account OAuth uses upstream
keyring services that this wrapper does not provision; it is unverified here
and is not copied into batch jobs. API-key usage follows Gemini API billing
and access rules.

## Submit experiments

Choose a model reported by `agy models` inside the actual job image:

```bash
sbatch --export=ALL,AGENT=antigravity scripts/gpu-check.sh

bash scripts/submit-agent.sh antigravity gemini-4-argon \
  configs/smollm3-swedish.train-only.example.json high
```

The optional fourth argument becomes `--effort LEVEL`. The launcher accepts
`low`, `medium`, `high`, `xhigh`, and `max`, subject to model/CLI support.
The tested Argon CLI accepted `low/medium/high` and rejected `xhigh/max`.
Prefer bare `gemini-4-argon` for separate effort selection; a suffixed model
such as `gemini-4-argon-high` rejects a conflicting explicit level.

## Runtime and credentials

Each job creates minimal Gemini settings without copying interactive hooks,
plugins, custom models, or sessions. Keys stay in the environment; optional
endpoint overrides use `APPTAINERENV_GOOGLE_GEMINI_BASE_URL`.

Headless execution uses `--print`, `--output-format stream-json`, and
`--dangerously-skip-permissions`. It asks the agent to read
`/workspace/prompt.md`; `--print-timeout` follows `num_hours`. Batch settings
disable the nested terminal sandbox, allow access to mounted resources outside
the workspace, and set artifact review to `always-proceed`.

The launcher saves `event=result` → `result.response` to `work/agent-final.md`
when present and preserves the CLI exit status. USD cost is unavailable.

## Validation and references

On **2026-10-23**, CLI **1.4.6** was checked in the real SIF with simulated
Slurm commands, a dummy key, and a local Gemini-compatible HTTP endpoint:

| Model / effort | Captured `thinkingConfig.thinkingLevel` or result |
| --- | --- |
| Bare Argon, `low` / `medium` / `high` | `LOW` / `MEDIUM` / `HIGH` |
| Bare Argon, omitted effort | `MEDIUM`, without a CLI `--effort` flag |
| Argon-high, `high` or omitted | `HIGH` |
| Argon-high, `low` | Rejected by CLI before generation |
| `xhigh` / `max` | Rejected by CLI before generation |
| Invalid level | Rejected by launcher |

Successful cases produced `work/agent-final.md` and left persistent settings
unchanged. Evidence and replay scripts are in
`runs/antigravity-effort-hmibt34l/` (Git-ignored). These checks verify request
construction, without Google inference, Slurm submission, or GPU work. The build
example selects **1.5.3**; it does not establish a repeat of those runtime checks.

- [Authentication](https://antigravity.google/docs/install?tab=cli)
- [Effort](https://antigravity.google/docs/cli/commands/effort/)
- [Headless mode](https://antigravity.google/docs/cli/headless/)
- [Settings](https://antigravity.google/docs/settings?tab=cli)
