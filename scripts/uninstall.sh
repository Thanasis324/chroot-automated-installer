#!/usr/bin/env bash
# ==============================================================================
# Uninstall Utility for Termux Chroot Environments
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
    DISTRO_CMD=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/autochroot_state.sh" 2>/dev/null || true

INSTALLED_DISTROS=()
if [ -n "$DISTRO_CMD" ]; then
    while IFS= read -r d; do [ -n "$d" ] && INSTALLED_DISTROS+=("$d"); done < <(autochroot_list_distros)
fi

remove_distro() {
    local target="$1"
    if [ -n "$DISTRO_CMD" ]; then
        log_info "Removing distribution: $target..."
        $DISTRO_CMD remove "$target" 2>/dev/null || true
        rm -f "$HOME/.${target}_user" 2>/dev/null || true
        autochroot_remove_distro_state "$target" 2>/dev/null || true
        log_success "Successfully removed $target."
    else
        log_warn "chroot-distro not found. Cannot remove $target."
    fi
}

remove_installer_repo() {
    log_info "Deleting all installer scripts and repository files..."
    
    # Remove loose configuration files
    rm -f "$HOME/.chroot_distro" 2>/dev/null || true
    
    # Identify the repository root (assumed to be one directory up from scripts/)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_DIR="$(dirname "$SCRIPT_DIR")"
    
    # Ensure we don't accidentally delete HOME or root
    if [[ "$REPO_DIR" == "/" || "$REPO_DIR" == "$HOME" || "$REPO_DIR" == "/data/data/com.termux/files/home" ]]; then
        log_error "Safety Check Failed: Repository directory is detected as $REPO_DIR. Refusing to delete to prevent system breakage."
        exit 1
    fi
    
    log_warn "About to completely delete repository folder: $REPO_DIR"
    read -rp "Are you absolutely sure? [y/N]: " confirm
    if [[ "${confirm,,}" == "y"* ]]; then
        rm -rf "$REPO_DIR"
        log_success "Repository deleted."
        echo -e "${YELLOW}Warning: This script's directory was just deleted. Exiting now.${RESET}"
        exit 0
    else
        log_info "Aborted repository deletion."
    fi
}

while true; do
    echo ""
    print_divider
    print_centered "${RED}${BOLD}Chroot Uninstallation & Cleanup Utility${RESET}"
    echo ""
    print_centered "${CYAN}What would you like to delete?${RESET}"
    echo ""
    print_centered "  ${WHITE}1)${RESET} Delete ALL installed Linux distributions       "
    print_centered "  ${WHITE}2)${RESET} Delete a specific Linux distribution         "
    print_centered "  ${WHITE}3)${RESET} Delete this entire automated installer folder"
    print_centered "  ${WHITE}4)${RESET} Exit                                         "
    print_divider
    echo ""
    read -p "Select an option (1-4): " main_choice

    case "$main_choice" in
        1)
            echo -e "${RED}Warning: This will delete ALL data inside your Linux containers!${RESET}"
            read -rp "Are you sure? [y/N]: " confirm
            if [[ "${confirm,,}" == "y"* ]]; then
                for d in "${INSTALLED_DISTROS[@]}"; do
                    remove_distro "$d"
                done
                INSTALLED_DISTROS=()
            fi
            ;;
        2)
            if [ ${#INSTALLED_DISTROS[@]} -eq 0 ]; then
                log_warn "No installed distros detected."
            else
                echo -e "${CYAN}Select which distribution to delete:${RESET}"
                for i in "${!INSTALLED_DISTROS[@]}"; do
                    echo "  $((i+1))) ${INSTALLED_DISTROS[$i]}"
                done
                read -p "Select a distro to delete: " d_choice
                if [[ "$d_choice" -ge 1 && "$d_choice" -le "${#INSTALLED_DISTROS[@]}" ]]; then
                    target="${INSTALLED_DISTROS[$((d_choice-1))]}"
                    read -rp "Delete $target? [y/N]: " confirm
                    if [[ "${confirm,,}" == "y"* ]]; then
                        remove_distro "$target"
                        # Refresh installed distros array
                        INSTALLED_DISTROS=()
                        while IFS= read -r d; do [ -n "$d" ] && INSTALLED_DISTROS+=("$d"); done < <(autochroot_list_distros)
                    fi
                else
                    log_warn "Invalid selection."
                fi
            fi
            ;;
        3)
            remove_installer_repo
            ;;
        4)
            echo -e "${CYAN}Exiting.${RESET}"
            exit 0
            ;;
        *)
            log_warn "Invalid choice."
            ;;
    esac
done
