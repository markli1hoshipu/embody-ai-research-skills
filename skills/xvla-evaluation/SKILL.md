---
name: xvla-evaluation
description: "Set up and run X-VLA model evaluation against BEHAVIOR-1K simulator on a SLURM cluster. Use this skill when deploying X-VLA for BEHAVIOR-1K evaluation, setting up websocket-based policy servers for OmniGibson, creating SLURM sbatch scripts for dual-GPU eval (policy server + simulator), or troubleshooting X-VLA inference in the BEHAVIOR-1K eval pipeline. Trigger on mentions of: X-VLA eval, behavior-1k evaluation, xvla deploy, websocket policy server, omnigibson eval pipeline, deploy_b1k, xvla action server."
---

# X-VLA Evaluation on BEHAVIOR-1K

This skill documents how to run X-VLA model evaluation against the BEHAVIOR-1K OmniGibson simulator. The architecture uses two GPUs: one for the X-VLA action server (websocket) and one for the OmniGibson simulator.

## Prerequisites

You need the `behavior-1k-environment` skill set up first — the BEHAVIOR-1K simulator must be working before running evaluations. See that skill for the full OmniGibson + Isaac Sim setup.

## Architecture

```
GPU 0: X-VLA Action Server (websocket :8000)
  - Loads checkpoint, runs inference
  - Receives observations via websocket
  - Returns actions (23-dim absolute)
  
GPU 1: OmniGibson Simulator (eval.py)
  - Loads scene + R1Pro robot
  - Sends observations to action server
  - Steps physics, records metrics + video
```

The two processes communicate via websocket on port 8000. The SLURM script starts the action server first, waits for it to be ready, then launches the simulator.

## X-VLA Environment Setup

Create a separate conda env for the X-VLA server (it has different dependencies than OmniGibson):

```bash
conda create -p /path/to/envs/xvla python=3.11 -y

# PyTorch with CUDA 12.8 (must match behavior env)
pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
  --index-url https://download.pytorch.org/whl/cu128

# X-VLA dependencies
pip install transformers==4.51.3 peft==0.17.1 einops==0.8.1 timm==1.0.12 \
  safetensors==0.4.5 accelerate==1.2.1 msgpack websockets pillow "numpy<2" \
  scipy fastapi uvicorn mmengine h5py mediapy json_numpy pyarrow av
```

## Project Structure

```
behavior1k-xvla/
├── behavior1k_training/
│   └── deploy_b1k.py          # Websocket action server
├── checkpoints/
│   └── xvla_v3_object/
│       └── task40-200k/       # Model checkpoint
├── X-VLA/
│   └── models/
│       ├── modeling_xvla.py   # XVLA model class
│       └── processing_xvla.py # Observation processor
├── README.md
└── setup.sh
```

`deploy_b1k.py` adds `/path/to/X-VLA` to `sys.path` at runtime to import the model classes. No separate install step needed for X-VLA itself.

## SLURM Sbatch Script

Here's the template for the eval job. Save as `run_eval_xvla.sbatch`:

```bash
#!/bin/bash
#SBATCH --job-name=b1k_xvla
#SBATCH --partition=all
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=48G
#SBATCH --gres=gpu:2
#SBATCH --time=04:00:00
#SBATCH --output=/shared_work/logs/%j_%x.out
#SBATCH --error=/shared_work/logs/%j_%x.err

set -euo pipefail

# --- Configurable parameters ---
export TASK_NAME="${1:-turning_on_radio}"
export CHECKPOINT="${CHECKPOINT:-/shared_work/behavior1k-xvla/checkpoints/xvla_v3_object/task40-200k}"
export ACTION_SERVER_PORT="${ACTION_SERVER_PORT:-8000}"
export LOG_DIR="${LOG_DIR:-/shared_work/logs/behavior_eval}"

# --- Environment paths ---
export CONDA_BASE="/shared_work/miniconda3"
export BEHAVIOR_ENV="${CONDA_BASE}/envs/behavior"
export XVLA_ENV="${CONDA_BASE}/envs/xvla"

# --- Headless mode ---
export OMNIGIBSON_HEADLESS=1
export OMNI_KIT_ACCEPT_EULA=YES

# --- Helper: wait for websocket server ---
wait_for_server() {
    local port=$1 max_wait=300 elapsed=0
    echo "[$(date +%T)] Waiting for action server on port ${port}..."
    while ! ss -tlnp 2>/dev/null | grep -q ":${port} "; do
        sleep 5; elapsed=$((elapsed + 5))
        if [ $elapsed -ge $max_wait ]; then
            echo "ERROR: Action server did not start within ${max_wait}s"; exit 1
        fi
        echo "[$(date +%T)] Still waiting... (${elapsed}s)"
    done
    echo "[$(date +%T)] Action server ready on port ${port} (took ${elapsed}s)"
}

# --- GPU 0: X-VLA Action server ---
echo ">>> Starting X-VLA action server on GPU 0..."
CUDA_VISIBLE_DEVICES=0 "${XVLA_ENV}/bin/python" \
    /shared_work/behavior1k-xvla/behavior1k_training/deploy_b1k.py \
    --model_path "${CHECKPOINT}" \
    --port "${ACTION_SERVER_PORT}" \
    --device cuda &
ACTION_SERVER_PID=$!

wait_for_server "${ACTION_SERVER_PORT}"

# --- GPU 1: OmniGibson Simulator ---
# Use OMNIGIBSON_GPU_ID (not CUDA_VISIBLE_DEVICES) to avoid close_stage segfault
echo ">>> Starting OmniGibson eval on GPU 1..."
OMNIGIBSON_GPU_ID=1 \
    "${BEHAVIOR_ENV}/bin/python" \
    /shared_work/BEHAVIOR-1K/OmniGibson/omnigibson/learning/eval.py \
    headless=true \
    policy=websocket \
    log_path="${LOG_DIR}" \
    task.name="${TASK_NAME}" \
    write_video=true
EVAL_EXIT=$?

# --- Cleanup ---
echo ">>> Eval finished (exit code: ${EVAL_EXIT}). Stopping action server..."
kill "${ACTION_SERVER_PID}" 2>/dev/null || true
wait "${ACTION_SERVER_PID}" 2>/dev/null || true
exit ${EVAL_EXIT}
```

## GPU Assignment Pattern

This is important and non-obvious:

- **X-VLA server** uses `CUDA_VISIBLE_DEVICES=0` — this is fine because the X-VLA process doesn't use Isaac Sim, so hiding GPUs is safe.
- **OmniGibson simulator** uses `OMNIGIBSON_GPU_ID=1` (NOT `CUDA_VISIBLE_DEVICES=1`) — Isaac Sim's `close_stage()` segfaults when the GPU topology changes between init and shutdown. `OMNIGIBSON_GPU_ID` selects the GPU within OmniGibson without hiding others from the process.

## Eval Configuration

The eval uses Hydra configs located in `OmniGibson/omnigibson/learning/configs/`:

```
configs/
├── base_config.yaml      # Wrapper, eval settings
├── policy/
│   ├── websocket.yaml    # Websocket policy (host, port)
│   └── local.yaml        # Local policy
├── robot/
│   └── r1pro.yaml        # R1Pro robot config
└── task/
    └── behavior.yaml     # Task settings
```

Override settings via command line:
```bash
python eval.py headless=true policy=websocket task.name=turning_on_radio write_video=true
```

## Output Structure

```
logs/behavior_eval/
├── metrics/
│   ├── turning_on_radio_242_0.json    # Per-episode metrics
│   └── turning_on_radio_295_0.json
└── videos/
    ├── turning_on_radio_242_0.mp4     # Episode recordings
    └── turning_on_radio_295_0.mp4
```

Each metrics JSON contains:
```json
{
  "agent_distance": {"base": 6.35, "left": 8.55, "right": 17.58},
  "normalized_agent_distance": {"base": 0.31, "left": 0.38, "right": 0.23},
  "q_score": {"final": 0.0},
  "time": {"simulator_steps": 4300, "simulator_time": 143.3, "normalized_time": 0.5}
}
```

- `q_score.final` is the success metric (1.0 = task completed)
- `agent_distance` shows how much the robot moved (base, left arm, right arm)
- `simulator_steps` is typically 4,300 per episode (~143 seconds of sim time)

## Submitting Jobs

```bash
# Default task (turning_on_radio)
ssh trt-node-1 "sbatch /shared_work/meta_scripts/behavior_1k/run_eval_xvla_trt.sbatch"

# Specific task
ssh trt-node-1 "sbatch /shared_work/meta_scripts/behavior_1k/run_eval_xvla_trt.sbatch picking_up_trash"

# Custom checkpoint
ssh trt-node-1 "CHECKPOINT=/path/to/ckpt sbatch /shared_work/meta_scripts/behavior_1k/run_eval_xvla_trt.sbatch"
```

## Monitoring

```bash
# Check queue
ssh trt-node-1 "squeue"

# Watch output
ssh trt-node-1 "tail -f /shared_work/logs/<JOBID>_b1k_xvla.out"

# Check GPU usage
ssh trt-node-1 "nvidia-smi"

# Sync results to local
rsync -avz trt-node-1:/shared_work/logs/behavior_eval/ /shared_work/synced_oldtrt/
```

## Troubleshooting

1. **Port 8000 already in use**: Kill the stale process before resubmitting:
   ```bash
   ssh trt-node-1 "kill \$(lsof -ti:8000)"
   ```

2. **X-VLA inference error**: Check the stderr log for the traceback. Common issue is image format mismatch between OG 3.8.0 obs and X-VLA's CLIP processor. The working version from aaron-workstation handles this correctly.

3. **Simulator crash on startup**: Make sure you're using the correct BEHAVIOR-1K source (from aaron-workstation, with Kit 107.3.1 support). See the `behavior-1k-environment` skill.

4. **Job stuck in PD state**: Check `sinfo` — nodes may be in completing/down state from previous crashed jobs. Resume with `scontrol update NodeName=<name> State=RESUME`.
