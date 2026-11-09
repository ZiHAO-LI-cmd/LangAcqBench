# Claude Code on Roihu

Claude Code uses the repository's shared Apptainer and experiment workflow.
Follow the [common guide](agent-common.md) for environment setup, the base image,
GPU allocation, submission rules, and logs.

## Build once

After the [shared setup](agent-common.md#prepare-the-environment):

```bash
bash scripts/downloads/download-claude.sh 2.1.319
apptainer build --fakeroot --bind="$TMPDIR:/tmp" containers/claude.sif claude.def
AGENT=claude bash scripts/in-container.sh claude --version
```

The helper runs Anthropic's official installer in a temporary home and copies
the prepared binary into `build-claude/`, recording local SHA-256 checksums for
the binary and installer. Build on Roihu-GPU so the installer selects the target
architecture. The image pins that version and disables in-job auto-updates.

## Interactive use and authentication

For browser login:

```bash
AGENT=claude bash scripts/in-container.sh claude auth login
AGENT=claude bash scripts/in-container.sh claude auth status
AGENT=claude bash scripts/in-container.sh
```

Credentials are stored in
`interactive/claude/home/.claude/.credentials.json`; task files use
`interactive/claude/work/`.

For API-key authentication, set `ANTHROPIC_API_KEY` in the ignored `.env` as
shown in the [shared key setup](agent-common.md#api-keys-and-clean-environments),
then launch normally. On first use, approve the key if prompted. The key takes
precedence over subscription OAuth. Console/API usage is billed separately
from a Claude subscription.

## Submit experiments

```bash
sbatch --export=ALL,AGENT=claude scripts/gpu-check.sh

bash scripts/submit-agent.sh claude sonnet \
  configs/smollm3-swedish.example.json high
```

Use a model alias or ID available to your account. The optional fourth argument
becomes `--effort LEVEL`; the launcher accepts `low`, `medium`, `high`, `xhigh`,
and `max`, subject to model support. Omit it to use the CLI default.

## Runtime and credentials

The launcher uses `claude -p --output-format stream-json --verbose`, reads the
prompt from stdin, and enables unattended tools with
`--dangerously-skip-permissions`. It saves the final response, when present, to
`work/agent-final.md` and preserves the CLI exit status.

API-key jobs receive the key through the environment and do not take the OAuth
lock. Without a key, the launcher copies the interactive OAuth credential into
the private job home and atomically saves refreshed credentials on exit. A
nonblocking lock rejects a second batch job using the same login immediately.
Avoid interactive login/logout or use of that OAuth login while a batch job is
active; interactive commands do not acquire the lock. SIGKILL or node failure
can prevent credential copy-back and require a fresh login.

## Validation and references

The build and submission commands are operating instructions, not validation
records. Check the installed CLI version and authentication before a short run;
inspect [logs and requested artifacts](agent-common.md#outputs-and-monitoring)
to establish completion.

- [Claude Code documentation](https://code.claude.com/docs/en/overview)
