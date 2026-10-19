# LangAcqBench

Apptainer and Slurm setup for running language-acquisition experiments on
Roihu-GPU with OpenCode, Codex, Claude Code, Kimi Code, or Antigravity CLI.
The agents share the vLLM base image, prompt template, experiment configuration,
timer, and translation evaluator.

## Guides

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

## Repository layout

```text
scripts/       Evaluator, download helpers, container entry point, Slurm launchers, prompt renderer
docs/          Agent-specific operating guides
configs/       Experiment configuration examples
prompt.md      Batch-job prompt template
prompt.train-only.md  Training-only batch-job prompt template
*.def          Apptainer definitions
```

Local container images, downloaded binaries, credentials, runtime state, run
outputs, models, datasets, and logs are intentionally ignored by Git. Configure
the cluster-specific paths in `env.sh` before following a guide.
