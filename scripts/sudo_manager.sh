#!/usr/bin/env bash

# ==============================================================================
# Sudo Manager - Enable/Disable Passwordless Sudo for Distros
# ==============================================================================

set -e

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

PREFIX_VAR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib"
INSTALLED_DISTROS=()
for d in debian fedora archlinux; do
    if [ -d "$PREFIX_VAR/chroot-distro/containers/$d" ] || [ -d "$PREFIX_VAR/chroot-distro/installed-rootfs/$d" ]; then
        INSTALLED_DISTROS+=("$d")
    fi
done

if [ ${#INSTALLED_DISTROS[@]} -eq 0 ]; then
    log_error "No distros detected! Install one with setup.sh first."
    exit 1
fi

echo ""
print_divider
print_centered "${CYAN}${BOLD}Sudo Configuration Manager${RESET}"
echo ""
print_centered "${WHITE}Select which distro to configure:${RESET}"
for i in "${!INSTALLED_DISTROS[@]}"; do
    print_centered "  ${WHITE}$((i+1)))${RESET} ${INSTALLED_DISTROS[$i]}  "
done
print_divider
echo ""

read -p "Select a distro (1-${#INSTALLED_DISTROS[@]}): " distro_choice
if [[ "$distro_choice" -lt 1 || "$distro_choice" -gt "${#INSTALLED_DISTROS[@]}" ]]; then
    log_error "Invalid selection."
    exit 1
fi
SELECTED_DISTRO="${INSTALLED_DISTROS[$((distro_choice-1))]}"

echo ""
print_divider
print_centered "${CYAN}Do you want to ENABLE or DISABLE Passwordless Sudo for ${SELECTED_DISTRO^^}?${RESET}"
echo ""
print_centered "  ${WHITE}1)${GREEN} ENABLE (No password needed for sudo)${RESET} "
print_centered "  ${WHITE}2)${RED} DISABLE (Requires password for sudo)${RESET} "
print_divider
echo ""

read -p "Select an option (1-2): " sudo_choice

if [ "$sudo_choice" == "1" ]; then
    log_info "Enabling passwordless sudo for ${SELECTED_DISTRO^^}..."
    $DISTRO_CMD login "$SELECTED_DISTRO" -- bash -c "
        mkdir -p /etc/sudoers.d
        echo '%sudo ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/99_sudo_nopasswd
        echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers.d/99_sudo_nopasswd
        chmod 440 /etc/sudoers.d/99_sudo_nopasswd
    "
    log_success "Passwordless sudo has been ENABLED for ${SELECTED_DISTRO^^}."
elif [ "$sudo_choice" == "2" ]; then
    log_info "Disabling passwordless sudo for ${SELECTED_DISTRO^^}..."
    $DISTRO_CMD login "$SELECTED_DISTRO" -- bash -c "
        grep -l 'NOPASSWD' /etc/sudoers.d/* 2>/dev/null | xargs rm -f 2>/dev/null || true
    "
    log_success "Passwordless sudo has been DISABLED for ${SELECTED_DISTRO^^}."
else
    log_error "Invalid option selected."
    exit 1
fi
exit 0
