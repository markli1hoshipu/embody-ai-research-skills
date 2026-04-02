---
name: deploy-libero-plus
description: >
  Set up the LIBERO-Plus robustness benchmark for evaluating Vision-Language-Action
  (VLA) models on HPC clusters. Covers conda environment setup, asset download,
  required patches, and task category structure across 7 perturbation dimensions.
  Use this skill whenever someone needs to install LIBERO-Plus, understand its
  perturbation categories (camera, robot state, lighting, textures, noise, objects,
  language), find task ID ranges, or debug common deployment issues like EGL
  rendering failures, torch.load errors, or robosuite log path conflicts on
  shared clusters.
license: MIT
metadata:
  skill-author: Embody AI
---

# Deploy LIBERO-Plus Benchmark on HPC

LIBERO-Plus is a robustness benchmark for VLA models with 10,030 tasks spanning
7 perturbation dimensions. It extends the original LIBERO benchmark (libero_10,
libero_spatial, libero_object, libero_goal) by adding systematic perturbations
to camera viewpoints, robot states, lighting, textures, noise, object layouts,
and language instructions.

This skill covers setting up LIBERO-Plus as a standalone benchmark environment.
For running a specific model against it, see the model-specific eval skill
(e.g. `eval-lingbot-va`).

---

## Step 1: Conda Environment

Python 3.10 is the sweet spot — numpy 1.22.4 and robosuite 1.4.0 need it.

```bash
conda create -p /pm/<user>/libero-plus python=3.10 -y
conda activate /pm/<user>/libero-plus

# cmake must be installed via conda (not pip) so it's visible during
# pip's build isolation when compiling egl_probe
conda install -c conda-forge cmake fontconfig imagemagick -y

git clone https://github.com/sylvestf/LIBERO-plus.git
cd LIBERO-plus
pip install -e .
pip install -r extra_requirements.txt   # wand, scikit-image
pip install -r requirements.txt          # robosuite, robomimic, hydra, etc.
```

On shared clusters, packages sometimes install to `~/.local` instead of the
conda env. If imports fail on compute nodes, force-install into the env:

```bash
pip install --target=$(python -c "import site; print(site.getsitepackages()[0])") \
  python-dateutil pytz typing_extensions
```

---

## Step 2: Download Assets (~6.4GB)

```bash
hf download Sylvest/LIBERO-plus assets.zip --repo-type dataset \
  --local-dir /path/to/LIBERO-plus/

cd LIBERO-plus/libero/libero
unzip assets.zip -d .
```

The zip contains a deeply nested path. After extraction, move to the right place:

```bash
mv inspire/hdd/project/embodied-multimodality/public/syfei/libero_new/release/dataset/LIBERO-plus-0/assets ./assets
rm -rf inspire
```

**Cluster tip**: The zip has 457K small files. Extraction on shared filesystems
(NFS/Lustre) can take 30+ minutes. Extract to local `/tmp` first, then `mv`.

Expected structure:
```
LIBERO-plus/libero/libero/assets/
├── articulated_objects/
├── new_objects/
├── scenes/
├── stable_hope_objects/
├── stable_scanned_objects/
├── textures/
├── turbosquid_objects/
├── serving_region.xml
├── wall_frames.stl
└── wall.xml
```

---

## Step 3: LIBERO Config

LIBERO triggers an interactive prompt on first import if no config exists.
This breaks batch jobs. Pre-create the config on shared storage:

```bash
mkdir -p /shared_work/<user>/.libero
cat > /shared_work/<user>/.libero/config.yaml << 'EOF'
benchmark_root: /path/to/LIBERO-plus/libero/libero
bddl_files: /path/to/LIBERO-plus/libero/libero/bddl_files
init_states: /path/to/LIBERO-plus/libero/libero/init_files
datasets: /path/to/datasets
assets: /path/to/LIBERO-plus/libero/libero/assets
EOF
```

Set in all SLURM scripts: `export LIBERO_CONFIG_PATH=/shared_work/<user>/.libero`

Use a shared path (not `~/.libero`) because compute nodes may not share the
same home directory as the submit node.

---

## Step 4: Required Patches

### 4.1 Robosuite log path

**Problem**: robosuite hardcodes `/tmp/robosuite.log` — fails if another user
owns that file on a shared node.

**File**: `<conda-env>/site-packages/robosuite/utils/log_utils.py`

```python
# Add at top:
import os

# Change line ~71 from:
fh = logging.FileHandler("/tmp/robosuite.log")
# To:
fh = logging.FileHandler(os.path.join(os.environ.get("TMPDIR", "/tmp"), "robosuite.log"))
```

### 4.2 torch.load weights_only

**Problem**: PyTorch 2.6+ defaults `weights_only=True`, but LIBERO init states
contain numpy arrays that fail the safety check.

**File**: `LIBERO-plus/libero/libero/benchmark/__init__.py`

Change all `torch.load(init_states_path)` to
`torch.load(init_states_path, weights_only=False)`.

---

## Task Categories and ID Ranges

Tasks are classified in `LIBERO-plus/libero/libero/benchmark/task_classification.json`.
Each task belongs to exactly one perturbation dimension.

### libero_10 (2519 tasks)

| Category              | Task ID Range | Count |
|-----------------------|---------------|-------|
| Background Textures   | 0 – 288       | 289   |
| Robot Initial States  | 289 – 681     | 393   |
| Camera Viewpoints     | 682 – 1100    | 419   |
| Language Instructions | 1101 – 1483   | 383   |
| Sensor Noise          | 1484 – 1932   | 449   |
| Objects Layout        | 1933 – 2244   | 312   |
| Light Conditions      | 2245 – 2518   | 274   |

### Other benchmarks

| Benchmark      | Tasks |
|----------------|-------|
| libero_spatial | 2,402 |
| libero_object  | 2,518 |
| libero_goal    | 2,591 |
| **Total**      | **10,030** |

Each benchmark has roughly the same 7 perturbation categories.

### Querying categories programmatically

```python
import json
with open("LIBERO-plus/libero/libero/benchmark/task_classification.json") as f:
    data = json.load(f)

from collections import Counter
cats = Counter(t["category"] for t in data["libero_10"])
for cat, count in sorted(cats.items(), key=lambda x: -x[1]):
    print(f"{cat}: {count}")
```

### Evaluation protocol

Per the LIBERO-Plus README: use `num_trials_per_task=1` (the original LIBERO
uses 50). Each task already represents a specific perturbation instance, so
one trial per task provides the perturbation coverage.

---

## Verification

Quick sanity check that everything works:

```bash
conda activate /pm/<user>/libero-plus
export LIBERO_CONFIG_PATH=/shared_work/<user>/.libero
export TMPDIR=/shared_work/<user>/.cache/tmp

python -c "
from libero.libero import benchmark, get_libero_path
print('assets:', get_libero_path('assets'))
bd = benchmark.get_benchmark_dict()
inst = bd['libero_10']()
print(f'libero_10: {inst.get_num_tasks()} tasks')
print(f'First task: {inst.get_task(0).language}')
"
```

Expected: 2519 tasks, no interactive prompts, no import errors.

---

## EGL Rendering Note

The LIBERO simulator uses MuJoCo with EGL offscreen rendering, which requires
a GPU with OpenGL support. SLURM jobs that need rendering must request at least
1 GPU (`--gres=gpu:1`), even if the model inference runs on a different GPU.
On H100s, EGL rendering uses <1GB VRAM so it can share a GPU with a model.
