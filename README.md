# LangAcqBench

Apptainer and Slurm setup for running language-acquisition experiments on
Roihu-GPU with OpenCode or Codex. Both agents share the vLLM base image, prompt
template, experiment configuration, timer, and translation evaluator.

## Guides

- [OpenCode on Roihu](docs/opencode.md) — build the default OpenCode image,
  authenticate, check GPU access, submit jobs, and evaluate translations.
- [Codex on Roihu](docs/codex.md) — build and use the standalone Codex CLI in
  the same environment.

## Repository layout

```text
scripts/       Download helpers, container entry point, Slurm launchers, prompt renderer
docs/          Agent-specific operating guides
configs/       Experiment configuration examples
prompt.md      Batch-job prompt template
*.def          Apptainer definitions
```

Local container images, downloaded binaries, credentials, runtime state, run
outputs, models, datasets, and logs are intentionally ignored by Git. Configure
the cluster-specific paths in `env.sh` before following either guide.
