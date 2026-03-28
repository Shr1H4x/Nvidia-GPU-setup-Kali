#!/bin/bash
# =============================================================================
# check.sh — Full system check for NVIDIA GPU setup on Kali Linux
# Checks everything configured during setup:
#   - NVIDIA driver & nvidia-smi
#   - Kernel module & DRM modeset
#   - CUDA toolkit
#   - switcheroo-control service & GPU detection
#   - gpu-run wrapper
#   - Persistence mode & systemd service
#   - SDDM login screen fix (nvidia-drm.conf + GRUB + sddm.conf.d)
#   - GRUB kernel parameter
#   - initramfs
#   - Flatpak DRI access
#   - Python CUDA (PyTorch)
#   - Session type (Wayland/X11)
#   - Live GPU renderer test
# =============================================================================
# Usage: chmod +x check.sh && ./check.sh
# =============================================================================

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Counters ─────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
WARN=0

# ── Helpers ──────────────────────────────────────────────────────────────────
pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN++)); }
info() { echo -e "  ${CYAN}→${NC} $1"; }
section() {
    echo ""
    echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│  $1${NC}"
    echo -e "${BOLD}${BLUE}└─────────────────────────────────────────┘${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}╔═════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║   NVIDIA GPU Setup — Full System Check      ║${NC}"
echo -e "${BOLD}${BLUE}║   Kali Linux · $(date '+%Y-%m-%d %H:%M:%S')         ║${NC}"
echo -e "${BOLD}${BLUE}╚═════════════════════════════════════════════╝${NC}"

# =============================================================================
section "1. NVIDIA Driver"
# =============================================================================

if command -v nvidia-smi &>/dev/null; then
    pass "nvidia-smi is installed"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | xargs)
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | xargs)
    CUDA_VER=$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader 2>/dev/null | xargs)
    TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | xargs)
    info "GPU:    $GPU_NAME"
    info "Driver: $DRIVER_VER"
    info "CUDA:   $CUDA_VER"
    info "Temp:   ${TEMP}°C"
else
    fail "nvidia-smi not found — run: sudo apt install nvidia-smi"
fi

# =============================================================================
section "2. Kernel Module"
# =============================================================================

if lsmod | grep -q "^nvidia "; then
    pass "nvidia kernel module is loaded"
else
    fail "nvidia kernel module NOT loaded — run: sudo modprobe nvidia"
fi

if lsmod | grep -q "nvidia_drm"; then
    pass "nvidia_drm module is loaded"
else
    fail "nvidia_drm module NOT loaded"
fi

if lsmod | grep -q "nvidia_uvm"; then
    pass "nvidia_uvm module is loaded (required for CUDA)"
else
    warn "nvidia_uvm module not loaded — CUDA may not work"
fi

# =============================================================================
section "3. DRM Modeset (Black Login Screen Fix)"
# =============================================================================

MODESET_VAL=$(sudo cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null)
if [ "$MODESET_VAL" = "Y" ]; then
    pass "NVIDIA DRM modeset is ENABLED (Y)"
elif [ -z "$MODESET_VAL" ]; then
    warn "Could not read modeset value — try running check.sh with sudo"
else
    fail "NVIDIA DRM modeset is NOT enabled (got: '${MODESET_VAL}') — login screen may be black"
    info "Fix: sudo tee /etc/modprobe.d/nvidia-drm.conf <<< 'options nvidia-drm modeset=1 fbdev=1'"
    info "Then: sudo update-initramfs -u && sudo reboot"
fi

if [ -f /etc/modprobe.d/nvidia-drm.conf ]; then
    pass "/etc/modprobe.d/nvidia-drm.conf exists"
    CONF_CONTENT=$(cat /etc/modprobe.d/nvidia-drm.conf)
    if echo "$CONF_CONTENT" | grep -q "modeset=1"; then
        pass "modeset=1 is set in nvidia-drm.conf"
    else
        fail "modeset=1 NOT found in nvidia-drm.conf"
    fi
    if echo "$CONF_CONTENT" | grep -q "fbdev=1"; then
        pass "fbdev=1 is set in nvidia-drm.conf"
    else
        warn "fbdev=1 not set in nvidia-drm.conf (recommended)"
    fi
else
    fail "/etc/modprobe.d/nvidia-drm.conf does not exist"
fi

# =============================================================================
section "4. GRUB Configuration"
# =============================================================================

if [ -f /etc/default/grub ]; then
    pass "/etc/default/grub exists"
    GRUB_LINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
    info "Current: $GRUB_LINE"
    if echo "$GRUB_LINE" | grep -q "nvidia-drm.modeset=1"; then
        pass "nvidia-drm.modeset=1 is in GRUB_CMDLINE_LINUX_DEFAULT"
    else
        fail "nvidia-drm.modeset=1 NOT found in GRUB — login screen may be black"
        info "Fix: add nvidia-drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub"
        info "Then run: sudo update-grub"
    fi
    if echo "$GRUB_LINE" | grep -q "acpi_backlight=native"; then
        pass "acpi_backlight=native is set (backlight control)"
    else
        warn "acpi_backlight=native not set — backlight keys may not work"
    fi
else
    fail "/etc/default/grub not found"
fi

# =============================================================================
section "5. SDDM Login Screen Config"
# =============================================================================

if [ -f /etc/sddm.conf.d/nvidia.conf ]; then
    pass "/etc/sddm.conf.d/nvidia.conf exists"
    SDDM_CONTENT=$(cat /etc/sddm.conf.d/nvidia.conf)
    if echo "$SDDM_CONTENT" | grep -q "DisplayServer=wayland"; then
        pass "SDDM DisplayServer=wayland is set"
    else
        warn "SDDM DisplayServer=wayland not set"
    fi
    if echo "$SDDM_CONTENT" | grep -q "kwin_wayland"; then
        pass "SDDM CompositorCommand is set to kwin_wayland"
    else
        warn "SDDM CompositorCommand not set"
    fi
else
    fail "/etc/sddm.conf.d/nvidia.conf does not exist — login screen may be black"
    info "Fix: sudo mkdir -p /etc/sddm.conf.d && create the config file"
fi

if systemctl is-active --quiet sddm; then
    pass "SDDM service is running"
else
    warn "SDDM service is not running"
fi

# =============================================================================
section "6. switcheroo-control"
# =============================================================================

if command -v switcherooctl &>/dev/null; then
    pass "switcherooctl is installed"
else
    fail "switcherooctl not found — run: sudo apt install switcheroo-control"
fi

if systemctl is-active --quiet switcheroo-control; then
    pass "switcheroo-control service is active"
else
    fail "switcheroo-control service is NOT running"
    info "Fix: sudo systemctl enable switcheroo-control --now"
fi

if systemctl is-enabled --quiet switcheroo-control 2>/dev/null; then
    pass "switcheroo-control is enabled on boot"
else
    warn "switcheroo-control is not enabled on boot"
    info "Fix: sudo systemctl enable switcheroo-control"
fi

GPU_LIST=$(switcherooctl list 2>/dev/null)
GPU_COUNT=$(echo "$GPU_LIST" | grep -c "Device:" 2>/dev/null || echo 0)
if [ "$GPU_COUNT" -ge 2 ]; then
    pass "Both GPUs detected by switcherooctl ($GPU_COUNT devices)"
    NVIDIA_NAME=$(echo "$GPU_LIST" | grep -A2 "Discrete:.*yes" | grep "Name:" | cut -d: -f2 | xargs)
    INTEL_NAME=$(echo "$GPU_LIST" | grep -A2 "Default:.*yes" | grep "Name:" | cut -d: -f2 | xargs)
    info "Default (Intel): $INTEL_NAME"
    info "Discrete (NVIDIA): $NVIDIA_NAME"
elif [ "$GPU_COUNT" -eq 1 ]; then
    warn "Only 1 GPU detected — switcheroo-control may need a restart or reboot"
else
    fail "No GPUs detected by switcherooctl"
fi

# =============================================================================
section "7. gpu-run Wrapper"
# =============================================================================

if [ -f /usr/local/bin/gpu-run ]; then
    pass "gpu-run exists at /usr/local/bin/gpu-run"
else
    fail "gpu-run NOT found at /usr/local/bin/gpu-run"
    info "Fix: copy gpu-run to /usr/local/bin/ and chmod +x"
fi

if [ -x /usr/local/bin/gpu-run ]; then
    pass "gpu-run is executable"
else
    fail "gpu-run is NOT executable"
    info "Fix: sudo chmod +x /usr/local/bin/gpu-run"
fi

if [ -f /usr/local/bin/gpu-run ]; then
    if grep -q "switcherooctl" /usr/local/bin/gpu-run; then
        pass "gpu-run uses switcherooctl"
    else
        warn "gpu-run does not use switcherooctl — may be outdated"
    fi
    if grep -q "flatpak" /usr/local/bin/gpu-run; then
        pass "gpu-run handles Flatpak apps"
    else
        warn "gpu-run does not handle Flatpak apps"
    fi
    if grep -q "ozone-platform=x11" /usr/local/bin/gpu-run; then
        pass "gpu-run handles Electron/Wayland apps (ozone-platform=x11)"
    else
        warn "gpu-run missing Wayland Electron fix (ozone-platform=x11)"
    fi
    if grep -q "jetbrains-toolbox" /usr/local/bin/gpu-run; then
        pass "gpu-run has JetBrains Toolbox entry"
    else
        warn "gpu-run missing JetBrains Toolbox entry"
    fi
fi

# =============================================================================
section "8. Persistence Mode"
# =============================================================================

PERSISTENCE=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | xargs)
if [ "$PERSISTENCE" = "Enabled" ]; then
    pass "NVIDIA Persistence Mode is ON"
else
    warn "NVIDIA Persistence Mode is OFF — apps may take longer to start on GPU"
    info "Fix: sudo nvidia-smi -pm 1"
fi

if [ -f /etc/systemd/system/nvidia-persistence.service ]; then
    pass "nvidia-persistence.service file exists"
else
    warn "nvidia-persistence.service not found — persistence won't survive reboot"
fi

if systemctl is-enabled --quiet nvidia-persistence.service 2>/dev/null; then
    pass "nvidia-persistence.service is enabled on boot"
else
    warn "nvidia-persistence.service is NOT enabled on boot"
    info "Fix: sudo systemctl enable nvidia-persistence.service --now"
fi

# =============================================================================
section "9. CUDA Toolkit"
# =============================================================================

if command -v nvcc &>/dev/null; then
    NVCC_VER=$(nvcc --version | grep "release" | awk '{print $6}' | tr -d ',')
    pass "CUDA compiler (nvcc) found: $NVCC_VER"
else
    warn "nvcc not found — CUDA toolkit may not be installed"
    info "Install: sudo apt install nvidia-cuda-toolkit"
fi

if [ -d /usr/local/cuda ] || [ -d /usr/lib/cuda ]; then
    pass "CUDA directory found"
else
    warn "CUDA directory not found at /usr/local/cuda or /usr/lib/cuda"
fi

# =============================================================================
section "10. Python & PyTorch CUDA"
# =============================================================================

if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    pass "Python3 found: $PY_VER"

    TORCH_AVAILABLE=$(python3 -c "import torch; print('yes')" 2>/dev/null)
    if [ "$TORCH_AVAILABLE" = "yes" ]; then
        pass "PyTorch is installed"
        TORCH_VER=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null)
        info "PyTorch version: $TORCH_VER"

        CUDA_AVAILABLE=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null)
        if [ "$CUDA_AVAILABLE" = "True" ]; then
            GPU_PY=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)
            pass "PyTorch CUDA is available: $GPU_PY"
        else
            fail "PyTorch CUDA is NOT available"
            info "Install: pip install torch --index-url https://download.pytorch.org/whl/cu124"
        fi
    else
        warn "PyTorch not installed"
        info "Install: pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124"
    fi
else
    warn "python3 not found"
fi

# =============================================================================
section "11. Session & Display"
# =============================================================================

SESSION="${XDG_SESSION_TYPE:-unknown}"
DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"
info "Desktop environment: $DESKTOP"
info "Session type:        $SESSION"

if [ "$SESSION" = "wayland" ]; then
    pass "Wayland session detected"
    warn "Electron apps need --ozone-platform=x11 flag (handled by gpu-run)"
elif [ "$SESSION" = "x11" ]; then
    pass "X11 session — full GPU offloading support"
else
    warn "Unknown session type: $SESSION"
fi

if command -v glxinfo &>/dev/null; then
    RENDERER=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
    info "Default OpenGL renderer: $RENDERER"
    if echo "$RENDERER" | grep -qi "intel\|mesa"; then
        pass "Intel is default renderer (correct for Optimus — saves battery)"
    elif echo "$RENDERER" | grep -qi "nvidia"; then
        pass "NVIDIA is default renderer"
    fi
else
    warn "glxinfo not found — install: sudo apt install mesa-utils"
fi

# =============================================================================
section "12. Flatpak GPU Access"
# =============================================================================

if command -v flatpak &>/dev/null; then
    pass "Flatpak is installed"
    FLATPAK_COUNT=$(flatpak list --app 2>/dev/null | wc -l)
    info "Flatpak apps installed: $FLATPAK_COUNT"

    DRI_OVERRIDE=$(flatpak override --user --show 2>/dev/null | grep -i "dri\|device" || echo "")
    if echo "$DRI_OVERRIDE" | grep -qi "dri\|all"; then
        pass "Flatpak user DRI override is set"
    else
        warn "Flatpak DRI override may not be set"
        info "Fix: flatpak override --user --device=dri"
    fi
else
    info "Flatpak not installed — skipping"
fi

# =============================================================================
section "13. Live GPU Renderer Test"
# =============================================================================

if command -v gpu-run &>/dev/null && command -v glxinfo &>/dev/null; then
    info "Testing gpu-run with glxinfo..."
    GPU_RENDERER=$(gpu-run glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
    if echo "$GPU_RENDERER" | grep -qi "nvidia"; then
        pass "gpu-run renderer: $GPU_RENDERER ✓"
    else
        fail "gpu-run renderer shows: $GPU_RENDERER (expected NVIDIA)"
        info "switcheroo-control may need a reboot or service restart"
    fi
else
    warn "Skipping live test — gpu-run or glxinfo not available"
fi

# =============================================================================
# ── Summary ──────────────────────────────────────────────────────────────────
# =============================================================================

TOTAL=$((PASS + FAIL + WARN))
echo ""
echo -e "${BOLD}${BLUE}╔═════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║              CHECK SUMMARY                  ║${NC}"
echo -e "${BOLD}${BLUE}╠═════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  Total checks : ${BOLD}$TOTAL${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${GREEN}Passed${NC}        : ${GREEN}${BOLD}$PASS${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${YELLOW}Warnings${NC}      : ${YELLOW}${BOLD}$WARN${NC}"
echo -e "${BOLD}${BLUE}║${NC}  ${RED}Failed${NC}        : ${RED}${BOLD}$FAIL${NC}"
echo -e "${BOLD}${BLUE}╚═════════════════════════════════════════════╝${NC}"
echo ""

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  🎉 All checks passed! Your NVIDIA GPU setup is complete.${NC}"
elif [ "$FAIL" -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}  ⚠️  Setup looks good but has $WARN warning(s). Review above.${NC}"
else
    echo -e "${RED}${BOLD}  ❌ $FAIL check(s) failed. Fix the issues above and re-run this script.${NC}"
fi
echo ""
