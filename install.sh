#!/bin/bash
# =============================================================================
# install.sh — Automated setup for NVIDIA GPU on-demand on Kali Linux
# =============================================================================
# Run: chmod +x install.sh && sudo ./install.sh
# =============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Must run as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo ./install.sh"
fi

echo ""
echo "=============================================="
echo "   NVIDIA GPU On-Demand Setup — Kali Linux"
echo "=============================================="
echo ""

# ------------------------------------------------------------------------------
# Step 1 — Check NVIDIA GPU exists
# ------------------------------------------------------------------------------
info "Checking for NVIDIA GPU..."
if ! lspci | grep -i nvidia > /dev/null; then
    error "No NVIDIA GPU detected. Exiting."
fi
lspci | grep -i nvidia
echo ""

# ------------------------------------------------------------------------------
# Step 2 — Install dependencies
# ------------------------------------------------------------------------------
info "Updating package list..."
apt update -q

info "Installing switcheroo-control..."
apt install -y switcheroo-control

info "Installing nvidia-settings (if not present)..."
apt install -y nvidia-settings 2>/dev/null || warning "nvidia-settings not available, skipping."

# ------------------------------------------------------------------------------
# Step 3 — Enable switcheroo-control service
# ------------------------------------------------------------------------------
info "Enabling switcheroo-control service..."
systemctl enable switcheroo-control --now

sleep 2

info "Verifying switcheroo-control..."
if ! systemctl is-active --quiet switcheroo-control; then
    error "switcheroo-control failed to start. Check: systemctl status switcheroo-control"
fi

# ------------------------------------------------------------------------------
# Step 4 — Verify both GPUs are detected
# ------------------------------------------------------------------------------
info "Checking GPU list..."
GPU_LIST=$(switcherooctl list 2>/dev/null)
if [ -z "$GPU_LIST" ]; then
    error "switcherooctl list returned empty. Service may need a reboot."
fi
echo "$GPU_LIST"
echo ""

# ------------------------------------------------------------------------------
# Step 5 — Install gpu-run wrapper
# ------------------------------------------------------------------------------
info "Installing gpu-run wrapper to /usr/local/bin/gpu-run..."
cp "$(dirname "$0")/gpu-run" /usr/local/bin/gpu-run
chmod +x /usr/local/bin/gpu-run
echo "gpu-run installed successfully."

# ------------------------------------------------------------------------------
# Step 6 — Enable NVIDIA Persistence Mode
# ------------------------------------------------------------------------------
info "Enabling NVIDIA Persistence Mode..."
nvidia-smi -pm 1

info "Installing persistence systemd service..."
cp "$(dirname "$0")/nvidia-persistence.service" /etc/systemd/system/nvidia-persistence.service
systemctl daemon-reload
systemctl enable nvidia-persistence.service --now
echo "Persistence mode enabled permanently."

# ------------------------------------------------------------------------------
# Step 7 — Grant Flatpak DRI access for GPU offloading
# ------------------------------------------------------------------------------
info "Granting Flatpak apps DRI (GPU) access..."
REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
su - "$REAL_USER" -c "flatpak override --user --device=dri" 2>/dev/null || \
    warning "Could not set Flatpak DRI override. Run manually: flatpak override --user --device=dri"

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------
echo ""
echo "=============================================="
echo -e "${GREEN}   Setup Complete!${NC}"
echo "=============================================="
echo ""
echo "Usage:"
echo "  gpu-run code                 # VS Code"
echo "  gpu-run pycharm              # PyCharm"
echo "  gpu-run jetbrains-toolbox    # JetBrains Toolbox"
echo "  gpu-run kdenlive             # Kdenlive"
echo "  gpu-run heroic               # Heroic Games Launcher"
echo "  gpu-run gimp                 # GIMP"
echo "  gpu-run appname              # Any other app"
echo ""
echo "Verify:"
echo "  watch -n 1 nvidia-smi        # Live GPU monitor"
echo "  switcherooctl list           # List GPUs"
echo ""
