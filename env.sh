export PROJECT_ROOT=/scratch/project_2008161/zihao/LangAcqBench

export APPTAINER_CACHEDIR=/scratch/project_2008161/cache/apptainer-cache
export HF_HOME=/scratch/project_2008161/cache/huggingface

export APPTAINER_TMPDIR="${TMPDIR:?System TMPDIR Not Set}/apptainer-build"

mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR" "$HF_HOME"
