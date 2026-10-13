# Objective
Post-train `{model}` from `{model_path}` to achieve the best performance on benchmarks for `{languages}`.

Benchmarks:
- Translation tasks: `{translation_tasks}`.
    - Translation directions: `{translation_directions}`.
- Monolingual tasks (`lm_eval` task IDs): `{monolingual_tasks}`.

Save your best trained model in `/workspace/final_model`, with loading instructions and a brief report of your approach and actual results.

## Setup
- Available training data (host path → path inside this agent container):
{training_data}
- Held-out test data: `/data/test`.
- Working directory: `/workspace`; Hugging Face cache: `/hf-cache`.
- `evaluate.sh` is the launcher for translation and optional `lm_eval` monolingual tasks.
- Time budget: `{num_hours}` hours. Check remaining time with `bash timer.sh`.

{gpu_info}

## Autonomy
Operate autonomously without asking for feedback. Choose your own data sources, methods, and experiments. Internet access is unrestricted. Work within the time and allocated resources, and save your outputs under `/workspace`.

## Exploration and validation
- Treat this as an iterative research task. A working training pipeline and an improvement over the base model are milestones; continue investigating how to improve the best model within the available budget.
- Establish base-model validation scores early. Use development data for experiment decisions. If an appropriate development set is unavailable, hold out a fixed subset of permitted training data before training. Cover both translation and the requested monolingual capabilities where applicable, and keep validation examples out of training and data generation.
- Maintain an experiment log under `/workspace`. For each experiment, record the hypothesis, data sources and mixture, token count, training settings, runtime, validation results, and the next decision. Record regressions as well as gains, and select checkpoints using validation results.
- Explore several materially different hypotheses as the budget permits, such as data quality and coverage, mixture proportions, training objectives or stages, learning rate and training duration, and prompt-format compatibility. Use small pilot experiments to screen ideas, then allocate more compute to promising ones.
- After each experiment, identify the largest remaining weakness and choose the next experiment from the evidence. Investigate regressions, compare alternatives, and check whether improvements persist across validation examples. Revisit initial assumptions when results contradict them.
- While a long training run is active, use available resources for useful work such as preparing the next data variant, inspecting training diagnostics, or planning validation. Preserve the best checkpoint throughout the search so that unsuccessful experiments do not jeopardize delivery.

## Time management and stopping
- Aim to use most of the `{num_hours}`-hour budget for meaningful exploration and optimization. Reserve roughly the final 10–15% for final evaluation, model verification, and reporting; adjust this reserve using measured evaluation and save times.
- Check `bash timer.sh` before and after major experiments and before deciding to finish. Estimate whether the next experiment fits while preserving the finalization reserve. The timer is already initialized; keep its original deadline.
- Completing an initial plan or saving a candidate model should trigger a review of remaining time and unexplored hypotheses. When useful experiments still fit, extend the plan and continue. If a large run no longer fits, consider a smaller pilot, a targeted diagnostic, or a checkpoint comparison.
- Stop exploration when the remaining time is needed for finalization. Earlier stopping requires evidence that no useful experiment is feasible: document diminishing returns across distinct approaches, concrete resource or data limitations, or an unresolved blocker. Explain alternatives considered and report unused time. Avoid idle waiting or repeating unchanged experiments merely to consume the budget.
- Freeze model selection before accessing held-out test data. Run final test evaluation only after choosing the final model from validation results; final test scores must not guide further training or selection.
- Before your final response, ensure all required training and evaluations have completed or explicitly report them as unfinished. Verify `/workspace/final_model` loads, preserve actual results, and include an experiment summary, elapsed and remaining time, and the reason for stopping in the report.

## Integrity rules
1. Only fine-tune from `{model_path}`. Do not substitute another base model or an instruction-tuned version.
2. Do not inspect or use held-out test questions, reference translations, or answers for training, data generation, prompt tuning, or model selection. Access test data only through the provided evaluators for final evaluation; do not tune on final test scores.
3. Do not derive training examples from test items through paraphrasing, perturbation, seeded generation, or targeted examples. These restrictions also apply to test copies found online. Matching general task styles and domains is allowed.
4. Do not modify or bypass `evaluate-mt.py`, `evaluate.sh`, test data, or scoring logic. Do not leak reference answers into model inputs, hard-code test answers, or replace model predictions with answer lookups.
5. Report results honestly. Do not fabricate scores or claim unrun evaluations or unfinished training succeeded. If an evaluator or task is unavailable, report it as not run.
