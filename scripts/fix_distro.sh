#!/usr/bin/env bash

# ==============================================================================
# Termux Automated Chroot Package Fixer
# Purpose: Re-run package installations and configuration on broken distros
# ==============================================================================

set -e

# --- Color Definitions ---
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
WHITE="\033[37m"
RESET="\033[0m"

log_info() { echo -e "${CYAN}${BOLD}[INFO]${RESET} ${WHITE}$1${RESET}"; }
log_success() { echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} ${WHITE}$1${RESET}"; }
log_warn() { echo -e "${YELLOW}${BOLD}[WARNING]${RESET} ${WHITE}$1${RESET}"; }
log_error() { echo -e "${RED}${BOLD}[ERROR]${RESET} ${WHITE}$1${RESET}"; }

# --- Helper functions for UI ---
print_centered() {
    local text="$1"
    local term_width=$(tput cols 2>/dev/null || echo 80)
    local clean_text=$(echo -e "$text" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    local text_length=${#clean_text}
    if [ "$text_length" -ge "$term_width" ]; then
        echo -e "$text"
    else
        local padding=$(( (term_width - text_length) / 2 ))
        printf "%${padding}s" ""
        echo -e "$text"
    fi
}

print_divider() {
    local term_width=$(tput cols 2>/dev/null || echo 80)
    local divider=$(printf "%${term_width}s" | tr ' ' '=')
    echo -e "${YELLOW}${BOLD}${divider}${RESET}"
}

if command -v chroot-distro &> /dev/null; then
    DISTRO_CMD="chroot-distro"
else
    log_error "chroot-distro is not installed. Please run setup.sh first."
    exit 1
fi

SELECTED_DISTRO="$1"

# If no distro was passed as an argument, auto-detect installed distros
if [ -z "$SELECTED_DISTRO" ]; then
    PREFIX_VAR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib"
    INSTALLED_DISTROS=()
    for d in debian fedora archlinux; do
        if [ -d "$PREFIX_VAR/chroot-distro/containers/$d" ] || [ -d "$PREFIX_VAR/chroot-distro/installed-rootfs/$d" ]; then
            INSTALLED_DISTROS+=("$d")
        fi
    done
    
    if [ ${#INSTALLED_DISTROS[@]} -eq 0 ]; then
        log_warn "Could not automatically detect installed distros."
        echo ""
        print_divider
        print_centered "${CYAN}${BOLD}Please select which environment to fix:${RESET}"
        print_centered "  ${WHITE}1)${RESET} fedora    "
        print_centered "  ${WHITE}2)${RESET} debian    "
        print_centered "  ${WHITE}3)${RESET} archlinux "
        print_centered "  ${WHITE}4)${RESET} Exit      "
        print_divider
        read -p "Select a number (1-4): " fallback_choice
        
        case "$fallback_choice" in
            1) SELECTED_DISTRO="fedora" ;;
            2) SELECTED_DISTRO="debian" ;;
            3) SELECTED_DISTRO="archlinux" ;;
            4) exit 0 ;;
            *) log_error "Invalid choice. Exiting."; exit 1 ;;
        esac
    elif [ "$AUTOCHROOT_MANUAL" != "1" ] && [ ${#INSTALLED_DISTROS[@]} -eq 1 ]; then
        SELECTED_DISTRO="${INSTALLED_DISTROS[0]}"
        echo -e "${GREEN}Auto-selected installed distribution: ${SELECTED_DISTRO^^}${RESET}"
    else
        echo -e "${CYAN}${BOLD}Multiple distributions detected. Which one do you want to repair?${RESET}"
        select opt in "${INSTALLED_DISTROS[@]}"; do
            if [ -n "$opt" ]; then
                SELECTED_DISTRO="$opt"
                break
            else
                echo "Invalid selection."
            fi
        done
    fi
fi

# Need to run GPU detection so distro_setup.sh can configure XFCE and drivers properly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
GPU_DETECT_SCRIPT="$SCRIPT_DIR/scripts/gpu_detect.sh"
DISTRO_SETUP_SCRIPT="$SCRIPT_DIR/scripts/distro_setup.sh"

if [ ! -f "$DISTRO_SETUP_SCRIPT" ]; then
    log_error "Missing distro_setup.sh! Cannot proceed."
    exit 1
fi

if [ -f "$GPU_DETECT_SCRIPT" ]; then
    log_info "Detecting hardware..."
    source "$GPU_DETECT_SCRIPT"
    detect_adreno_gpu >/dev/null 2>&1 || true
else
    IS_ADRENO=false
    ADRENO_SERIES="Generic"
fi

# Source universal settings (but force false for repair script)
if [ -f "$SCRIPT_DIR/scripts/global_settings.sh" ]; then
    source "$SCRIPT_DIR/scripts/global_settings.sh"
fi
export SETUP_MODE="false"

echo -e "\n${YELLOW}${BOLD}=== Distro Configuration Repair ===${RESET}"
echo -e "${WHITE}Executing repair utility for ${SELECTED_DISTRO^^}...${RESET}"

log_info "Injecting repair script directly into ${SELECTED_DISTRO^^} rootfs..."

# Auto-detect the saved username
SAVED_USER=""
if [ -f "$HOME/.${SELECTED_DISTRO}_user" ]; then
    SAVED_USER=$(cat "$HOME/.${SELECTED_DISTRO}_user" | tr -d '\r\n')
elif [ -f "/data/data/com.termux/files/home/.${SELECTED_DISTRO}_user" ]; then
    SAVED_USER=$(cat "/data/data/com.termux/files/home/.${SELECTED_DISTRO}_user" | tr -d '\r\n')
fi

SETUP_B64=$(base64 -w0 "$DISTRO_SETUP_SCRIPT" 2>/dev/null || base64 "$DISTRO_SETUP_SCRIPT" | tr -d '\r\n')

$DISTRO_CMD login $SELECTED_DISTRO -- bash -c "
    export SETUP_MODE='$SETUP_MODE'
    echo '$SETUP_B64' | base64 -d > /tmp/distro_setup.sh
    chmod +x /tmp/distro_setup.sh
    bash /tmp/distro_setup.sh '$SAVED_USER' '' '$IS_ADRENO' '$ADRENO_SERIES' '$SELECTED_DISTRO' ''
"

log_success "${SELECTED_DISTRO^^} packages and configurations have been successfully repaired!"
exit 0
