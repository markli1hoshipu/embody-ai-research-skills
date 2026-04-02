---
name: behavior-1k-environment
description: "Deploy BEHAVIOR-1K (OmniGibson + Isaac Sim) on RTX 5080/50-series Blackwell GPUs. Use this skill whenever setting up BEHAVIOR-1K, OmniGibson, or Isaac Sim on RTX 5080, RTX 5090, or any Blackwell-architecture GPU. Also use when troubleshooting Isaac Sim material/shader crashes, close_stage segfaults, or Kit version mismatches on newer NVIDIA GPUs. Trigger on mentions of: BEHAVIOR-1K install, OmniGibson setup, Isaac Sim 5080, Blackwell GPU simulator, omnigibson headless, behavior challenge environment."
---

# BEHAVIOR-1K Environment Setup for RTX 5080 (Blackwell)

This skill captures the exact working configuration for running BEHAVIOR-1K / OmniGibson on RTX 5080 GPUs. This was hard-won through extensive debugging — the main branch and standard setup.sh do NOT work on 5080s. Follow these instructions exactly.

## The Critical Insight

The RTX 5080 (Blackwell, sm_120) requires a specific combination of package versions. The most important detail is **Omniverse Kit 107.3.1** — the version from the main branch setup.sh (Kit 106.5.0) causes segfaults when loading material shaders on Blackwell GPUs.

## Working Version Matrix

| Component | Version | Notes |
|---|---|---|
| Python | 3.11 | Required by Isaac Sim 5.1 wheels |
| PyTorch | 2.7.0+cu128 | Stable release with sm_120 support |
| OmniGibson | 3.8.0 | From aaron-workstation, NOT from GitHub main |
| Isaac Sim | 5.1.0.0 | All 26 packages |
| Omniverse Kit | **107.3.1.206797** | CRITICAL — not 106.5.0 |
| NVIDIA Driver | 580+ | Tested with 580.126.09 |
| CUDA (driver) | 13.0 | Via driver, not toolkit |

## Source Code

The OmniGibson source must come from `aaron-workstation` (`/home/aaron/BEHAVIOR-1K/`), not from `git clone https://github.com/StanfordVL/BEHAVIOR-1K.git`. The main branch is missing:

- `BaseRobot` class (in `robots/__init__.py` → `robot_base.py`)
- `RGBLowResWrapper` and other wrappers (in `learning/wrappers/`)
- `model_name` attribute on robots (main branch uses `model`)
- `KIT_FILES` mapping for `(5, 1, 0)` in `simulator.py`
- `omnigibson_5_1_0.kit` file

To get the source:
```bash
# SSH into aaron-workstation (guest account)
SSH_ASKPASS=/tmp/sshpass.sh SSH_ASKPASS_REQUIRE=force \
  rsync -avz --exclude='.git/' --exclude='appdata/' --exclude='__pycache__/' \
  --exclude='datasets/' --exclude='logging/' \
  -e "ssh -i ~/.ssh/id_ed25519_mark" \
  guest@192.168.50.10:/home/aaron/BEHAVIOR-1K/ /destination/BEHAVIOR-1K/
```

See `references/aaron-workstation-access.md` for SSH details.

## Step-by-Step Installation

### 1. Create conda environment
```bash
conda create -p /path/to/envs/behavior python=3.11 -y
```

### 2. Install PyTorch 2.7.0 with CUDA 12.8
```bash
pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
  --index-url https://download.pytorch.org/whl/cu128
```

### 3. Install Isaac Sim 5.1.0 with Kit 107.3.1

Download all 26 wheels from pypi.nvidia.com and install together. The package names use underscores but the PyPI URLs use hyphens.

```bash
TMPDIR=$(mktemp -d)
PACKAGES=(
  "omniverse_kit-107.3.1.206797"
  "isaacsim_kernel-5.1.0.0" "isaacsim_app-5.1.0.0" "isaacsim_core-5.1.0.0"
  "isaacsim_gui-5.1.0.0" "isaacsim_utils-5.1.0.0" "isaacsim_storage-5.1.0.0"
  "isaacsim_asset-5.1.0.0" "isaacsim_sensor-5.1.0.0" "isaacsim_robot_motion-5.1.0.0"
  "isaacsim_robot-5.1.0.0" "isaacsim_benchmark-5.1.0.0" "isaacsim_code_editor-5.1.0.0"
  "isaacsim_ros1-5.1.0.0" "isaacsim_cortex-5.1.0.0" "isaacsim_example-5.1.0.0"
  "isaacsim_replicator-5.1.0.0" "isaacsim_rl-5.1.0.0" "isaacsim_robot_setup-5.1.0.0"
  "isaacsim_ros2-5.1.0.0" "isaacsim_template-5.1.0.0" "isaacsim_test-5.1.0.0"
  "isaacsim-5.1.0.0" "isaacsim_extscache_physics-5.1.0.0"
  "isaacsim_extscache_kit-5.1.0.0" "isaacsim_extscache_kit_sdk-5.1.0.0"
)
WHEELS=()
for pkg in "${PACKAGES[@]}"; do
  pkg_name=${pkg%-*}
  filename="${pkg}-cp311-none-manylinux_2_35_x86_64.whl"
  url="https://pypi.nvidia.com/${pkg_name//_/-}/${filename}"
  curl -sL "$url" -o "$TMPDIR/$filename"
  WHEELS+=("$TMPDIR/$filename")
done
pip install "${WHEELS[@]}"
rm -rf "$TMPDIR"
```

### 4. Install OmniGibson (with --no-deps to avoid bddl conflict)
```bash
pip install --no-deps -e /path/to/BEHAVIOR-1K/OmniGibson
```

### 5. Install joylo and bddl3 from the repo
```bash
pip install -e /path/to/BEHAVIOR-1K/joylo
pip install -e /path/to/BEHAVIOR-1K/bddl3
```

### 6. Install remaining dependencies

Use the pip freeze from the working env (see `references/requirements_5080.txt`) or install individually:

```bash
pip install hydra-core omegaconf av pandas msgpack google-auth google-cloud-storage \
  "numpy<2" cffi==1.17.1 addict ipython h5py pillow==11.0.0 "websockets>=15.0.1" \
  transforms3d huggingface_hub rich opencv-python
```

### 7. Install g++ (needed by PyTorch inductor for JIT compilation)
```bash
sudo apt-get install -y g++
```

### 8. Download datasets
```bash
OMNIGIBSON_HEADLESS=1 OMNI_KIT_ACCEPT_EULA=YES python -m omnigibson.utils.asset_utils \
  --download_omnigibson_robot_assets --download_behavior_1k_assets \
  --download_2025_challenge_task_instances --accept_license
```
Dataset is ~33GB (behavior-1k-assets 3.7.2rc1).

## Running Headless

Set these environment variables:
```bash
export OMNIGIBSON_HEADLESS=1
export OMNI_KIT_ACCEPT_EULA=YES
```

To select a specific GPU, use `OMNIGIBSON_GPU_ID` (not `CUDA_VISIBLE_DEVICES`):
```bash
export OMNIGIBSON_GPU_ID=1  # Use GPU 1
```

`CUDA_VISIBLE_DEVICES` hides GPUs from the process, which causes Isaac Sim's `close_stage()` to segfault when the GPU topology changes between init and shutdown.

## Verification Test

```python
import os
os.environ["OMNIGIBSON_HEADLESS"] = "1"
os.environ["OMNI_KIT_ACCEPT_EULA"] = "YES"

import omnigibson as og
from omnigibson.macros import gm
gm.USE_GPU_DYNAMICS = True
gm.ENABLE_FLATCACHE = True
gm.ENABLE_OBJECT_STATES = False
gm.ENABLE_TRANSITION_RULES = False

cfg = {
    "scene": {
        "type": "InteractiveTraversableScene",
        "scene_model": "Rs_int",
        "load_object_categories": ["floors", "walls", "ceilings"],
    },
    "robots": [{"type": "Fetch", "obs_modalities": ["rgb"]}],
}
env = og.Environment(configs=cfg)
for i in range(10):
    obs, reward, terminated, truncated, info = env.step(env.action_space.sample())
    print(f"Step {i+1}/10 OK")
env.close()
```

All 10 steps should complete. A crash dump on shutdown (`close_stage`) is cosmetic — ignore it.

## Known Issues

1. **Shutdown segfault**: Isaac Sim's `close_stage()` segfaults on exit. This is cosmetic — all computation completes before the crash. Ignore it.

2. **PyTorch sm_120 warning**: PyTorch 2.7.0+cu128 may emit a warning about sm_120 compatibility. It works via PTX forward compatibility with driver 580+. Ignore the warning.

3. **First launch slow**: First launch takes 2-3 minutes for shader compilation. Subsequent launches are faster due to caching.

4. **Main branch incompatibility**: Do NOT use `git clone https://github.com/StanfordVL/BEHAVIOR-1K.git` — the main branch has Kit 106.5.0 which segfaults on material loading with Blackwell GPUs.
