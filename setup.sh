#!/bin/bash
# =============================================================================
# setup.sh — Full NVIDIA GPU On-Demand Automation for Kali Linux
# =============================================================================
# Does everything after driver verification:
#   1. Checks prerequisites
#   2. Installs switcheroo-control
#   3. Auto-detects all apps & Flatpaks → generates gpu-run wrapper
#   4. Enables Flatpak DRI access
#   5. Enables NVIDIA DRM modeset
#   6. Updates GRUB kernel parameters
#   7. Updates initramfs
#   8. Fixes SDDM black login screen
#   9. Final summary & reboot prompt
# =============================================================================
# Usage: sudo bash setup.sh
# =============================================================================

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
pass()    { echo -e "  ${GREEN}✓${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
info()    { echo -e "  ${CYAN}→${NC} $1"; }
section() {
    echo ""
    echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│  $1${NC}"
    echo -e "${BOLD}${BLUE}└─────────────────────────────────────────┘${NC}"
}
abort() {
    echo -e "\n  ${RED}${BOLD}[ABORTED]${NC} $1"
    exit 1
}

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
ERRORS=0
STEPS_DONE=0

# =============================================================================
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║   NVIDIA GPU Setup — Full Automation             ║${NC}"
echo -e "${BOLD}${BLUE}║   Kali Linux · $(date '+%Y-%m-%d %H:%M:%S')              ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Running as: ${BOLD}$(whoami)${NC} (real user: ${BOLD}$REAL_USER${NC})"

# =============================================================================
section "0. Prerequisites Check"
# =============================================================================

# Must run as root
if [ "$EUID" -ne 0 ]; then
    abort "Please run as root: sudo bash setup.sh"
fi
pass "Running as root"

# Check NVIDIA GPU exists
if ! lspci | grep -qi nvidia; then
    abort "No NVIDIA GPU detected. This script is for NVIDIA Optimus laptops only."
fi
GPU_NAME=$(lspci | grep -i nvidia | head -1 | sed 's/.*: //')
pass "NVIDIA GPU detected: $GPU_NAME"

# Check nvidia-smi works
if ! command -v nvidia-smi &>/dev/null; then
    abort "nvidia-smi not found. Install NVIDIA drivers first:\n  sudo apt install nvidia-driver nvidia-driver-bin -y\n  sudo reboot\n  Then re-run this script."
fi
DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | xargs)
pass "NVIDIA driver is installed (version $DRIVER)"

# Check internet
if ! ping -c1 -W2 8.8.8.8 &>/dev/null; then
    warn "No internet connection detected — package installation may fail"
else
    pass "Internet connection available"
fi

# Check apt
if ! command -v apt &>/dev/null; then
    abort "apt not found — this script requires a Debian/Kali system"
fi
pass "apt package manager available"

# =============================================================================
section "1. Installing switcheroo-control"
# =============================================================================

apt update -q 2>/dev/null
if apt install -y switcheroo-control &>/dev/null; then
    pass "switcheroo-control installed"
    ((STEPS_DONE++))
else
    fail "Failed to install switcheroo-control"
    ((ERRORS++))
fi

# Enable and start service
if systemctl enable switcheroo-control --now &>/dev/null; then
    pass "switcheroo-control service enabled and started"
else
    fail "Failed to start switcheroo-control service"
    ((ERRORS++))
fi

# Wait for service to detect GPUs
sleep 2

# Verify both GPUs detected
GPU_COUNT=$(switcherooctl list 2>/dev/null | grep -c "Device:" || echo 0)
if [ "$GPU_COUNT" -ge 2 ]; then
    pass "Both GPUs detected by switcherooctl ($GPU_COUNT devices)"
else
    warn "Only $GPU_COUNT GPU(s) detected — may need a reboot"
fi

# =============================================================================
section "2. Auto-Detecting Apps & Generating gpu-run Wrapper"
# =============================================================================

# ── Known Electron apps (need --ozone-platform=x11 on Wayland) ───────────────
ELECTRON_APPS=(
    "code|VS Code"
    "antigravity|Antigravity"
    "cursor|Cursor"
    "windsurf|Windsurf"
    "brave-browser|Brave Browser"
    "chromium|Chromium"
    "google-chrome|Google Chrome"
    "google-chrome-stable|Google Chrome Stable"
    "slack|Slack"
    "discord|Discord"
    "obsidian|Obsidian"
    "notion-app|Notion"
    "figma-linux|Figma"
    "insomnia|Insomnia"
    "postman|Postman"
    "mongodb-compass|MongoDB Compass"
    "teams|Microsoft Teams"
    "microsoft-edge|Microsoft Edge"
    "1password|1Password"
    "logseq|Logseq"
)

# ── Known system apps (work with switcherooctl directly) ─────────────────────
SYSTEM_APPS=(
    "pycharm|PyCharm"
    "pycharm-professional|PyCharm Professional"
    "idea|IntelliJ IDEA"
    "webstorm|WebStorm"
    "goland|GoLand"
    "clion|CLion"
    "rider|Rider"
    "datagrip|DataGrip"
    "phpstorm|PhpStorm"
    "rubymine|RubyMine"
    "blender|Blender"
    "inkscape|Inkscape"
    "vlc|VLC"
    "mpv|MPV"
    "firefox|Firefox"
    "firefox-esr|Firefox ESR"
    "thunderbird|Thunderbird"
    "krita|Krita"
    "darktable|Darktable"
    "rawtherapee|RawTherapee"
    "handbrake|HandBrake"
    "openshot|OpenShot"
    "shotcut|Shotcut"
    "resolve|DaVinci Resolve"
    "godot|Godot"
    "godot4|Godot 4"
    "steam|Steam"
    "lutris|Lutris"
)

# ── Known Flatpak app IDs (app.id|shortname|display_name) ────────────────────
KNOWN_FLATPAKS=(
    "org.gimp.GIMP|gimp|GIMP"
    "org.kde.kdenlive|kdenlive|Kdenlive"
    "com.heroicgameslauncher.hgl|heroic|Heroic Games Launcher"
    "dev.vencord.Vesktop|vesktop|Vesktop"
    "app.zen_browser.zen|zen|Zen Browser"
    "com.discordapp.Discord|discord-flatpak|Discord"
    "org.blender.Blender|blender-flatpak|Blender"
    "org.inkscape.Inkscape|inkscape-flatpak|Inkscape"
    "org.kde.krita|krita-flatpak|Krita"
    "org.videolan.VLC|vlc-flatpak|VLC"
    "com.valvesoftware.Steam|steam-flatpak|Steam"
    "net.lutris.Lutris|lutris-flatpak|Lutris"
    "com.usebottles.bottles|bottles-flatpak|Bottles"
    "org.mozilla.firefox|firefox-flatpak|Firefox"
    "org.mozilla.Thunderbird|thunderbird-flatpak|Thunderbird"
    "org.gnome.Snapshot|snapshot|GNOME Camera"
    "io.missioncenter.MissionCenter|missioncenter|Mission Center"
    "io.appflowy.AppFlowy|appflowy|AppFlowy"
    "com.github.joseexposito.touche|touche|Touché"
    "com.github.tenderowl.frog|frog|Frog"
    "com.vixalien.sticky|sticky|Sticky Notes"
    "io.github.radiolamp.mangojuice|mangojuice|Mango Juice"
    "org.darktable.darktable|darktable-flatpak|Darktable"
    "org.rawtherapee.RawTherapee|rawtherapee-flatpak|RawTherapee"
    "fr.handbrake.ghb|handbrake-flatpak|HandBrake"
    "org.openshot.OpenShot|openshot-flatpak|OpenShot"
    "org.shotcut.Shotcut|shotcut-flatpak|Shotcut"
    "com.blackmagicdesign.resolve|resolve-flatpak|DaVinci Resolve"
    "org.godotengine.Godot|godot-flatpak|Godot"
    "com.obsproject.Studio|obs-flatpak|OBS Studio"
    "org.audacityteam.Audacity|audacity-flatpak|Audacity"
    "com.spotify.Client|spotify-flatpak|Spotify"
    "md.obsidian.Obsidian|obsidian-flatpak|Obsidian"
    "com.slack.Slack|slack-flatpak|Slack"
    "com.microsoft.Teams|teams-flatpak|Microsoft Teams"
    "com.visualstudio.code|code-flatpak|VS Code (Flatpak)"
)

# ── Scan system binaries ──────────────────────────────────────────────────────
FOUND_ELECTRON=()
FOUND_SYSTEM=()

info "Scanning Electron apps..."
for entry in "${ELECTRON_APPS[@]}"; do
    BIN="${entry%%|*}"; NAME="${entry##*|}"
    if command -v "$BIN" &>/dev/null; then
        pass "Found: $NAME ($BIN)"
        FOUND_ELECTRON+=("$BIN|$NAME")
    fi
done

info "Scanning system apps..."
for entry in "${SYSTEM_APPS[@]}"; do
    BIN="${entry%%|*}"; NAME="${entry##*|}"
    if command -v "$BIN" &>/dev/null; then
        pass "Found: $NAME ($BIN)"
        FOUND_SYSTEM+=("$BIN|$NAME")
    fi
done

# ── Scan JetBrains Toolbox ────────────────────────────────────────────────────
JETBRAINS_BIN=$(find "$REAL_HOME/.local/share/JetBrains" -name "jetbrains-toolbox" -type f 2>/dev/null | head -1)
if [ -n "$JETBRAINS_BIN" ]; then
    pass "Found: JetBrains Toolbox ($JETBRAINS_BIN)"
    HAS_JETBRAINS=true
else
    HAS_JETBRAINS=false
fi

# ── Scan Flatpak apps ─────────────────────────────────────────────────────────
FOUND_FLATPAKS=()

if command -v flatpak &>/dev/null; then
    info "Scanning Flatpak apps..."
    INSTALLED_FLATPAKS=$(su - "$REAL_USER" -c "flatpak list --app --columns=application" 2>/dev/null)

    if [ -n "$INSTALLED_FLATPAKS" ]; then
        # Match known Flatpaks
        for entry in "${KNOWN_FLATPAKS[@]}"; do
            APP_ID="${entry%%|*}"; REST="${entry#*|}"; SHORT="${REST%%|*}"; DISPLAY="${REST##*|}"
            if echo "$INSTALLED_FLATPAKS" | grep -q "^${APP_ID}$"; then
                pass "Found Flatpak: $DISPLAY ($APP_ID)"
                FOUND_FLATPAKS+=("$APP_ID|$SHORT|$DISPLAY")
            fi
        done
        # Auto-detect unknown Flatpaks
        while read -r appid; do
            KNOWN=false
            for entry in "${KNOWN_FLATPAKS[@]}"; do
                [ "${entry%%|*}" = "$appid" ] && KNOWN=true && break
            done
            if [ "$KNOWN" = false ]; then
                SHORT=$(echo "$appid" | awk -F. '{print tolower($NF)}')
                pass "Auto-detected Flatpak: $appid → gpu-run $SHORT"
                FOUND_FLATPAKS+=("$appid|$SHORT|$appid")
            fi
        done <<< "$INSTALLED_FLATPAKS"
    fi
fi

# ── Generate gpu-run ──────────────────────────────────────────────────────────
GPURUN_FILE="/usr/local/bin/gpu-run"

cat > "$GPURUN_FILE" << 'HEADER'
#!/bin/bash
# =============================================================================
# gpu-run — Launch any app on NVIDIA GPU (auto-generated by setup.sh)
# Usage: gpu-run <appname> [args...]
# Regenerate: sudo bash setup.sh
# =============================================================================

APP="$1"
shift

case "$APP" in
HEADER

# Electron block
if [ ${#FOUND_ELECTRON[@]} -gt 0 ]; then
    echo "    # Electron apps — need --ozone-platform=x11 on Wayland" >> "$GPURUN_FILE"
    PATTERN=""
    for entry in "${FOUND_ELECTRON[@]}"; do
        BIN="${entry%%|*}"; NAME="${entry##*|}"
        [ -n "$PATTERN" ] && PATTERN="$PATTERN|"
        PATTERN="${PATTERN}${BIN}"
        echo "    # $NAME" >> "$GPURUN_FILE"
    done
    printf '    %s)\n        exec switcherooctl launch --gpu 1 "$APP" --enable-features=UseOzonePlatform --ozone-platform=x11 "$@"\n        ;;\n' "$PATTERN" >> "$GPURUN_FILE"
fi

# JetBrains block
if [ "$HAS_JETBRAINS" = true ]; then
    cat >> "$GPURUN_FILE" << JBLOCK
    # JetBrains Toolbox
    jetbrains-toolbox)
        TOOLBOX_BIN=\$(find "$REAL_HOME/.local/share/JetBrains" -name "jetbrains-toolbox" -type f 2>/dev/null | head -1)
        if [ -z "\$TOOLBOX_BIN" ]; then echo "Error: jetbrains-toolbox not found"; exit 1; fi
        exec switcherooctl launch --gpu 1 "\$TOOLBOX_BIN" "\$@"
        ;;
JBLOCK
fi

# Flatpak block
if [ ${#FOUND_FLATPAKS[@]} -gt 0 ]; then
    echo "    # Flatpak apps — use env vars (switcherooctl can't enter sandbox)" >> "$GPURUN_FILE"
    for entry in "${FOUND_FLATPAKS[@]}"; do
        APP_ID="${entry%%|*}"; REST="${entry#*|}"; SHORT="${REST%%|*}"; DISPLAY="${REST##*|}"
        printf '    # %s\n    %s)\n        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia --env=__VK_LAYER_NV_optimus=NVIDIA_only --env=VK_LOADER_DRIVERS_SELECT='"'"'*nvidia*'"'"' %s "$@"\n        ;;\n' "$DISPLAY" "$SHORT" "$APP_ID" >> "$GPURUN_FILE"
    done
    cat >> "$GPURUN_FILE" << 'FGENERIC'
    # Generic: gpu-run flatpak <APP_ID>
    flatpak)
        exec flatpak run --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia --env=__VK_LAYER_NV_optimus=NVIDIA_only --env=VK_LOADER_DRIVERS_SELECT='*nvidia*' "$@"
        ;;
FGENERIC
fi

# System apps block
if [ ${#FOUND_SYSTEM[@]} -gt 0 ]; then
    echo "    # System apps" >> "$GPURUN_FILE"
    for entry in "${FOUND_SYSTEM[@]}"; do
        BIN="${entry%%|*}"; NAME="${entry##*|}"
        printf '    # %s\n    %s)\n        exec switcherooctl launch --gpu 1 "$APP" "$@"\n        ;;\n' "$NAME" "$BIN" >> "$GPURUN_FILE"
    done
fi

# Fallback
cat >> "$GPURUN_FILE" << 'FOOTER'
    # Fallback
    *)
        exec switcherooctl launch --gpu 1 "$APP" "$@"
        ;;
esac
FOOTER

chmod +x "$GPURUN_FILE"

if [ -x "$GPURUN_FILE" ]; then
    pass "gpu-run generated with ${#FOUND_ELECTRON[@]} Electron + ${#FOUND_SYSTEM[@]} system + ${#FOUND_FLATPAKS[@]} Flatpak apps"
    ((STEPS_DONE++))
else
    fail "Failed to generate gpu-run"
    ((ERRORS++))
fi

# =============================================================================
section "3. Flatpak DRI Access"
# =============================================================================

if command -v flatpak &>/dev/null; then
    if su - "$REAL_USER" -c "flatpak override --user --device=dri" &>/dev/null; then
        pass "Flatpak DRI override set for user $REAL_USER"
        ((STEPS_DONE++))
    else
        warn "Could not set Flatpak DRI override automatically"
        info "Run manually: flatpak override --user --device=dri"
    fi
else
    info "Flatpak not installed — skipping DRI override"
fi

# =============================================================================
section "4. NVIDIA DRM Modeset"
# =============================================================================

# Create modprobe config
cat > /etc/modprobe.d/nvidia-drm.conf << 'EOF'
options nvidia-drm modeset=1 fbdev=1
EOF

if [ -f /etc/modprobe.d/nvidia-drm.conf ]; then
    pass "/etc/modprobe.d/nvidia-drm.conf created"
    ((STEPS_DONE++))
else
    fail "Failed to create nvidia-drm.conf"
    ((ERRORS++))
fi

# =============================================================================
section "5. GRUB Configuration"
# =============================================================================

GRUB_FILE="/etc/default/grub"

if [ ! -f "$GRUB_FILE" ]; then
    fail "/etc/default/grub not found"
    ((ERRORS++))
else
    # Backup original grub
    cp "$GRUB_FILE" "${GRUB_FILE}.bak"
    pass "GRUB backup saved to ${GRUB_FILE}.bak"

    CURRENT_LINE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_FILE")
    info "Current: $CURRENT_LINE"

    if echo "$CURRENT_LINE" | grep -q "nvidia-drm.modeset=1"; then
        pass "nvidia-drm.modeset=1 already in GRUB — skipping"
    else
        # Extract current value and append
        CURRENT_PARAMS=$(echo "$CURRENT_LINE" | sed 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/\1/')
        NEW_PARAMS="$CURRENT_PARAMS nvidia-drm.modeset=1"
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" "$GRUB_FILE"
        pass "nvidia-drm.modeset=1 added to GRUB"
    fi

    # Update GRUB
    if update-grub &>/dev/null; then
        pass "GRUB updated successfully"
        ((STEPS_DONE++))
    else
        fail "update-grub failed"
        ((ERRORS++))
    fi
fi

# =============================================================================
section "6. Updating initramfs"
# =============================================================================

info "Running update-initramfs (this may take a moment)..."
if update-initramfs -u &>/dev/null; then
    pass "initramfs updated successfully"
    ((STEPS_DONE++))
else
    fail "update-initramfs failed"
    ((ERRORS++))
fi

# =============================================================================
section "7. SDDM Black Login Screen Fix"
# =============================================================================

mkdir -p /etc/sddm.conf.d

cat > /etc/sddm.conf.d/nvidia.conf << 'EOF'
[General]
DisplayServer=wayland

[Wayland]
EnableHiDPI=true
CompositorCommand=kwin_wayland --drm --no-lockscreen
EOF

if [ -f /etc/sddm.conf.d/nvidia.conf ]; then
    pass "/etc/sddm.conf.d/nvidia.conf created"
    ((STEPS_DONE++))
else
    fail "Failed to create SDDM nvidia config"
    ((ERRORS++))
fi

# =============================================================================
section "8. mesa-utils (for verification)"
# =============================================================================

if ! command -v glxinfo &>/dev/null; then
    info "Installing mesa-utils for glxinfo..."
    if apt install -y mesa-utils &>/dev/null; then
        pass "mesa-utils installed"
    else
        warn "Could not install mesa-utils — glxinfo unavailable"
    fi
else
    pass "mesa-utils already installed"
fi

# =============================================================================
# ── Final Summary ─────────────────────────────────────────────────────────────
# =============================================================================
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║              SETUP SUMMARY                       ║${NC}"
echo -e "${BOLD}${BLUE}╠══════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${BLUE}║${NC}  Steps completed : ${GREEN}${BOLD}$STEPS_DONE${NC}"
echo -e "${BOLD}${BLUE}║${NC}  Errors          : ${RED}${BOLD}$ERRORS${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✓ All steps completed successfully!${NC}"
else
    echo -e "${RED}${BOLD}  ✗ $ERRORS error(s) occurred. Review output above.${NC}"
fi

echo ""
echo -e "${BOLD}  What was configured:${NC}"
echo -e "  ${GREEN}✓${NC} switcheroo-control installed & enabled"
echo -e "  ${GREEN}✓${NC} gpu-run auto-generated for all detected apps"
echo -e "  ${GREEN}✓${NC} Flatpak DRI access granted"
echo -e "  ${GREEN}✓${NC} NVIDIA DRM modeset enabled (nvidia-drm.conf)"
echo -e "  ${GREEN}✓${NC} GRUB updated with nvidia-drm.modeset=1"
echo -e "  ${GREEN}✓${NC} initramfs updated"
echo -e "  ${GREEN}✓${NC} SDDM login screen fix applied"
echo ""
echo -e "${BOLD}  After reboot, use:${NC}"
echo -e "  ${CYAN}gpu-run code${NC}               # VS Code on NVIDIA"
echo -e "  ${CYAN}gpu-run pycharm${NC}            # PyCharm on NVIDIA"
echo -e "  ${CYAN}gpu-run jetbrains-toolbox${NC}  # JetBrains on NVIDIA"
echo -e "  ${CYAN}gpu-run kdenlive${NC}           # Kdenlive on NVIDIA"
echo -e "  ${CYAN}gpu-run heroic${NC}             # Heroic Games on NVIDIA"
echo -e "  ${CYAN}watch -n 1 nvidia-smi${NC}      # Monitor GPU usage"
echo ""

# Reboot prompt
echo -e "${YELLOW}${BOLD}  A reboot is required to apply all changes.${NC}"
echo -ne "  Reboot now? [y/N] "
read -r REBOOT_ANSWER
REBOOT_ANSWER=$(echo "$REBOOT_ANSWER" | tr '[:upper:]' '[:lower:]')
if [ "$REBOOT_ANSWER" = "y" ] || [ "$REBOOT_ANSWER" = "yes" ]; then
    echo ""
    echo -e "  ${GREEN}Rebooting...${NC}"
    sleep 2
    reboot
else
    echo ""
    echo -e "  ${CYAN}Reboot manually when ready:${NC} sudo reboot"
    echo ""
fi
