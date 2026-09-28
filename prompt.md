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

## Integrity rules
1. Only fine-tune from `{model_path}`. Do not substitute another base model or an instruction-tuned version.
2. Do not inspect or use held-out test questions, reference translations, or answers for training, data generation, prompt tuning, or model selection. Access test data only through the provided evaluators for final evaluation; do not tune on final test scores.
3. Do not derive training examples from test items through paraphrasing, perturbation, seeded generation, or targeted examples. These restrictions also apply to test copies found online. Matching general task styles and domains is allowed.
4. Do not modify or bypass `evaluate-mt.py`, `evaluate.sh`, test data, or scoring logic. Do not leak reference answers into model inputs, hard-code test answers, or replace model predictions with answer lookups.
5. Report results honestly. Do not fabricate scores or claim unrun evaluations or unfinished training succeeded. If an evaluator or task is unavailable, report it as not run.
