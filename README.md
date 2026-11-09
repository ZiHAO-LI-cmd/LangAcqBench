# LangAcqBench

Apptainer and Slurm setup for running language-acquisition experiments on
Roihu-GPU with OpenCode, Codex, Claude Code, Kimi Code, Antigravity CLI, or Grok Build.
The agents share the vLLM base image, prompt template, experiment configuration,
timer, and translation evaluator.

## Guides

- [Shared agent workflow](docs/agent-common.md) — environment and base image,
  API-key forwarding, GPU allocation, submission rules, and logs.
- [Azure model connections and API usage](docs/azure-models.md) — Kimi K3,
  DeepSeek V4.1 Flash, GLM 5.3, Grok 4.7, and GPT-6 configuration,
  API calls, and batch setup across agents.
- [OpenCode on Roihu](docs/opencode.md) — build the default OpenCode image,
  authenticate, check GPU access, submit jobs, and evaluate translations.
- [Codex on Roihu](docs/codex.md) — build and use the standalone Codex CLI in
  the same environment.
- [Claude Code on Roihu](docs/claude.md) — build and use Claude Code CLI in
  the same environment.
- [Kimi Code on Roihu](docs/kimi.md) — prepare a pinned native release,
  build its image, authenticate, and submit experiments.
- [Antigravity CLI on Roihu](docs/antigravity.md) — prepare the native `agy`
  binary, build its image, and submit experiments with Gemini API key authentication.
- [Grok Build on Roihu](docs/grok.md) — prepare a pinned native `grok` binary,
  build its image, and submit experiments with an xAI API key.

## Repository layout

```text
scripts/       Common command entry points (see scripts/README.md)
  agents/      Per-agent Slurm launchers
  downloads/   Pinned CLI release downloaders
  evaluation/  Translation evaluator and report generator
  lib/         Shared configuration, prompt, credential, and job helpers
tools/         Dataset download and token preparation
docs/          Agent-specific operating guides
configs/       Experiment configuration examples
prompt.md      Batch-job prompt template
*.def          Apptainer definitions
```

Local container images, downloaded binaries, credentials, runtime state, run
outputs, models, datasets, and logs are intentionally ignored by Git. Configure
the cluster-specific paths in `env.sh` before following a guide.

See the [script directory guide](scripts/README.md) for entry points and examples.
