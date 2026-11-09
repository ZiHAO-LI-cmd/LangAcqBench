export PROJECT_ROOT=/scratch/project_2008161/zihao/LangAcqBench

export APPTAINER_CACHEDIR=/scratch/project_2008161/cache/apptainer-cache
export HF_HOME=/scratch/project_2008161/cache/huggingface

export APPTAINER_TMPDIR="${TMPDIR:?System TMPDIR Not Set}/apptainer-build"

mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$HF_HOME"

# Shared by interactive entry points and Slurm batch launchers.
source "$PROJECT_ROOT/scripts/lib/load-api-keys.sh"
langacqbench_load_api_keys "${LANGACQBENCH_ENV_FILE:-$PROJECT_ROOT/.env}"
