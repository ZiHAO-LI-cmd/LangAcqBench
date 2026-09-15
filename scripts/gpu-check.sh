#!/bin/bash
#SBATCH --job-name=opencode-gpu-check
#SBATCH --account=project_2008161
#SBATCH --partition=gputest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --gres=gpu:gh200:1
#SBATCH --time=0-00:15:00
#SBATCH --output=logs/gpu-check-%j.out
#SBATCH --error=logs/gpu-check-%j.err

set -euo pipefail
source "$SLURM_SUBMIT_DIR/env.sh"

export RUN_DIR="$PROJECT_ROOT/runs/gpu-check-$SLURM_JOB_ID"
export USE_GPU=1

srun bash "$PROJECT_ROOT/scripts/in-container.sh" python3 -c '
import torch

assert torch.cuda.is_available(), "CUDA unavailable"
print("PyTorch:", torch.__version__)
print("GPU:", torch.cuda.get_device_name(0))

x = torch.randn(512, 512, device="cuda")
loss = (x @ x).square().mean()
torch.cuda.synchronize()
print("GPU computation OK:", loss.item())
'