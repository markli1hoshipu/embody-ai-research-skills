---
name: eval-fastwam
description: >
  Deploy and evaluate FastWAM (Fast World Action Model) on LIBERO and LIBERO-Plus
  benchmarks. Covers environment setup, checkpoint download, Wan2.2 model preparation,
  single-GPU and multi-GPU evaluation, per-task and per-category result aggregation.
  Use this skill whenever someone needs to install FastWAM, run inference on LIBERO
  tasks, debug model loading issues (CUDA version mismatch, HF repo redirects,
  ActionDiT preprocessing), parallelize evaluation across GPUs, or compare FastWAM
  results against other VLA models like LingBot-VA.
license: MIT
metadata:
  skill-author: Embody AI
---

# Evaluate FastWAM on LIBERO / LIBERO-Plus

FastWAM is a 6B parameter world-action model (5B video DiT + 1B action DiT) built
on the Wan2.2 backbone. It uses flow matching for joint video-action generation
with a Mixture-of-Transformers architecture.

- Paper: https://arxiv.org/abs/2603.16666
- Repo: https://github.com/yuantianyuan01/FastWAM
- Checkpoints: https://huggingface.co/yuanty/fastwam

---

## Architecture

FastWAM eval is **single-process** — each GPU loads the full model AND runs the
simulator. No client-server split. This means:
- Each eval job needs 1 GPU (~15GB VRAM for model + EGL rendering)
- Parallelism via multiple independent jobs, each handling different tasks
- Model loads once per job (~3 min), then runs tasks sequentially (~30s each)

---

## Step 1: Environment Setup

```bash
# Create venv (uv is fastest)
uv venv /pm/<user>/fastwam-env --python 3.10
source /pm/<user>/fastwam-env/bin/activate

# Bootstrap pip
uv pip install pip setuptools wheel --python /pm/<user>/fastwam-env/bin/python

# Install PyTorch — must match cluster CUDA driver version
# Check driver: nvidia-smi | grep "CUDA Version"
# CUDA 12.4 cluster → use cu124
pip install torch==2.6.0+cu124 torchvision==0.21.0+cu124 \
    --extra-index-url https://download.pytorch.org/whl/cu124

# Install FastWAM (no-deps to avoid torch version conflict)
git clone https://github.com/yuantianyuan01/FastWAM.git
cd FastWAM
pip install -e . --no-deps

# Install remaining deps manually (skipping torch)
pip install accelerate==1.12.0 av==16.0.1 datasets==3.6.0 deepspeed==0.18.5 \
    einops==0.8.1 hydra-core==1.3.2 imageio==2.37.0 imageio-ffmpeg==0.6.0 \
    omegaconf==2.3.0 pandas==2.2.3 safetensors==0.5.3 transformers==4.49.0 \
    wandb==0.23.1 tqdm==4.66.5 rich==14.2.0 huggingface-hub==0.29.2 \
    regex==2025.11.3 jsonlines==4.0.0 termcolor==2.5.0 torchcodec==0.5 \
    pyarrow==23.0.0 gitpython==3.1.45 boto3==1.35.99 modelscope==1.34.0

# Fix numpy for robosuite compatibility
pip install numpy==1.26.4
```

### CUDA Version Compatibility

This is the most common deployment issue. torch 2.7+ needs CUDA 12.8+ drivers.
Most clusters run CUDA 12.4. Check with `nvidia-smi` and install the matching
torch build:

| CUDA Driver | torch version |
|-------------|--------------|
| 12.4 | `torch==2.6.0+cu124` |
| 12.6 | `torch==2.7.1+cu126` |
| 12.8+ | `torch==2.7.1+cu128` (README default) |

---

## Step 2: Download Checkpoints

```bash
mkdir -p checkpoints/fastwam_release
python -c "
from huggingface_hub import hf_hub_download
for f in ['libero_uncond_2cam224.pt', 'libero_uncond_2cam224_dataset_stats.json']:
    hf_hub_download('yuanty/fastwam', f, local_dir='checkpoints/fastwam_release')
"
```

Each checkpoint is ~12GB. For RoboTwin, also download `robotwin_uncond_3cam_384.pt`
and its stats JSON.

---

## Step 3: Download Wan2.2 Base Model

The model loader downloads Wan2.2 components at first run. Pre-download to avoid
hangs during SLURM jobs:

```bash
export DIFFSYNTH_MODEL_BASE_PATH="$(pwd)/checkpoints"
export DIFFSYNTH_DOWNLOAD_SOURCE=huggingface  # avoid slow modelscope downloads

python -c "
from huggingface_hub import snapshot_download
snapshot_download('Wan-AI/Wan2.2-TI2V-5B',
    local_dir='checkpoints/Wan-AI/Wan2.2-TI2V-5B')
"
```

This downloads ~32GB (DiT weights, VAE, text encoder, tokenizer).

### ActionDiT Preprocessing

The README mentions `preprocess_action_dit_backbone.py` — this is **only needed
for training**, not inference. The eval config sets `skip_dit_load_from_pretrain=true`
and `action_dit_pretrained_path=null`, so skip this step for evaluation.

---

## Step 4: Model Config Fix

The default config tries to redirect model downloads to a private HF repo. Disable:

```yaml
# In configs/model/fastwam.yaml, change:
redirect_common_files: false  # was: true
```

---

## Step 5: Install LIBERO / LIBERO-Plus

FastWAM uses `libero.libero.benchmark` for task loading. Install LIBERO-Plus
(see `deploy-libero-plus` skill) or original LIBERO.

Key: the `libero` package has a nested `libero/libero/` structure that breaks
editable installs. Use PYTHONPATH instead:

```bash
export PYTHONPATH="/path/to/LIBERO-plus:$PYTHONPATH"
```

Also install LIBERO's runtime deps into the fastwam env:

```bash
pip install robosuite==1.4.0 robomimic==0.2.0 bddl==1.0.1 gym==0.25.2 \
    mujoco==3.3.2 future matplotlib wand scikit-image easydict opencv-python
```

For `wand` (ImageMagick Python bindings), you need `libMagickWand`. Without sudo,
install via conda in a separate env and set:

```bash
export LD_LIBRARY_PATH="/path/to/conda-env-with-imagemagick/lib:$LD_LIBRARY_PATH"
```

### Required Patches

Same patches as `deploy-libero-plus` skill:
- `robosuite/utils/log_utils.py`: Fix hardcoded `/tmp/robosuite.log`
- `benchmark/__init__.py`: `torch.load(..., weights_only=False)`
- `envs/env_wrapper.py`: `bddl_file_name = str(bddl_file_name)` for PosixPath fix

---

## Step 6: LIBERO Config

```bash
mkdir -p /shared_work/<user>/.libero
cat > /shared_work/<user>/.libero/config.yaml << 'EOF'
benchmark_root: /path/to/LIBERO-plus/libero/libero
bddl_files: /path/to/LIBERO-plus/libero/libero/bddl_files
init_states: /path/to/LIBERO-plus/libero/libero/init_files
datasets: /path/to/datasets
assets: /path/to/LIBERO-plus/libero/libero/assets
EOF

export LIBERO_CONFIG_PATH=/shared_work/<user>/.libero
```

---

## Step 7: Single-Task Evaluation

```bash
python experiments/libero/eval_libero_single.py \
    task=libero_uncond_2cam224_1e-4 \
    ckpt=./checkpoints/fastwam_release/libero_uncond_2cam224.pt \
    EVALUATION.dataset_stats_path=./checkpoints/fastwam_release/libero_uncond_2cam224_dataset_stats.json \
    EVALUATION.task_suite_name=libero_10 \
    EVALUATION.task_id=0 \
    EVALUATION.num_trials=1 \
    gpu_id=0
```

### Inference Speed

- Model load: ~3 min (one-time per process)
- Per inference call: ~0.3s (10 denoising steps, 32 actions predicted, 10 executed)
- Per episode: ~30s (with replan_steps=10)
- First call: ~1.2s (warmup)

---

## Step 8: Multi-Task Evaluation (Batch)

Use `eval_libero_range.py` to evaluate a range of tasks with a single model load:

```python
# eval_libero_range.py loads the model once, then loops over task IDs
# Set TASK_START and TASK_END via environment variables
export TASK_START=0
export TASK_END=289

python experiments/libero/eval_libero_range.py \
    task=libero_uncond_2cam224_1e-4 \
    ckpt=./checkpoints/fastwam_release/libero_uncond_2cam224.pt \
    EVALUATION.dataset_stats_path=./checkpoints/fastwam_release/libero_uncond_2cam224_dataset_stats.json \
    EVALUATION.task_suite_name=libero_10 \
    EVALUATION.task_id=0 \
    EVALUATION.num_trials=1 \
    EVALUATION.output_dir=./evaluate_results/libero_plus/bg_textures \
    gpu_id=0
```

The script skips tasks with existing result files, so it can resume after crashes.

### SLURM Template

```bash
#!/bin/bash
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=80G
#SBATCH --time=3-00:00:00

export PYTHONUNBUFFERED=1
export LIBERO_CONFIG_PATH=/shared_work/<user>/.libero
export DIFFSYNTH_MODEL_BASE_PATH=/path/to/FastWAM/checkpoints
export DIFFSYNTH_DOWNLOAD_SOURCE=huggingface
export TASK_START=0
export TASK_END=289

source /pm/<user>/fastwam-env/bin/activate
export PYTHONPATH="/path/to/LIBERO-plus:$PYTHONPATH"
export LD_LIBRARY_PATH="/path/to/imagemagick-lib:$LD_LIBRARY_PATH"
cd /path/to/FastWAM

python experiments/libero/eval_libero_range.py \
    task=libero_uncond_2cam224_1e-4 \
    ckpt=./checkpoints/fastwam_release/libero_uncond_2cam224.pt \
    EVALUATION.dataset_stats_path=./checkpoints/fastwam_release/libero_uncond_2cam224_dataset_stats.json \
    EVALUATION.task_suite_name=libero_10 \
    EVALUATION.task_id=0 \
    EVALUATION.num_trials=1 \
    EVALUATION.output_dir=./evaluate_results/libero_plus/<category> \
    gpu_id=0
```

---

## Step 9: Parallelization (LIBERO-Plus)

LIBERO-Plus has 2519 tasks per suite. Split across multiple 1-GPU jobs:

```bash
# 7 jobs, one per perturbation category for libero_10
# Task ID ranges from task_classification.json:
# bg_textures:   0-288   (289 tasks)
# robot_states:  289-681 (393 tasks)
# camera_views:  682-1100 (419 tasks)
# lang_instr:    1101-1483 (383 tasks)
# sensor_noise:  1484-1932 (449 tasks)
# obj_layout:    1933-2244 (312 tasks)
# light_conds:   2245-2518 (274 tasks)

for args in "0 289 bg_textures" "289 682 robot_states" ...; do
    read start end cat <<< "$args"
    TASK_START=$start TASK_END=$end \
    OUT_DIR=./evaluate_results/libero_plus/${cat} \
    sbatch eval_fastwam.sbatch
done
```

At ~30s/task, each job takes 2-4 hours.

---

## Step 10: Original LIBERO (50 trials)

For standard LIBERO evaluation with 50 trials per task:

```bash
python experiments/libero/eval_libero_range.py \
    task=libero_uncond_2cam224_1e-4 \
    ckpt=./checkpoints/fastwam_release/libero_uncond_2cam224.pt \
    EVALUATION.dataset_stats_path=./checkpoints/fastwam_release/libero_uncond_2cam224_dataset_stats.json \
    EVALUATION.task_suite_name=libero_10 \
    EVALUATION.task_id=0 \
    EVALUATION.num_trials=50 \
    EVALUATION.output_dir=./evaluate_results/libero_original_50trials \
    gpu_id=0
```

Set `LIBERO_CONFIG_PATH` to original LIBERO (not LIBERO-Plus) config.

---

## Result Aggregation

Results are saved as JSON per task: `<output_dir>/<suite>/gpu<N>_task<ID>_results.json`

```bash
# Per-category success rate
python3 -c "
import json, glob, sys
files = sorted(glob.glob(sys.argv[1] + '/*.json'))
total = len(files)
succ = sum(1 for f in files if json.load(open(f))['succ_rate'] > 0
           if 'succ_rate' in json.load(open(f))
           else json.load(open(f)).get('successes', 0) > 0)
print(f'{succ}/{total} = {succ/total*100:.1f}%')
" ./evaluate_results/libero_plus/<category>/<suite>/
```

---

## Baseline Results (FastWAM on LIBERO-Plus, libero_10)

| Perturbation | Success Rate |
|-------------|-------------|
| Language Instructions | 60.1% |
| Objects Layout | 61.2% |
| Light Conditions | 52.2% |
| Robot Initial States | 45.3% |
| Sensor Noise | 28.5% |
| Background Textures | 22.8% |
| Camera Viewpoints | 17.7% |

Original LIBERO (50 trials): 95.6% (libero_10), 97.6% (spatial), 99.8% (object), 96.2% (goal).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `CUDA initialization: driver too old` | torch compiled for newer CUDA than driver | Install torch matching your CUDA driver (see Step 1) |
| `RepositoryNotFoundError: DiffSynth-Studio/...` | Private HF repo redirect | Set `redirect_common_files: false` in `configs/model/fastwam.yaml` |
| `RuntimeError: CMake must be installed` (egl_probe) | cmake not visible during pip build | Install cmake via conda, not pip |
| `PosixPath is not iterable` | LIBERO-Plus env_wrapper.py bug | Add `bddl_file_name = str(bddl_file_name)` |
| `ImportError: MagickWand shared library not found` | ImageMagick not installed | Set `LD_LIBRARY_PATH` to conda env with imagemagick |
| Model loads but no output | Python stdout buffered | Set `PYTHONUNBUFFERED=1` |
| `Preprocessing ActionDiT backbone...` hangs | Downloading Wan2.2 via modelscope (slow) | Set `DIFFSYNTH_DOWNLOAD_SOURCE=huggingface` and pre-download |
