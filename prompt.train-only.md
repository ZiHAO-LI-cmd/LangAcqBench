# Objective
Post-train `{model}` from `{model_path}` to improve language capabilities for `{languages}`.

Save your chosen trained model in `/workspace/final_model`, with loading instructions and a brief report of your approach and results.

## Setup
- Provided training data:
{training_data}
- You may train on the provided data, training data you find online, or a mixture of both, subject to the integrity rules below.
- This is a training-only experiment. Official benchmark development and test data and evaluation scripts are not provided.
- Working directory: `/workspace`; Hugging Face cache: `/hf-cache` (isolated for this run).
- Time budget: `{num_hours}` hours. Check remaining time with `bash timer.sh`; the timer is already initialized.

{gpu_info}

## Autonomy and exploration
Operate autonomously without asking for feedback. Choose your own training methods, data mixtures, and experiments. Internet access is available for documentation, packages, and training data. Whether and how to validate during training is up to you. Inspect actual GPU memory and installed packages before training. Save outputs under `/workspace`.

- Treat this as an iterative research task. Continue exploring improvements after establishing a working pipeline.
- Explore several materially different hypotheses as time permits: data quality and coverage, mixture proportions, training objectives or stages, learning rate, training duration, and generation-format compatibility. Screen ideas with small pilots, then allocate more compute to promising ones.
- Maintain an experiment log with hypotheses, data sources, token counts, settings, runtime, observations, and the next decision. Preserve the checkpoint you intend to submit.
- While training is active, use available resources to prepare subsequent data variants or inspect diagnostics.

## Time management and stopping
- Aim to use most of the `{num_hours}`-hour budget for meaningful exploration and optimization. Reserve roughly the final 10–15% for model verification and reporting; adjust using measured runtimes.
- Check `bash timer.sh` before and after major experiments and before deciding to finish. Plan experiments that fit while preserving the finalization reserve.
- Completing an initial plan or saving a candidate model should trigger a review of remaining time and unexplored hypotheses. Continue with useful experiments when they fit; consider smaller pilots or diagnostics if a large run no longer fits.
- Stop exploration when the remaining time is needed for finalization. Earlier stopping requires documented evidence of diminishing returns across distinct approaches, concrete resource or data limitations, or an unresolved blocker. Explain alternatives considered and report unused time. Avoid idle waiting or unchanged repeated experiments merely to consume the budget.
- Before your final response, verify that `/workspace/final_model` loads and generates. Report data usage, experiments, elapsed and remaining time, the reason for stopping, and any unfinished work.

## Integrity rules
1. Only fine-tune from `{model_path}`. Do not substitute another base model or an instruction-tuned version.
2. Do not retrieve, inspect, or use official benchmark test or development splits, their answers, or benchmark evaluation scripts from the host, the internet, caches, or previous runs. This includes public copies.
3. Do not derive training or validation examples from official benchmark items through paraphrasing, perturbation, or seeded generation. Matching general task styles and domains is allowed.
4. Report results honestly. If you report validation metrics, describe what you measured and identify them as your own results, not official benchmark scores. Do not claim unrun evaluations or unfinished training succeeded.
