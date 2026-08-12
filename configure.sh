#!/usr/bin/env bash

# ==============================================================================
# Automated Chroot Configuration Wrapper
# Purpose: Interactive menu to launch fix_gpu.sh or fix_distro.sh
# ==============================================================================

set -e

BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
WHITE="\033[37m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/scripts"
echo 'SETUP_MODE="false"' > "$SCRIPT_DIR/scripts/global_settings.sh"

# --- Helper function to center text ---
print_centered() {
    local text="$1"
    local term_width=$(tput cols 2>/dev/null || echo 80)
    
    # Remove ANSI escape codes to get the true length of the visible string
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

clear

print_divider
echo ""
print_centered "${WHITE}${BOLD}Termux Chroot Configuration Menu${RESET}"
echo ""
print_divider
echo ""
print_centered "${CYAN}What would you like to configure or repair?${RESET}"
echo ""
print_centered "  ${WHITE}1) ${GREEN}Fix / Update GPU Drivers${RESET}                    "
print_centered "     (Recompiles or updates graphics drivers & Mesa) "
echo ""
print_centered "  ${WHITE}2) ${GREEN}Repair Distro Packages & Settings${RESET}           "
print_centered "     (Reinstalls core packages, XFCE, user configs)  "
echo ""
print_centered "  ${WHITE}3) ${GREEN}Manage Passwordless Sudo${RESET}                  "
print_centered "     (Enable or disable sudo without password)       "
echo ""
print_centered "  ${WHITE}4) ${RED}Manage storage/Uninstall${RESET}                  "
print_centered "     (Delete distros or remove the installer script) "
echo ""
print_centered "  ${WHITE}5) ${CYAN}Exit${RESET}                                        "
echo ""
print_divider

while true; do
    read -p "Select an option (1-5): " choice
    case "$choice" in
        1)
            echo -e "${GREEN}Launching GPU Driver Configuration...${RESET}"
            exec "$SCRIPT_DIR/scripts/fix_gpu.sh"
            ;;
        2)
            echo -e "${GREEN}Launching Distro Repair Utility...${RESET}"
            exec "$SCRIPT_DIR/scripts/fix_distro.sh"
            ;;
        3)
            echo -e "${GREEN}Launching Sudo Configuration Manager...${RESET}"
            exec "$SCRIPT_DIR/scripts/sudo_manager.sh"
            ;;
        4)
            echo -e "${RED}Launching Uninstall Utility...${RESET}"
            exec "$SCRIPT_DIR/scripts/uninstall.sh"
            ;;
        5)
            echo -e "${CYAN}Exiting.${RESET}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please enter 1, 2, 3, 4, or 5.${RESET}"
            ;;
    esac
done
