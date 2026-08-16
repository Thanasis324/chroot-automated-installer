#!/usr/bin/env bash
# ==============================================================================
# Termux Automated Debian Chroot Setup Script
# Features:
#   1. Pre-installation of all dependencies & internet connectivity check
#   2. Root verification & auto-elevation via installed sudo/tsu (BEFORE credentials)
#   3. Single interactive user credentials registration (username & password)
#   4. Automated Python & PyPI chroot-distro setup
#   5. Native Debian Chroot Installation via chroot-distro
#   6. PulseAudio & Termux:X11 Integration
#   7. Automatic GPU Architecture Detection & Adreno Turnip (A6XX/A7XX/A8XX) Drivers
#   8. Touch-Optimized XFCE4 Desktop Environment (No Systemd required)
#   9. Visually appealing UI with ASCII Art banners & ANSI styling
#  10. Automatic GPU driver verification & helper utility scripts
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "." ] || [ ! -d "$SCRIPT_DIR/scripts" ]; then
    if [ -d "${PREFIX:-/data/data/com.termux/files/usr}/Chroot-Automated-Installer/scripts" ]; then
        SCRIPT_DIR="${PREFIX:-/data/data/com.termux/files/usr}/Chroot-Automated-Installer"
    elif [ -d "$HOME/chroot-automated-installer/scripts" ]; then
        SCRIPT_DIR="$HOME/chroot-automated-installer"
    else
        SCRIPT_DIR="$PWD"
    fi
fi
mkdir -p "$SCRIPT_DIR/scripts"
source "$SCRIPT_DIR/scripts/autochroot_state.sh" 2>/dev/null || true
export SETUP_MODE="true"
echo 'SETUP_MODE="true"' > "$SCRIPT_DIR/scripts/global_settings.sh"

# --- Color Definitions ---
BOLD="\033[1m"
RESET="\033[0m"
RED="\033[38;5;196m"
GREEN="\033[38;5;46m"
YELLOW="\033[38;5;226m"
BLUE="\033[38;5;39m"
PURPLE="\033[38;5;129m"
CYAN="\033[38;5;51m"
WHITE="\033[38;5;231m"

DISTRO_CMD="chroot-distro"

# --- Helper Functions ---
print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "================================================================================"
    echo "       _   _   _ _____ ___   ____ _   _ ____   ___   ___ _____                  "
    echo "      / \\ | | | |_   _/ _ \\ / ___| | | |  _ \\ / _ \\ / _ \\_   _|                 "
    echo "     / _ \\| | | | | || | | | |   | |_| | |_) | | | | | | || |                   "
    echo "    / ___ \\ |_| | | || |_| | |___|  _  |  _ <| |_| | |_| || |                   "
    echo "   /_/   \\_\\___/  |_| \\___/ \\____|_| |_|_| \\_\\\\___/ \\___/ |_|                   "
    echo "                                                                                "
    echo "        Termux Linux X11 & Touch Desktop Automated Installer                    "
    echo "================================================================================"
    echo -e "${RESET}"
}

log_info() {
    echo -e "${BLUE}${BOLD}[INFO]${RESET} ${WHITE}$1${RESET}"
}

log_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} ${WHITE}$1${RESET}"
}

log_warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${RESET} ${WHITE}$1${RESET}"
}

log_error() {
    echo -e "${RED}${BOLD}[ERROR]${RESET} ${WHITE}$1${RESET}"
}

log_section() {
    print_banner
    echo ""
    echo -e "${PURPLE}${BOLD}>>> $1 <<<${RESET}"
    local term_width=$(tput cols 2>/dev/null || echo 80)
    local divider=$(printf "%${term_width}s" | tr ' ' '-')
    echo -e "${divider}"
}

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

# --- Step 1: Pre-Install Dependencies & Verify Internet Connection ---
install_all_dependencies() {
    log_section "Step 1: Installing Required Termux & System Dependencies"

    # Define a helper function to safely run pkg commands as the normal Termux user
    run_pkg() {
        if [ "$(id -u)" -eq 0 ]; then
            # Find the actual Termux user (usually u0_aXXX)
            TERMUX_USER=$(stat -c "%U" /data/data/com.termux/files/home 2>/dev/null || stat -c "%U" /data/data/com.termux)
            if [ -n "$TERMUX_USER" ] && [ "$TERMUX_USER" != "root" ]; then
                su -c "$*" "$TERMUX_USER"
            else
                log_warn "Could not determine Termux user to drop privileges. Attempting raw command..."
                eval "$@"
            fi
        else
            eval "$@"
        fi
    }

    echo ""
    echo -e "${CYAN}${BOLD}Would you like to install dependencies automatically?${RESET}"
    echo -e "${YELLOW}(Recommended Y for first time install. Select N to skip if already installed)${RESET}"
    read -p "Install dependencies? [Y/n]: " install_deps
    
    if [[ "$install_deps" =~ ^[Yy]$ ]] || [[ -z "$install_deps" ]]; then

        # Attempt to use standard Termux package manager safely
    log_info "Updating Termux package lists (apt update && apt full-upgrade)..."
    
    # First use apt directly to bypass curl/pkg errors on fresh installs
    if ! run_pkg "apt update -y && apt full-upgrade -y"; then
        log_warn "apt update failed. Falling back to pkg update..."
        if ! run_pkg "pkg update -y && pkg upgrade -y"; then
            log_warn "Initial package update returned non-zero code. Retrying repository update..."
            sleep 2
            if ! run_pkg "pkg update -y"; then
                echo ""
                log_error "Failed to update package repositories!"
                log_error "Please check your internet connection and try again."
                echo ""
                exit 1
            fi
        fi
    fi

    # Allow user to select the fastest mirror for subsequent downloads
    log_info "Launching Termux Repo Manager (Select the fastest mirror for your region)..."
    run_pkg "termux-change-repo" || true

    log_info "Enabling required repositories (root-repo, x11-repo, tur-repo)..."
    run_pkg "pkg install -y root-repo x11-repo tur-repo 2>/dev/null" || true

    log_info "Installing Python, pip, tsu & core utilities..."
    DEPS=(
        "python"
        "tsu"
        "pulseaudio"
        "termux-x11-nightly"
        "wget"
        "curl"
        "git"
        "figlet"
        "ncurses-utils"
        "pciutils"
        "tar"
        "xz-utils"
        "procps"
        "virglrenderer-android"
        "mesa-zink"
        "mesa-vulkan-icd-freedreno"
        "vulkan-loader-generic"
    )

    FAILED_PACKAGES=()
    log_info "Bulk installing Termux packages to save time..."
    if ! run_pkg "pkg install -y ${DEPS[*]}"; then
        log_warn "Bulk installation failed. Falling back to sequential installation..."
        for dep in "${DEPS[@]}"; do
            log_info "Installing Termux package: $dep"
            if ! run_pkg "pkg install -y \"$dep\""; then
                log_warn "Package '$dep' installation failed. Attempting retry..."
                if ! run_pkg "pkg install -y \"$dep\""; then
                    FAILED_PACKAGES+=("$dep")
                fi
            fi
        done
    fi

    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        log_warn "Some packages could not be installed directly: ${FAILED_PACKAGES[*]}"
        log_info "Verifying internet connectivity..."
        if ! ping -c 1 8.8.8.8 &>/dev/null && ! curl -s --connect-timeout 5 https://1.1.1.1 &>/dev/null; then
            echo ""
            log_error "Network unreachable during package installation!"
            log_error "Please check your internet connection and try again."
            echo ""
            exit 1
        fi
    fi

    log_info "Installing 'chroot-distro' Python package via pip..."
    python3 -m pip install --upgrade chroot-distro --break-system-packages 2>/dev/null || \
    python3 -m pip install --upgrade chroot-distro 2>/dev/null || \
    pip install chroot-distro --break-system-packages 2>/dev/null || \
    pip install chroot-distro 2>/dev/null || \
    log_warn "pip install chroot-distro completed with warning. Checking command availability..."

    PREFIX_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    export PATH="$PATH:$HOME/.local/bin:$PREFIX_BIN:/system/bin"

        log_success "All Termux dependencies installed successfully."
    else
        log_info "Skipping dependency installation..."
    fi
}

# --- Step 2: Check Root Privileges & Elevation (Run BEFORE Credentials Prompt) ---
check_and_elevate_root() {
    log_section "Step 2: Verifying Root Privileges & Elevation"
    
    # 1. Check if currently running as root (UID 0)
    if [ "$(id -u)" -eq 0 ]; then
        log_success "Script is running with root privileges (UID 0)."
        IS_ROOT=true
        export IS_ROOT
        return 0
    fi

    log_warn "Script is currently running as non-root user (UID $(id -u))."

    # 2. Attempt root elevation cleanly via tsu (Termux official su wrapper) or su
    log_info "Attempting root elevation via tsu / su..."
    export CALLER_PWD="${CALLER_PWD:-$PWD}"
    SCRIPT_PATH="$SCRIPT_DIR/setup.sh"
    [ ! -f "$SCRIPT_PATH" ] && SCRIPT_PATH="$PWD/setup.sh"
    
    chmod -R 755 "$SCRIPT_DIR" 2>/dev/null || true
    chmod -R 755 "${PREFIX:-/data/data/com.termux/files/usr}/bin" 2>/dev/null || true

    set +e
    if command -v tsu &>/dev/null; then
        tsu -c "CALLER_PWD='$CALLER_PWD' bash '$SCRIPT_PATH' --elevated $*"
        ELEV_STATUS=$?
        if [ $ELEV_STATUS -eq 0 ]; then
            exit 0
        fi
    fi

    if command -v su &>/dev/null; then
        su -c "CALLER_PWD='$CALLER_PWD' bash '$SCRIPT_PATH' --elevated $*"
        ELEV_STATUS=$?
        if [ $ELEV_STATUS -eq 0 ]; then
            exit 0
        fi
    fi
    set -e

    # 3. If root elevation failed, display the formatted ROOT ACCESS REQUIRED prompt banner
    echo ""
    log_error "Root access (UID 0) is REQUIRED to set up Debian chroot environment."
    echo ""
    echo -e "${YELLOW}${BOLD}================================================================================"
    echo "                         ROOT ACCESS REQUIRED                                   "
    echo "================================================================================"
    echo -e "${WHITE}Please choose one of the following options to proceed:${RESET}"
    echo ""
    echo -e "${CYAN}Option 1:${RESET} Grant Termux root permissions in your Root Manager:"
    echo -e "          ${WHITE}(Magisk, KernelSU, APatch, or SuperSU)${RESET}"
    echo ""
    echo -e "${CYAN}Option 2:${RESET} Root your Android device if it is not currently rooted."
    echo -e "${YELLOW}${BOLD}================================================================================"
    echo -e "${RESET}"
    exit 1
}

# --- Custom Rootfs Installer Flow ---
custom_rootfs_installer() {
    IS_CUSTOM_ROOTFS=1
    log_section "Custom Rootfs Automated Installation"
    
    TERMUX_HOME="/data/data/com.termux/files/home"
    
    if [ -f "$PWD/custom.tar.gz" ]; then
        CUSTOM_ARCHIVE="$PWD/custom.tar.gz"
    elif [ -n "$CALLER_PWD" ] && [ -f "$CALLER_PWD/custom.tar.gz" ]; then
        CUSTOM_ARCHIVE="$CALLER_PWD/custom.tar.gz"
    elif [ -f "$TERMUX_HOME/custom.tar.gz" ]; then
        CUSTOM_ARCHIVE="$TERMUX_HOME/custom.tar.gz"
    else
        CUSTOM_ARCHIVE="$PWD/custom.tar.gz"
    fi
    
    if [ ! -f "$CUSTOM_ARCHIVE" ]; then
        echo ""
        print_divider
        print_centered "${YELLOW}${BOLD}No 'custom.tar.gz' found!${RESET}"
        echo ""
        print_centered "${WHITE}Please copy or move your rootfs archive to the current folder or Termux home:${RESET}"
        print_centered "${CYAN}${BOLD}$PWD/custom.tar.gz${RESET}"
        print_centered "${WHITE}or:${RESET} ${CYAN}${BOLD}$TERMUX_HOME/custom.tar.gz${RESET}"
        echo ""
        print_centered "${WHITE}Example command:${RESET}"
        print_centered "${GREEN}cp /sdcard/Download/your-rootfs.tar.gz ./custom.tar.gz${RESET}"
        print_divider
        echo ""
        read -rp "$(echo -e "${YELLOW}Press [Enter] after placing the file, or type 'q' to exit: ${RESET}")" retry_choice
        if [[ "${retry_choice,,}" == "q"* ]]; then
            echo -e "${CYAN}Installation cancelled.${RESET}"
            exit 0
        fi
        if [ -f "$PWD/custom.tar.gz" ]; then
            CUSTOM_ARCHIVE="$PWD/custom.tar.gz"
        elif [ -n "$CALLER_PWD" ] && [ -f "$CALLER_PWD/custom.tar.gz" ]; then
            CUSTOM_ARCHIVE="$CALLER_PWD/custom.tar.gz"
        elif [ -f "$TERMUX_HOME/custom.tar.gz" ]; then
            CUSTOM_ARCHIVE="$TERMUX_HOME/custom.tar.gz"
        fi
        if [ ! -f "$CUSTOM_ARCHIVE" ]; then
            log_error "File still not found. Please place custom.tar.gz in the current folder or $TERMUX_HOME and try again."
            exit 1
        fi
    fi
    
    log_info "Verifying integrity of $CUSTOM_ARCHIVE..."
    local is_valid_tar=0
    if gzip -t "$CUSTOM_ARCHIVE" >/dev/null 2>&1; then
        is_valid_tar=1
    elif xz -t "$CUSTOM_ARCHIVE" >/dev/null 2>&1; then
        is_valid_tar=1
    elif bzip2 -t "$CUSTOM_ARCHIVE" >/dev/null 2>&1; then
        is_valid_tar=1
    elif tar -tf "$CUSTOM_ARCHIVE" >/dev/null 2>&1; then
        is_valid_tar=1
    fi

    if [ "$is_valid_tar" -eq 0 ]; then
        log_error "The file at $CUSTOM_ARCHIVE is not a valid rootfs archive or is corrupted."
        echo -e "${YELLOW}Please ensure your file is a valid .tar.gz, .tar.xz, .tar.bz2, or .tar rootfs.${RESET}"
        exit 1
    fi
    log_success "Rootfs archive verified successfully ($CUSTOM_ARCHIVE)."
    echo ""
    
    # 1. OS Family
    print_divider
    print_centered "${WHITE}${BOLD}Select the base OS Family for this rootfs:${RESET}"
    echo ""
    print_centered "  ${CYAN}1) Debian${RESET}     (Debian base / APT packages)          "
    print_centered "  ${CYAN}2) Ubuntu${RESET}     (Ubuntu base / Standard APT packages) "
    print_centered "  ${CYAN}3) Fedora${RESET}     (Fedora / RHEL / DNF packages)        "
    print_centered "  ${CYAN}4) Arch Linux${RESET} (Arch / Pacman packages)              "
    print_divider
    echo ""
    while true; do
        read -rp "$(echo -e "${YELLOW}Enter choice [1-4] (default: 1): ${RESET}")" FAM_CHOICE
        case "$FAM_CHOICE" in
            1|"") DISTRO_FAMILY="debian"; break ;;
            2) DISTRO_FAMILY="ubuntu"; break ;;
            3) DISTRO_FAMILY="fedora"; break ;;
            4) DISTRO_FAMILY="arch"; break ;;
            *) log_warn "Invalid choice. Please enter 1, 2, 3, or 4." ;;
        esac
    done
    
    # 2. Container Name
    echo ""
    while true; do
        read -rp "$(echo -e "${CYAN}Enter a unique container name (e.g. ubuntu-jammy, my-os): ${RESET}")" CUSTOM_NAME
        CUSTOM_NAME="${CUSTOM_NAME,,}"
        if [[ "$CUSTOM_NAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            local existing_distros=()
            while IFS= read -r d; do [ -n "$d" ] && existing_distros+=("$d"); done < <(autochroot_list_distros)
            local name_taken=0
            for ed in "${existing_distros[@]}"; do
                if [ "$ed" == "$CUSTOM_NAME" ]; then
                    name_taken=1
                    break
                fi
            done
            if [ "$name_taken" -eq 1 ]; then
                log_warn "Container name '$CUSTOM_NAME' is already installed! Please choose another name."
            else
                SELECTED_DISTRO="$CUSTOM_NAME"
                break
            fi
        else
            log_warn "Invalid name. Must start with a lowercase letter and contain only lowercase letters, numbers, '-', or '_'."
        fi
    done
    
    # 3. Setup Mode
    echo ""
    print_divider
    print_centered "${WHITE}${BOLD}Select Configuration Mode:${RESET}"
    echo ""
    print_centered "  ${CYAN}1) Full Autochroot Setup${RESET} (XFCE4, Touch Audio/X11, User, GPU)    "
    print_centered "  ${CYAN}2) Import Only${RESET}          (Headless / Raw Root Container without GUI) "
    print_divider
    echo ""
    read -rp "$(echo -e "${YELLOW}Enter choice [1-2] (default: 1): ${RESET}")" CONF_MODE_CHOICE
    case "$CONF_MODE_CHOICE" in
        2) CUSTOM_SETUP_MODE="import" ;;
        *) CUSTOM_SETUP_MODE="full" ;;
    esac
    
    echo "$SELECTED_DISTRO" > "$HOME/.chroot_distro" 2>/dev/null || true
    echo "$SELECTED_DISTRO" > "/data/data/com.termux/files/home/.chroot_distro" 2>/dev/null || true
    export SELECTED_DISTRO DISTRO_FAMILY CUSTOM_SETUP_MODE IS_CUSTOM_ROOTFS
    log_success "Custom configuration configured: ${SELECTED_DISTRO^^} (Family: ${DISTRO_FAMILY^^}, Mode: ${CUSTOM_SETUP_MODE^^})"
}

# --- Step 2.5: Select Linux Distribution ---
get_distro_selection() {
    if [ "${IS_CUSTOM_MODE:-0}" -eq 1 ]; then
        custom_rootfs_installer
        return 0
    fi

    log_section "Step 2.5: Select Linux Distribution"
    
    if [ -f "$HOME/.chroot_distro" ]; then
        PREV_DISTRO=$(cat "$HOME/.chroot_distro" | tr -d '\r\n')
        echo -e "${YELLOW}Previous selection detected: ${CYAN}${PREV_DISTRO^^}${RESET}"
    fi

    echo ""
    print_divider
    print_centered "${WHITE}${BOLD}Please choose the Linux distribution to install:${RESET}"
    echo ""
    print_centered "  ${CYAN}1) Debian${RESET}    (Recommended - Highly stable, excellent support)  "
    print_centered "  ${CYAN}2) Fedora${RESET}    (Alternative - Modern, cutting-edge software)     "
    print_centered "  ${CYAN}3) Archlinux${RESET} (For advanced users)                              "
    print_centered "  ${CYAN}4) Custom${RESET}    (Import custom.tar.gz rootfs from ~/ directory)   "
    print_divider
    echo ""
    while true; do
        read -rp "$(echo -e "${YELLOW}Enter choice [1-4] (default: 1): ${RESET}")" DISTRO_CHOICE
        case "$DISTRO_CHOICE" in
            1|"") SELECTED_DISTRO="debian"; DISTRO_FAMILY="debian"; break ;;
            2) SELECTED_DISTRO="fedora"; DISTRO_FAMILY="fedora"; break ;;
            3) SELECTED_DISTRO="archlinux"; DISTRO_FAMILY="arch"; break ;;
            4) custom_rootfs_installer; return 0 ;;
            *) log_warn "Invalid choice. Please enter 1, 2, 3, or 4." ;;
        esac
    done

    echo "$SELECTED_DISTRO" > "$HOME/.chroot_distro" 2>/dev/null || true
    echo "$SELECTED_DISTRO" > "/data/data/com.termux/files/home/.chroot_distro" 2>/dev/null || true
    chmod 666 "$HOME/.chroot_distro" 2>/dev/null || true
    chmod 666 "/data/data/com.termux/files/home/.chroot_distro" 2>/dev/null || true
    
    export SELECTED_DISTRO DISTRO_FAMILY
    log_success "Selected distribution: ${SELECTED_DISTRO^^}"
}

# --- Step 3: Prompt User Credentials (Prompted ONCE after root elevation) ---
get_user_credentials() {
    if [ "$CUSTOM_SETUP_MODE" = "import" ]; then
        USERNAME="root"
        echo "root" > "$HOME/.${SELECTED_DISTRO}_user" 2>/dev/null || true
        echo "root" > "/data/data/com.termux/files/home/.${SELECTED_DISTRO}_user" 2>/dev/null || true
        autochroot_save_distro "$SELECTED_DISTRO" "${DISTRO_FAMILY:-debian}" "import" "root" 2>/dev/null || true
        log_info "Import-only mode: using root account for ${SELECTED_DISTRO^^}."
        return 0
    fi

    log_section "Step 3: User Account Setup for ${SELECTED_DISTRO^^}"
    
    while true; do
        read -rp "$(echo -e "${CYAN}Enter desired username for ${SELECTED_DISTRO^^} chroot: ${RESET}")" USERNAME
        if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        else
            log_warn "Invalid username. Must start with a letter/underscore and contain only lowercase letters, digits, '_' or '-'."
        fi
    done

    while true; do
        read -rsp "$(echo -e "${CYAN}Enter password for $USERNAME: ${RESET}")" PASSWORD
        echo ""
        read -rsp "$(echo -e "${CYAN}Confirm password: ${RESET}")" PASSWORD_CONFIRM
        echo ""
        
        if [ -z "$PASSWORD" ]; then
            log_warn "Password cannot be empty."
        elif [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
            break
        else
            log_warn "Passwords do not match. Please try again."
        fi
    done

    while true; do
        read -rp "$(echo -e "${CYAN}Enable passwordless sudo? [y/N]: ${RESET}")" SUDO_PROMPT
        case "${SUDO_PROMPT,,}" in
            y|yes) SUDO_CHOICE="yes"; break ;;
            n|no|"") SUDO_CHOICE="no"; break ;;
            *) log_warn "Invalid choice. Enter y or n." ;;
        esac
    done

    # Save created username to configuration file for launcher scripts
    echo "$USERNAME" > "$HOME/.${SELECTED_DISTRO}_user" 2>/dev/null || true
    echo "$USERNAME" > "/data/data/com.termux/files/home/.${SELECTED_DISTRO}_user" 2>/dev/null || true
    # Maintain legacy fallback
    echo "$USERNAME" > "$HOME/.debian_user" 2>/dev/null || true
    echo "$USERNAME" > "/data/data/com.termux/files/home/.debian_user" 2>/dev/null || true
    chmod 666 "$HOME/.debian_user" 2>/dev/null || true
    chmod 666 "/data/data/com.termux/files/home/.debian_user" 2>/dev/null || true

    if [ -z "$DISTRO_FAMILY" ]; then
        case "$SELECTED_DISTRO" in
            fedora) DISTRO_FAMILY="fedora" ;;
            archlinux) DISTRO_FAMILY="arch" ;;
            *) DISTRO_FAMILY="debian" ;;
        esac
    fi
    autochroot_save_distro "$SELECTED_DISTRO" "$DISTRO_FAMILY" "full" "$USERNAME" 2>/dev/null || true

    log_success "User credentials registered for '$USERNAME'."
}

# --- Step 4: Install Chroot Environment ---
install_chroot_distro() {
    log_section "Step 4: Installing ${SELECTED_DISTRO^^} Environment via $DISTRO_CMD"
    
    if [ "${IS_CUSTOM_ROOTFS:-0}" -eq 1 ] && [ -f "$CUSTOM_ARCHIVE" ]; then
        log_info "Launching '$DISTRO_CMD install -n $SELECTED_DISTRO $CUSTOM_ARCHIVE'..."
        if ! $DISTRO_CMD install -n "$SELECTED_DISTRO" "$CUSTOM_ARCHIVE"; then
            log_warn "Standard chroot-distro install encountered an archive header issue. Attempting native tar extraction fallback..."
            ROOTFS_DEST="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/chroot-distro/installed-rootfs/$SELECTED_DISTRO"
            mkdir -p "$ROOTFS_DEST"
            if tar -xf "$CUSTOM_ARCHIVE" -C "$ROOTFS_DEST" 2>/dev/null || tar -xzf "$CUSTOM_ARCHIVE" -C "$ROOTFS_DEST" 2>/dev/null; then
                # Configure basic Android resolver & hosts files
                echo "nameserver 8.8.8.8" > "$ROOTFS_DEST/etc/resolv.conf" 2>/dev/null || true
                echo "127.0.0.1 localhost" > "$ROOTFS_DEST/etc/hosts" 2>/dev/null || true
                log_success "Native extraction fallback succeeded."
            else
                log_error "Installation stopped or failed for custom rootfs '$SELECTED_DISTRO'!"
                exit 1
            fi
        fi
        # Ensure container manifest.json exists to avoid chroot-distro warnings
        CONTAINER_META_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/chroot-distro/containers/$SELECTED_DISTRO"
        mkdir -p "$CONTAINER_META_DIR" 2>/dev/null || true
        if [ ! -f "$CONTAINER_META_DIR/manifest.json" ]; then
            echo '{"arch": "aarch64", "architecture": "aarch64"}' > "$CONTAINER_META_DIR/manifest.json" 2>/dev/null || true
        fi

        log_success "Custom rootfs '$SELECTED_DISTRO' installed successfully."
        read -rp "Delete $CUSTOM_ARCHIVE to free storage? [y/N]: " del_custom
        case "${del_custom,,}" in y|yes) rm -f "$CUSTOM_ARCHIVE" ;; esac
    elif [ "$SELECTED_DISTRO" = "archlinux" ]; then
        log_info "Downloading Arch Linux ARM (aarch64) rootfs..."
        ARCH_TAR="/data/local/tmp/ArchLinuxARM-aarch64-latest.tar.gz"
        mkdir -p /data/local/tmp
        
        # Always remove existing file to get latest and avoid corrupted downloads
        rm -f "$ARCH_TAR"
        wget -q --show-progress -O "$ARCH_TAR" "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz" || curl -L "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz" -o "$ARCH_TAR"
        
        log_info "Launching '$DISTRO_CMD install -n archlinux $ARCH_TAR'..."
        if ! $DISTRO_CMD install -n archlinux "$ARCH_TAR"; then
            log_error "Installation stopped or failed for Arch Linux!"
            exit 1
        fi
        # We can safely delete the tarball after successful installation to save space
        rm -f "$ARCH_TAR"
    else
        log_info "Launching '$DISTRO_CMD install $SELECTED_DISTRO'..."
        if ! $DISTRO_CMD install $SELECTED_DISTRO; then
            log_error "Installation stopped or failed for ${SELECTED_DISTRO^^}!"
            exit 1
        fi
    fi

    log_success "${SELECTED_DISTRO^^} chroot environment is ready."
}

## GPU configuration has been decoupled and is now handled by fix_gpu.sh at the end of setup

# --- Step 6: Configure System & Touch DE ---
configure_chroot_system() {
    if [ "$CUSTOM_SETUP_MODE" = "import" ]; then
        log_info "Import-only mode: skipping desktop & user configuration."
        return 0
    fi

    log_section "Step 6: Configuring ${SELECTED_DISTRO^^} Chroot (User, Sudo, Audio, X11, Touch DE, Drivers)"
    
    DISTRO_SETUP_SCRIPT="$SCRIPT_DIR/scripts/distro_setup.sh"

    if [ ! -f "$DISTRO_SETUP_SCRIPT" ]; then
        log_error "Missing configuration script: $DISTRO_SETUP_SCRIPT"
        exit 1
    fi

    log_info "Injecting configuration script directly into ${SELECTED_DISTRO^^} rootfs..."

    SETUP_B64=$(base64 -w0 "$DISTRO_SETUP_SCRIPT" 2>/dev/null || base64 "$DISTRO_SETUP_SCRIPT" | tr -d '\r\n')
    
    # Inject local Mesa drivers zip if it exists (for offline/developer testing on pure Debian)
    if [ "$DISTRO_FAMILY" != "ubuntu" ]; then
        ROOTFS_DIR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/chroot-distro/installed-rootfs/$SELECTED_DISTRO"
        if [ -d "$ROOTFS_DIR/tmp" ] && [ -f "$SCRIPT_DIR/mesa-debs-trixie.zip" ]; then
            cp "$SCRIPT_DIR/mesa-debs-trixie.zip" "$ROOTFS_DIR/tmp/mesa-debs-trixie.zip" 2>/dev/null || true
        fi
    fi

    $DISTRO_CMD login $SELECTED_DISTRO -- bash -c "
        export SETUP_MODE='$SETUP_MODE'
        echo '$SETUP_B64' | base64 -d > /tmp/distro_setup.sh
        chmod +x /tmp/distro_setup.sh
        bash /tmp/distro_setup.sh '$USERNAME' '$PASSWORD' '$IS_ADRENO' '$ADRENO_SERIES' '$DISTRO_FAMILY' '$SUDO_CHOICE'
    "

    log_success "${SELECTED_DISTRO^^} internal configuration complete."
}

# --- Step 7: Configure Launchers & Termux Audio/X11 Integration ---
setup_launchers() {
    log_section "Step 7: Setting up Launcher Scripts & Audio/X11 Configuration"

    START_SCRIPT="$SCRIPT_DIR/start-chroot.sh"
    
    if [ ! -f "$START_SCRIPT" ]; then
        log_error "Missing start script: $START_SCRIPT"
        exit 1
    fi

    log_success "Launcher script successfully prepared in repository."
}

# --- Step 8: GPU Driver Verification & Final Output ---
verify_and_finish() {
    if [ "$CUSTOM_SETUP_MODE" = "import" ]; then
        echo ""
        print_divider
        print_centered "${GREEN}${BOLD}✓ Custom Rootfs '${SELECTED_DISTRO^^}' Imported Successfully!${RESET}"
        print_divider
        echo ""
        print_centered "${WHITE}Launch your custom container directly using:${RESET}"
        print_centered "${GREEN}${BOLD}autochroot start${RESET}  ${WHITE}or${RESET}  ${CYAN}${BOLD}$DISTRO_CMD login $SELECTED_DISTRO${RESET}"
        echo ""
        print_divider
        return 0
    fi

    log_section "Step 8: Verifying GPU Drivers & Finalizing Installation"

    # Enforce device permissions on host
    chmod 666 /dev/kgsl-3d0 2>/dev/null || true
    chmod 666 /dev/dri/* 2>/dev/null || true

    if [ -f "./scripts/fix_gpu.sh" ]; then
        bash ./scripts/fix_gpu.sh "$SELECTED_DISTRO"
    elif [ -f "$HOME/Termux Script/scripts/fix_gpu.sh" ]; then
        bash "$HOME/Termux Script/scripts/fix_gpu.sh" "$SELECTED_DISTRO"
    else
        log_warn "Could not locate scripts/fix_gpu.sh to perform automatic hardware test."
    fi

    VERIFY_RESULT=$($DISTRO_CMD login $SELECTED_DISTRO -- bash -c "
        export DISPLAY=:0
        export PULSE_SERVER=tcp:127.0.0.1:4713
        if [ -f /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json ] || [ -f /etc/vulkan/icd.d/turnip_icd.json ]; then
            echo 'VULKAN_READY'
        elif command -v glxinfo &> /dev/null; then
            echo 'OPENGL_READY'
        else
            echo 'DESKTOP_READY'
        fi
    " 2>/dev/null || echo "CHECK_FAILED")

    echo ""
    echo -e "${GREEN}${BOLD}"
    if command -v figlet &> /dev/null; then
        figlet -f standard "Installation Finished"
    else
        echo "================================================================="
        echo "   I N S T A L L A T I O N   F I N I S H E D   S U C C E S S !"
        echo "================================================================="
    fi
    echo -e "${RESET}"

    GPU_DRIVER_NAME="Unknown (Check fix_gpu.sh logs)"
    if [ -f /tmp/gpu_driver_name.txt ]; then
        GPU_DRIVER_NAME=$(cat /tmp/gpu_driver_name.txt)
        rm -f /tmp/gpu_driver_name.txt
    fi

    echo -e "${CYAN}${BOLD}"
    echo "================================================================================"
    echo "                          SUMMARY & INSTRUCTIONS                                "
    echo "================================================================================"
    echo -e "${WHITE}1. Distro Manager:   ${GREEN}$DISTRO_CMD (Python PyPI chroot-distro)${WHITE}"
    echo -e "${WHITE}2. OS Installed:     ${GREEN}${SELECTED_DISTRO^^}${WHITE}"
    echo -e "${WHITE}3. Username:         ${YELLOW}$USERNAME${WHITE}"
    echo -e "${WHITE}4. Sudo Privileges:  ${GREEN}Granted (Passwordless sudo for $USERNAME)${WHITE}"
    echo -e "${WHITE}5. Audio Protocol:   ${GREEN}PulseAudio TCP (127.0.0.1:4713)${WHITE}"
    echo -e "${WHITE}6. Display Output:   ${GREEN}Termux:X11 (DISPLAY=:0)${WHITE}"
    echo -e "${WHITE}7. GPU Driver:       ${GREEN}$GPU_DRIVER_NAME${WHITE}"
    echo -e "${WHITE}8. Desktop Env:      ${GREEN}Touch-Optimized XFCE4 Desktop (with virtual keyboard)${WHITE}"
    echo -e "${WHITE}9. Helper Utilities: ${GREEN}gpu-status, enable-zink, enable-freedreno, enable-software${WHITE}"
    echo "--------------------------------------------------------------------------------"
    echo -e "${YELLOW}${BOLD}HOW TO RUN:${RESET}"
    echo -e "${WHITE}  - Open the ${CYAN}Termux:X11${WHITE} app on your Android device."
    echo -e "${WHITE}  - Run launcher globally (${RED}${BOLD}Do NOT use sudo${RESET}${WHITE}): ${GREEN}autochroot start${WHITE}"
    echo "================================================================================"
    echo -e "${RESET}"
}

# --- Automatic De-elevation & Permission Restoration ---
restore_user_permissions() {
    if [ "$(id -u)" -eq 0 ]; then
        local termux_user
        termux_user=$(stat -c "%U" /data/data/com.termux/files/home 2>/dev/null || stat -c "%U" /data/data/com.termux 2>/dev/null || echo "")
        if [ -n "$termux_user" ] && [ "$termux_user" != "root" ]; then
            chown -R "$termux_user:$termux_user" /data/data/com.termux/files/home/.chroot_distro* /data/data/com.termux/files/home/.*_user /data/data/com.termux/files/home/custom.tar.gz 2>/dev/null || true
            chown -R "$termux_user:$termux_user" "${PREFIX:-/data/data/com.termux/files/usr}/var/lib/autochroot" 2>/dev/null || true
        fi
    fi
}
trap restore_user_permissions EXIT

# --- Main Execution Flow ---
main() {
    IS_CUSTOM_MODE=0
    for arg in "$@"; do
        if [ "$arg" == "-c" ] || [ "$arg" == "--custom" ]; then
            IS_CUSTOM_MODE=1
            break
        fi
    done
    export IS_CUSTOM_MODE

    if [ "$1" == "--elevated" ]; then
        # We are on the second pass (elevated to root). Skip deps.
        shift # remove --elevated from args
        get_distro_selection
        get_user_credentials
        install_chroot_distro
        # GPU driver configuration is handled externally at the end
        configure_chroot_system
        setup_launchers
        verify_and_finish
        # Cleanly exit root subshell to return to the non-root terminal session
        exit 0
    else
        # First pass (normal user)
        if [ "$(id -u)" -eq 0 ]; then
            echo -e "${RED}${BOLD}[ERROR] Please run this script WITHOUT sudo!${RESET}"
            echo -e "${WHITE}The script will automatically install Termux packages and then ask for root privileges when needed.${RESET}"
            exit 1
        fi
        print_banner
        install_all_dependencies
        check_and_elevate_root "$@"
        # Return cleanly to the caller's standard user prompt
        exit 0
    fi
}

main "$@"
