# NVIDIA GPU Setup on Kali Linux (Optimus Laptops)

> Complete guide to install, configure, and use NVIDIA GPU on-demand for any application on Kali Linux with hybrid Intel + NVIDIA graphics (Optimus).

## System Used
- **OS:** Kali Linux (Rolling)
- **GPU:** NVIDIA GeForce RTX 3050 Mobile (GA107M)
- **Driver:** 550.163.01
- **CUDA:** 12.4
- **Desktop:** Wayland
- **Method:** PRIME Offloading via `switcherooctl`

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Install NVIDIA Drivers](#install-nvidia-drivers)
3. [Verify Installation](#verify-installation)
4. [Setup GPU On-Demand](#setup-gpu-on-demand)
5. [gpu-run Wrapper](#gpu-run-wrapper)
6. [Running Applications on GPU](#running-applications-on-gpu)
7. [Persistence Mode](#persistence-mode)
8. [Python & CUDA Setup](#python--cuda-setup)
9. [Troubleshooting](#troubleshooting)
10. [Cheat Sheet](#cheat-sheet)

---

## Prerequisites

- Kali Linux installed (bare metal, not VM)
- NVIDIA Optimus laptop (Intel iGPU + NVIDIA dGPU)
- Internet connection
- sudo privileges

---

## Install NVIDIA Drivers

### Step 1 — Update system

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2 — Detect your GPU

```bash
nvidia-detect
```

This tells you which driver version to install.

### Step 3 — Install NVIDIA driver

```bash
sudo apt install nvidia-driver nvidia-driver-bin nvidia-settings -y
```

### Step 4 — Install CUDA toolkit (optional but recommended)

```bash
sudo apt install nvidia-cuda-toolkit -y
```

### Step 5 — Reboot

```bash
sudo reboot
```

---

## Verify Installation

After reboot, run these checks:

### Check driver is loaded

```bash
nvidia-smi
```

Expected output: shows GPU name, driver version, CUDA version, temperature.

### Check current renderer

```bash
glxinfo | grep "OpenGL renderer"
```

> On Optimus laptops this will show Intel by default — that is **normal and correct**.

### Check both GPUs are detected

```bash
switcherooctl list
```

Expected output:
```
Device: 0
  Name:        Intel Corporation Alder Lake-P Integrated Graphics
  Default:     yes
  Discrete:    no

Device: 1
  Name:        NVIDIA Corporation GA107M [GeForce RTX 3050 Mobile]
  Default:     no
  Discrete:    yes
```

### Check installed NVIDIA packages

```bash
dpkg -l | grep -E "nvidia|prime"
```

---

## Setup GPU On-Demand

### Install switcheroo-control

```bash
sudo apt install switcheroo-control -y
```

### Enable and start the service

```bash
sudo systemctl enable switcheroo-control --now
```

### Verify service is running

```bash
sudo systemctl status switcheroo-control
```

### Verify both GPUs detected

```bash
switcherooctl list
```

---

## gpu-run Wrapper

Create a universal wrapper script to launch any app on the NVIDIA GPU:

```bash
sudo tee /usr/local/bin/gpu-run << 'EOF'
#!/bin/bash

APP="$1"
shift

case "$APP" in
    # Electron apps (VS Code, Brave, Chromium, etc.) — need Wayland/X11 flag
    code|antigravity|brave-browser|brave|chromium|electron|slack|discord|obsidian)
        exec switcherooctl launch --gpu 1 "$APP" --enable-features=UseOzonePlatform --ozone-platform=x11 "$@"
        ;;
    # JetBrains Toolbox — installed in home directory
    jetbrains-toolbox)
        exec switcherooctl launch --gpu 1 /home/$USER/.local/share/JetBrains/$(ls /home/$USER/.local/share/JetBrains/ | grep jetbrains-toolbox | tail -1)/bin/jetbrains-toolbox "$@"
        ;;
    # Flatpak apps — use env vars instead of switcherooctl
    gimp)
        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia org.gimp.GIMP "$@"
        ;;
    kdenlive)
        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia org.kde.kdenlive "$@"
        ;;
    heroic)
        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia com.heroicgameslauncher.hgl "$@"
        ;;
    vesktop|discord)
        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia dev.vencord.Vesktop "$@"
        ;;
    zen)
        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia app.zen_browser.zen "$@"
        ;;
    # Everything else
    *)
        exec switcherooctl launch --gpu 1 "$APP" "$@"
        ;;
esac
EOF
```

### Make it executable

```bash
sudo chmod +x /usr/local/bin/gpu-run
```

### Verify it was created correctly

```bash
cat /usr/local/bin/gpu-run
```

---

## Running Applications on GPU

### System apps

```bash
gpu-run code                # VS Code
gpu-run antigravity         # Antigravity (VS Code fork)
gpu-run pycharm             # PyCharm
gpu-run jetbrains-toolbox   # JetBrains Toolbox
```

### Flatpak apps

```bash
gpu-run kdenlive            # Kdenlive video editor
gpu-run heroic              # Heroic Games Launcher
gpu-run gimp                # GIMP image editor
gpu-run vesktop             # Vesktop (Discord)
gpu-run zen                 # Zen Browser
```

### Any other app

```bash
gpu-run appname
```

### Adding a new Flatpak app

First find its app ID:
```bash
flatpak list --app
```

Then run it directly:
```bash
flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia <APP_ID>
```

Or add it to `gpu-run`:
```bash
sudo nano /usr/local/bin/gpu-run
```

---

## Verify App is Using GPU

### Method 1 — nvidia-smi

```bash
nvidia-smi
```

The app should appear under **Processes** section.

### Method 2 — Watch live

```bash
watch -n 1 nvidia-smi
```

### Method 3 — Check renderer

```bash
gpu-run glxinfo | grep "OpenGL renderer"
# Should show: NVIDIA GeForce RTX 3050
```

---

## Persistence Mode

Keeps the NVIDIA driver loaded in memory permanently so apps start faster.

### Enable manually

```bash
sudo nvidia-smi -pm 1
```

### Disable

```bash
sudo nvidia-smi -pm 0
```

### Enable permanently on boot

```bash
sudo tee /etc/systemd/system/nvidia-persistence.service << 'EOF'
[Unit]
Description=NVIDIA Persistence Mode
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm 1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable nvidia-persistence.service --now
```

### Verify persistence mode is on

```bash
nvidia-smi | grep Persistence
# Should show: Persistence-M: On
```

---

## Python & CUDA Setup

### Verify CUDA is available in Python

```python
import torch
print(torch.cuda.is_available())    # True
print(torch.cuda.get_device_name(0))  # NVIDIA GeForce RTX 3050
```

### Install PyTorch with CUDA 12.4

```bash
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
```

### Run Python script on GPU

CUDA always uses the NVIDIA GPU directly — no `gpu-run` needed for Python scripts:

```bash
python3 train.py
```

### Run PyCharm on GPU (for GPU monitoring inside IDE)

```bash
gpu-run pycharm
```

---

## Troubleshooting

### `switcherooctl list` returns empty

```bash
sudo systemctl enable switcheroo-control --now
sudo systemctl status switcheroo-control
```

### App not showing in nvidia-smi

1. You may be on Wayland — Electron apps need extra flags (already handled in `gpu-run`)
2. For Flatpak apps, use the `flatpak run --env=...` method
3. Check the binary name: `which appname`

### `gpu-run appname` gives FileNotFoundError

The binary doesn't exist at that name. Find it:
```bash
which appname
find / -name "appname" 2>/dev/null | head -5
```

Then add the full path to `gpu-run`.

### nvidia-smi not found

```bash
sudo apt install nvidia-smi -y
```

### Driver not loading after reboot

```bash
sudo modprobe nvidia
lsmod | grep nvidia
```

### Check Xorg is using NVIDIA

```bash
nvidia-smi | grep Xorg
```

---

## Cheat Sheet

| Task | Command |
|------|---------|
| Check GPU status | `nvidia-smi` |
| Watch GPU live | `watch -n 1 nvidia-smi` |
| List both GPUs | `switcherooctl list` |
| Run app on NVIDIA | `gpu-run appname` |
| Check current renderer | `glxinfo \| grep "OpenGL renderer"` |
| Enable persistence mode | `sudo nvidia-smi -pm 1` |
| Check session type | `echo $XDG_SESSION_TYPE` |
| List Flatpak apps | `flatpak list --app` |
| Find binary path | `which appname` |

---

## Notes

- On Optimus laptops, the display is physically connected to Intel GPU — NVIDIA does offscreen rendering and passes frames to Intel. This is normal.
- Intel GPU is used by default to save battery. Use `gpu-run` only when you need GPU acceleration.
- Wayland sessions require special flags for Electron apps — the `gpu-run` wrapper handles this automatically.
- CUDA workloads (PyTorch, TensorFlow) always use NVIDIA directly without needing `gpu-run`.

---

## Author

**shrijesh** — Kali Linux NVIDIA GPU Setup
