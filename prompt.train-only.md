# Objective
Post-train `{model}` from `{model_path}` to improve language capabilities for `{languages}`.

Design your own validation protocol using held-out portions
of the provided training data, and use it to guide experiments.

Save your best trained model in `/workspace/final_model`, with loading instructions and a brief report of your approach and actual validation results.

## Setup
- Provided training data:
{training_data}
- This is a training-only experiment. Official test data, development data, and benchmark evaluation scripts are not provided. Construct your own validation splits and tools from the permitted training data.
- Working directory: `/workspace`; Hugging Face cache: `/hf-cache` (isolated for this run).
- Time budget: `{num_hours}` hours. Check remaining time with `bash timer.sh`; the timer is already initialized.

{gpu_info}

## Autonomy and exploration
Operate autonomously without asking for feedback. Choose your own training methods, data mixtures, and experiments. Internet access is available for documentation, packages, and additional training sources subject to the integrity rules below. Inspect actual GPU memory and installed packages before training. Save outputs under `/workspace`.

- Treat this as an iterative research task. Continue exploring improvements after establishing a working pipeline and a model that improves over the base model.
- Before training, create fixed validation splits from training sources. Split by document or source group where possible, remove overlap, and keep validation examples out of training and synthetic-data generation. Preserve the split procedure and seed.
- Build validation tools that measure translation and the requested language capabilities using only these splits. Include held-out loss and suitable task metrics or general capability probes where feasible. Establish a base-model baseline and use the same validation protocol for candidate comparisons.
- Explore several materially different hypotheses as time permits: data quality and coverage, mixture proportions, training objectives or stages, learning rate, training duration, and generation-format compatibility. Screen ideas with small pilots, then allocate more compute to promising ones.
- After each experiment, identify remaining weaknesses and investigate regressions. Maintain an experiment log with hypotheses, data sources, token counts, settings, runtime, validation results, and the next decision. Select checkpoints using your validation results and preserve the best checkpoint throughout the search.
- While training is active, use available resources to prepare subsequent data variants, inspect diagnostics, or improve validation.

## Time management and stopping
- Aim to use most of the `{num_hours}`-hour budget for meaningful exploration and optimization. Reserve roughly the final 10–15% for final validation, model verification, and reporting; adjust using measured runtimes.
- Check `bash timer.sh` before and after major experiments and before deciding to finish. Plan experiments that fit while preserving the finalization reserve.
- Completing an initial plan or saving a candidate model should trigger a review of remaining time and unexplored hypotheses. Continue with useful experiments when they fit; consider smaller pilots or diagnostics if a large run no longer fits.
- Stop exploration when the remaining time is needed for finalization. Earlier stopping requires documented evidence of diminishing returns across distinct approaches, concrete resource or data limitations, or an unresolved blocker. Explain alternatives considered and report unused time. Avoid idle waiting or unchanged repeated experiments merely to consume the budget.
- Before your final response, verify that `/workspace/final_model` loads and generates, and report unfinished work explicitly. Include actual validation results, data usage, the experiment summary, elapsed and remaining time, and the reason for stopping. Official benchmark scores are unavailable in this run; identify all reported metrics as your own validation results.

## Integrity rules
1. Only fine-tune from `{model_path}`. Do not substitute another base model or an instruction-tuned version.
2. Use only training sources for training and for constructing your own validation sets. Do not retrieve, inspect, or use official benchmark test or development splits, their answers, or evaluation scripts from the host, the internet, caches, or previous runs. This includes public copies of the named benchmarks.
3. Do not derive training or validation examples from official benchmark items through paraphrasing, perturbation, or seeded generation. General task styles and domains may inform probes built from permitted training sources.
4. Keep your held-out validation examples out of training and data generation. Do not leak reference answers into validation inputs or replace predictions with answer lookups.
5. Report results honestly. Do not fabricate benchmark scores or label training-derived validation scores as official results. Do not claim unrun evaluations or unfinished training succeeded.
