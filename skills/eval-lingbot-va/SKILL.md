---
name: eval-lingbot-va
description: >
  Run LingBot-VA (Wan-VA) evaluation on LIBERO-Plus or LIBERO benchmarks using
  SLURM. Covers the client-server architecture (model server + simulator client
  on 1 GPU), SLURM sbatch scripts, parallel evaluation across multiple GPUs,
  checkpoint swapping, monitoring progress, and aggregating results. Use this
  skill whenever someone needs to evaluate a LingBot-VA checkpoint, parallelize
  VLA inference jobs, debug websocket connection issues between server and client,
  fix KV cache dtype mismatches, or interpret per-category success rates across
  perturbation dimensions.
license: MIT
metadata:
  skill-author: Embody AI
---

# Evaluate LingBot-VA on LIBERO-Plus

This skill covers running LingBot-VA (a 5.3B video-action diffusion model built
on Wan2.2) against the LIBERO-Plus benchmark on SLURM clusters. It assumes
LIBERO-Plus is already deployed — see the `deploy-libero-plus` skill for that.

---

## Architecture

LingBot-VA eval uses a **client-server design on a single GPU**:

```
┌─────────────────── 1x H100 GPU (~30-35GB VRAM) ───────────────────┐
│                                                                     │
│  Server (lingbot-va venv)           Client (libero-plus conda)     │
│  ┌──────────────────────┐           ┌─────────────────────────┐    │
│  │ WanTransformer (24GB)│◄─websocket─│ MuJoCo/robosuite EGL   │    │
│  │ VAE + UMT5 encoder   │           │ LIBERO-Plus simulator   │    │
│  │ Flow-match diffusion  │──actions──►│ 128x128 2-cam render   │    │
│  └──────────────────────┘           └─────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

Per inference call: 20 video denoising steps + 50 action denoising steps → 16
action steps in ~4.3s. A full 800-step episode takes ~4 minutes.

Both processes share one GPU (~30GB total), leaving headroom on 80GB H100s. This
means you can run **8 parallel eval jobs on an 8-GPU node**.

---

## Prerequisites

1. **LIBERO-Plus conda env** — see `deploy-libero-plus` skill
2. **LingBot-VA venv** — server environment:
   ```bash
   cd /path/to/lingbot-va
   python -m venv venv && source venv/bin/activate
   pip install -r requirements.txt
   # torch>=2.9, diffusers>=0.36, transformers>=4.55, flash_attn
   ```
3. **A checkpoint** with `transformer/`, `vae/`, `text_encoder/`, `tokenizer/` subdirs

---

## Required Patches

### KV cache dtype mismatch

The cache is allocated in bf16 but keys/values may arrive in fp32.

**File**: `lingbot-va/wan_va/modules/model.py` (~line 235)

```python
# Change:
cache['k'][:, slots] = key
cache['v'][:, slots] = value
# To:
cache['k'][:, slots] = key.to(cache['k'].dtype)
cache['v'][:, slots] = value.to(cache['v'].dtype)
```

### Client script modifications

**File**: `lingbot-va/wan_va/launch_libero_client.py`

The client imports `wan_va` which pulls in diffusers/torch — unavailable in
the conda env. Required changes:

- **LIBERO path**: Set `LIBERO_SOURCE_DIR` to your LIBERO-Plus path
- **Remove lerobot dep**: Replace `from lerobot.datasets.utils import write_json`
  with inline `json.dump`
- **Avoid heavy imports**: Inline `WebsocketClientPolicy` class (or add the
  deploy dir to sys.path and import `msgpack_numpy` directly) to skip
  `wan_va/__init__.py`
- **Add --host arg**: Needed for cross-node websocket connections
- **Fix obs keys**: Use `observation.images.agentview_rgb` and
  `observation.images.eye_in_hand_rgb` to match the server's `obs_cam_keys`

---

## Checkpoint Configuration

Edit `lingbot-va/wan_va/configs/va_libero_cfg.py`:

```python
va_libero_cfg.wan22_pretrained_model_name_or_path = "/path/to/checkpoint"
```

To swap checkpoints: update this path and resubmit jobs. If the checkpoint is on
a node's local disk (e.g. `/work/`), copy to shared storage first:

```bash
srun --nodelist=<node> cp -r /work/path/to/ckpt /shared_work/path/to/ckpt
```

---

## SLURM Evaluation Script

The sbatch script (`eval_liberoplus.sbatch`) runs server + client in one job:

```bash
#!/bin/bash
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=120G
#SBATCH --time=3-00:00:00
#SBATCH --partition=compute
#SBATCH --qos=high

# Derive unique ports from job ID to avoid collisions
PORT=$((29000 + (SLURM_JOB_ID % 500) * 2))
DIST_PORT=$((PORT + 100))

# --- Server (lingbot-va venv, background) ---
source /path/to/lingbot-va/venv/bin/activate
export PYTHONPATH="/path/to/lingbot-va/lingbot-va:$PYTHONPATH"

python -m torch.distributed.run --nproc_per_node 1 --master_port $DIST_PORT \
  /path/to/lingbot-va/lingbot-va/wan_va/wan_va_server.py \
  --config-name libero --port $PORT &
SERVER_PID=$!

# Wait for server to be ready
while ! ss -tlnp | grep -q ":${PORT} "; do sleep 5; done

# --- Client (libero-plus conda env) ---
source /path/to/miniconda3/etc/profile.d/conda.sh
conda activate /pm/<user>/libero-plus
export PYTHONPATH="/path/to/lingbot-va/lingbot-va:$PYTHONPATH"
export LIBERO_CONFIG_PATH=/shared_work/<user>/.libero

python /path/to/lingbot-va/lingbot-va/wan_va/launch_libero_client.py \
  --libero-benchmark "$BENCHMARK" --host 127.0.0.1 --port "$PORT" \
  --test-num "$TEST_NUM" --task_range $TASK_START $TASK_END \
  --out-dir "$OUT_DIR"

kill $SERVER_PID
```

### Environment variables

| Variable   | Default     | Description                             |
|------------|-------------|-----------------------------------------|
| BENCHMARK  | libero_10   | Benchmark name                          |
| TEST_NUM   | 1           | Trials per task (1 for LIBERO-Plus)     |
| TASK_START | 0           | First task index (inclusive)             |
| TASK_END   | 10          | Last task index (exclusive)             |
| OUT_DIR    | .../results | Output directory                        |

### Basic usage

```bash
TASK_START=289 TASK_END=682 TEST_NUM=1 \
OUT_DIR=/path/to/results/robot_states \
sbatch eval_liberoplus.sbatch
```

---

## Parallelization

Split task ranges across multiple jobs. All write to the same output directory
(files are named by task ID, no collisions).

### Example: 8 parallel jobs for one category

```bash
python3 -c "
start, end, n = 289, 682, 8
per = (end - start) // n
rem = (end - start) % n
pos = start
for i in range(n):
    size = per + (1 if i < rem else 0)
    print(f'{pos} {pos+size} {i}')
    pos += size
" | while read s e i; do
    TASK_START=$s TASK_END=$e TEST_NUM=1 \
    OUT_DIR=/path/to/results/robot_states \
    sbatch --job-name="lp_rs_${i}" eval_liberoplus.sbatch
done
```

### All 7 categories at once

```bash
declare -A CATS=(
  [bg_textures]="0 289"
  [robot_states]="289 682"
  [camera_views]="682 1101"
  [lang_instr]="1101 1484"
  [sensor_noise]="1484 1933"
  [obj_layout]="1933 2245"
  [light_conds]="2245 2519"
)

for cat in "${!CATS[@]}"; do
    read start end <<< "${CATS[$cat]}"
    TASK_START=$start TASK_END=$end TEST_NUM=1 \
    OUT_DIR=/path/to/results/${cat} \
    sbatch --job-name="lp_${cat}" eval_liberoplus.sbatch
done
```

### Timing estimates (H100)

| Tasks | 1 job   | 4 jobs  | 8 jobs  |
|-------|---------|---------|---------|
| 289   | ~19h    | ~5h     | ~2.5h   |
| 393   | ~26h    | ~6.5h   | ~3.3h   |
| 449   | ~30h    | ~7.5h   | ~3.8h   |

### Cluster limits

Check your account limits: `sacctmgr show assoc user=$USER format=MaxSubmitJobs,MaxJobs`

Common limits: 5-10 submitted jobs, 5 running concurrently. Submit in waves —
pending jobs start automatically as running jobs finish.

---

## Monitoring

### Per-job progress

```bash
# Episodes completed
grep "Success rate" /path/to/logs/lingbot_liberoplus_<jobid>.out | wc -l

# Successes
grep -c "success num: 1" /path/to/logs/lingbot_liberoplus_<jobid>.out

# Live watch
tail -f /path/to/logs/lingbot_liberoplus_<jobid>.out
```

### Aggregate per category

```bash
python3 -c "
import json, glob, sys
files = sorted(glob.glob(sys.argv[1] + '/*.json'))
total = len(files)
succ = sum(1 for f in files if json.load(open(f))['succ_rate'] > 0)
print(f'{succ}/{total} = {succ/total*100:.1f}%')
" /path/to/results/<category>
```

### Full benchmark summary

```bash
python3 -c "
import json, glob, os, sys
base = sys.argv[1]
for cat in sorted(os.listdir(base)):
    path = os.path.join(base, cat)
    if not os.path.isdir(path): continue
    files = glob.glob(path + '/*.json')
    if not files: continue
    total = len(files)
    succ = sum(1 for f in files if json.load(open(f))['succ_rate'] > 0)
    print(f'{cat:25s} {succ:4d}/{total:4d} = {succ/total*100:5.1f}%')
" /path/to/results/
```

---

## Baseline Results

lingbot-va-checkpoint-4000 on libero_10 (1 trial/task, partial results):

| Perturbation          | Success Rate |
|-----------------------|-------------|
| Language Instructions | 69%         |
| Robot Initial States  | 56%         |
| Objects Layout        | 47%         |
| Sensor Noise          | 45%         |
| Light Conditions      | 41%         |
| Background Textures   | 28%         |
| Camera Viewpoints     | 16%         |

---

## Training Reference

The local repo is inference-only. Training code is at
https://github.com/Robbyant/lingbot-va (latest version).

- **Dataset**: LeRobot v0.3.3 + pre-extracted VAE latents
- **Launch**: `NGPU=8 bash script/run_va_posttrain.sh`
- **Hyperparams**: lr=1e-5, AdamW (β1=0.9, β2=0.95), bf16, 3K steps
- **Important**: Set `"attn_mode": "flex"` in `transformer/config.json` for
  training; switch back to `"torch"` for inference

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `PermissionError: /tmp/robosuite.log` | Another user owns the file | Patch robosuite to use `$TMPDIR` (see deploy-libero-plus skill) |
| `RuntimeError: BFloat16 for destination and Float for source` | KV cache dtype mismatch | Patch model.py (see above) |
| `EOFError: EOF when reading a line` | Missing LIBERO config | Set `LIBERO_CONFIG_PATH` env var |
| `ModuleNotFoundError: diffusers` in client | Client importing full wan_va package | Inline WebsocketClientPolicy |
| `EGLError` / `MjRenderContext` errors | No GPU for EGL rendering | Ensure `--gres=gpu:1` in sbatch |
| `EADDRINUSE` on server start | Port collision with parallel job | Ports derived from SLURM_JOB_ID |
| Server loads but client can't connect | Different nodes | Use `--host` with server hostname |
