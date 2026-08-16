#!/usr/bin/env bash
# ==============================================================================
# Master Launcher Script
# NOTE: Run this script directly WITHOUT sudo!
# ==============================================================================

BOLD="\033[1m"
CYAN="\033[38;5;51m"
YELLOW="\033[38;5;226m"
RESET="\033[0m"

PREFIX_VAR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib"
export PATH="$PATH:$HOME/.local/bin:/data/data/com.termux/files/usr/bin"
DISTRO_CMD="chroot-distro"
INSTALLED_DISTROS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
source "$SCRIPT_DIR/scripts/autochroot_state.sh" 2>/dev/null || true

# Fast directory check instead of calling slow 'chroot-distro list'.
while IFS= read -r d; do INSTALLED_DISTROS+=("$d"); done < <(autochroot_list_distros)


if [ ${#INSTALLED_DISTROS[@]} -eq 0 ]; then
    echo -e "${YELLOW}Warning: Could not automatically detect installed distros.${RESET}"
    echo -e "${CYAN}${BOLD}Please select which environment to launch, or run the installer:${RESET}"
    echo "  1. debian"
    echo "  2. fedora"
    echo "  3. archlinux"
    echo "  4. I haven't run setup.sh yet (Run installer now)"
    read -p "Select a number (1-4): " fallback_choice
    
    case "$fallback_choice" in
        1) SELECTED_DISTRO="debian" ;;
        2) SELECTED_DISTRO="fedora" ;;
        3) SELECTED_DISTRO="archlinux" ;;
        4) 
            echo -e "${GREEN}Starting installer...${RESET}"
            chmod +x ./setup.sh 2>/dev/null || true
            exec ./setup.sh
            ;;
        *) 
            echo -e "${RED}Invalid choice. Exiting.${RESET}"
            exit 1 
            ;;
    esac
else
    if [ "$AUTOCHROOT_MANUAL" != "1" ] && [ ${#INSTALLED_DISTROS[@]} -eq 1 ]; then
        SELECTED_DISTRO="${INSTALLED_DISTROS[0]}"
    else
        echo -e "${CYAN}${BOLD}Multiple OS environments detected. Please select which one to launch:${RESET}"
        for i in "${!INSTALLED_DISTROS[@]}"; do
            echo -e "  $((i+1)). ${INSTALLED_DISTROS[$i]}"
        done
        read -p "Select a number (1-${#INSTALLED_DISTROS[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#INSTALLED_DISTROS[@]}" ]; then
            SELECTED_DISTRO="${INSTALLED_DISTROS[$((choice-1))]}"
        else
            SELECTED_DISTRO="${INSTALLED_DISTROS[0]}"
            echo "Invalid choice. Defaulting to $SELECTED_DISTRO."
        fi
    fi
fi

# Locate and execute the sub-script
if [ -z "$SCRIPT_DIR" ]; then SCRIPT_DIR="$PWD"; fi

if [ -f "$SCRIPT_DIR/scripts/start_${SELECTED_DISTRO}.sh" ]; then
    exec bash "$SCRIPT_DIR/scripts/start_${SELECTED_DISTRO}.sh" "$@"
elif [ -f "${PREFIX:-/data/data/com.termux/files/usr}/Chroot-Automated-Installer/scripts/start_${SELECTED_DISTRO}.sh" ]; then
    exec bash "${PREFIX:-/data/data/com.termux/files/usr}/Chroot-Automated-Installer/scripts/start_${SELECTED_DISTRO}.sh" "$@"
else
    autochroot_load_distro "$SELECTED_DISTRO"
    case "$DISTRO_FAMILY" in fedora|rhel) START_FAMILY="fedora" ;; arch) START_FAMILY="archlinux" ;; *) START_FAMILY="debian" ;; esac
    export AUTOCHROOT_SELECTED_DISTRO="$SELECTED_DISTRO"
    export AUTOCHROOT_SELECTED_USER="$CHROOT_USER"
    exec bash "$SCRIPT_DIR/scripts/start_${START_FAMILY}.sh" "$@"
fi
