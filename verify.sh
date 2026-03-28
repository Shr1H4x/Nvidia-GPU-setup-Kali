#!/bin/bash
# =============================================================================
# verify.sh — Check NVIDIA GPU setup health on Kali Linux
# =============================================================================
# Run: chmod +x verify.sh && ./verify.sh
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
section() { echo -e "\n${BLUE}── $1 ──${NC}"; }

echo ""
echo "=============================================="
echo "   NVIDIA GPU Setup Verification"
echo "=============================================="

# ------------------------------------------------------------------------------
section "Driver"
# ------------------------------------------------------------------------------
if command -v nvidia-smi &>/dev/null; then
    pass "nvidia-smi found"
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
    CUDA=$(nvidia-smi --query-gpu=cuda_version --format=csv,noheader 2>/dev/null)
    GPU=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)
    pass "GPU: $GPU"
    pass "Driver: $DRIVER"
    pass "CUDA: $CUDA"
else
    fail "nvidia-smi not found — driver may not be installed"
fi

# ------------------------------------------------------------------------------
section "Kernel Module"
# ------------------------------------------------------------------------------
if lsmod | grep -q "^nvidia "; then
    pass "nvidia kernel module loaded"
else
    fail "nvidia kernel module NOT loaded — try: sudo modprobe nvidia"
fi

# ------------------------------------------------------------------------------
section "switcheroo-control"
# ------------------------------------------------------------------------------
if command -v switcherooctl &>/dev/null; then
    pass "switcherooctl found"
    if systemctl is-active --quiet switcheroo-control; then
        pass "switcheroo-control service is running"
    else
        fail "switcheroo-control service is NOT running — run: sudo systemctl enable switcheroo-control --now"
    fi
    GPU_COUNT=$(switcherooctl list 2>/dev/null | grep -c "Device:")
    if [ "$GPU_COUNT" -ge 2 ]; then
        pass "Both GPUs detected ($GPU_COUNT devices)"
    else
        fail "Only $GPU_COUNT GPU detected — expected 2 (Intel + NVIDIA)"
    fi
else
    fail "switcherooctl not found — run: sudo apt install switcheroo-control"
fi

# ------------------------------------------------------------------------------
section "gpu-run wrapper"
# ------------------------------------------------------------------------------
if [ -f /usr/local/bin/gpu-run ]; then
    pass "gpu-run found at /usr/local/bin/gpu-run"
    if [ -x /usr/local/bin/gpu-run ]; then
        pass "gpu-run is executable"
    else
        fail "gpu-run is NOT executable — run: sudo chmod +x /usr/local/bin/gpu-run"
    fi
else
    fail "gpu-run NOT found — copy gpu-run to /usr/local/bin/ and chmod +x"
fi

# ------------------------------------------------------------------------------
section "Persistence Mode"
# ------------------------------------------------------------------------------
PERSISTENCE=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr -d ' ')
if [ "$PERSISTENCE" = "Enabled" ]; then
    pass "Persistence mode: Enabled"
elif systemctl is-enabled --quiet nvidia-persistence.service 2>/dev/null; then
    pass "Persistence service is enabled (will activate on next boot)"
else
    warn "Persistence mode is OFF — enable with: sudo nvidia-smi -pm 1"
fi

# ------------------------------------------------------------------------------
section "Session Type"
# ------------------------------------------------------------------------------
SESSION="${XDG_SESSION_TYPE:-unknown}"
echo "  Session type: $SESSION"
if [ "$SESSION" = "wayland" ]; then
    warn "Wayland session detected — Electron apps need --ozone-platform=x11 flag (handled by gpu-run)"
elif [ "$SESSION" = "x11" ]; then
    pass "X11 session — full GPU offloading support"
else
    warn "Unknown session type: $SESSION"
fi

# ------------------------------------------------------------------------------
section "Current OpenGL Renderer"
# ------------------------------------------------------------------------------
if command -v glxinfo &>/dev/null; then
    RENDERER=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs)
    echo "  Default renderer: $RENDERER"
    if echo "$RENDERER" | grep -qi "intel\|mesa"; then
        pass "Intel is default renderer (correct for Optimus laptops)"
    elif echo "$RENDERER" | grep -qi "nvidia"; then
        pass "NVIDIA is default renderer"
    fi
else
    warn "glxinfo not found — install with: sudo apt install mesa-utils"
fi

# ------------------------------------------------------------------------------
section "CUDA (Python)"
# ------------------------------------------------------------------------------
if command -v python3 &>/dev/null; then
    CUDA_PY=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>/dev/null)
    if [ "$CUDA_PY" = "True" ]; then
        GPU_PY=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)
        pass "PyTorch CUDA available: $GPU_PY"
    else
        warn "PyTorch not installed or CUDA not available in Python"
        warn "Install: pip install torch --index-url https://download.pytorch.org/whl/cu124"
    fi
else
    warn "python3 not found"
fi

# ------------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "Verification complete."
echo ""
echo "Quick test:"
echo "  gpu-run glxinfo | grep 'OpenGL renderer'"
echo "  # Should show: NVIDIA GeForce RTX ..."
echo "=============================================="
echo ""
