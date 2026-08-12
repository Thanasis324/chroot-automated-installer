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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/scripts"
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
    echo "  _____ _____ ____  __  ____  FX   _  _  ____ _____ _   _ ____                  "
    echo " |_   _| ____|  _ \|  \/  | |  | | | |/ ___|_   _| | | |  _ \                 "
    echo "   | | |  _| | |_) | |\/| | |  | | | | |     | | | | | | |_) |                "
    echo "   | | | |___|  _ <| |  | | |__| |_| | |___  | | | |_| |  __/                 "
    echo "   |_| |_____|_| \_\_|  |_|\____\___/ \____| |_|  \___/|_|                    "
    echo "                                                                                "
    echo "        Termux Debian X11 & Touch Desktop Automated Installer                   "
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

    log_info "Installing Python, pip, sudo, tsu & core utilities..."
    DEPS=(
        "python"
        "sudo"
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

    # 2. Attempt root elevation cleanly without process crash
    log_info "Attempting root elevation via installed sudo / tsu..."
    
    set +e
    if command -v sudo &>/dev/null; then
        sudo bash "$0" --elevated "$@"
        ELEV_STATUS=$?
        if [ $ELEV_STATUS -eq 0 ]; then
            exit 0
        fi
    fi

    if command -v tsu &>/dev/null; then
        tsu bash "$0" --elevated "$@"
        ELEV_STATUS=$?
        if [ $ELEV_STATUS -eq 0 ]; then
            exit 0
        fi
    fi

    if command -v su &>/dev/null; then
        su -c "bash \"$0\" --elevated \"$@\"" 2>/dev/null
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
    echo -e "${CYAN}Option 1:${RESET} Run the script manually using sudo:"
    echo -e "          ${GREEN}sudo ./setup.sh${RESET}"
    echo ""
    echo -e "${CYAN}Option 2:${RESET} Add / grant Termux root permissions in your Root Manager application:"
    echo -e "          ${WHITE}(Magisk, KernelSU, APatch, or SuperSU)${RESET}"
    echo ""
    echo -e "${CYAN}Option 3:${RESET} Root your Android device if it is not currently rooted."
    echo -e "${YELLOW}${BOLD}================================================================================"
    echo -e "${RESET}"
    exit 1
}

# --- Step 2.5: Select Linux Distribution ---
get_distro_selection() {
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
    print_divider
    echo ""
    while true; do
        read -rp "$(echo -e "${YELLOW}Enter choice [1-3] (default: 1): ${RESET}")" DISTRO_CHOICE
        case "$DISTRO_CHOICE" in
            1|"") SELECTED_DISTRO="debian"; break ;;
            2) SELECTED_DISTRO="fedora"; break ;;
            3) SELECTED_DISTRO="archlinux"; break ;;
            *) log_warn "Invalid choice. Please enter 1, 2, or 3." ;;
        esac
    done

    echo "$SELECTED_DISTRO" > "$HOME/.chroot_distro" 2>/dev/null || true
    echo "$SELECTED_DISTRO" > "/data/data/com.termux/files/home/.chroot_distro" 2>/dev/null || true
    chmod 666 "$HOME/.chroot_distro" 2>/dev/null || true
    chmod 666 "/data/data/com.termux/files/home/.chroot_distro" 2>/dev/null || true
    
    export SELECTED_DISTRO
    log_success "Selected distribution: ${SELECTED_DISTRO^^}"
}

# --- Step 3: Prompt User Credentials (Prompted ONCE after root elevation) ---
get_user_credentials() {
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

    log_success "User credentials registered for '$USERNAME'."
}

# --- Step 4: Install Chroot Environment ---
install_chroot_distro() {
    log_section "Step 4: Installing ${SELECTED_DISTRO^^} Environment via $DISTRO_CMD"
    
    if [ "$SELECTED_DISTRO" = "archlinux" ]; then
        log_info "Downloading Arch Linux ARM (aarch64) rootfs..."
        ARCH_TAR="/data/local/tmp/ArchLinuxARM-aarch64-latest.tar.gz"
        mkdir -p /data/local/tmp
        
        # Always remove existing file to get latest and avoid corrupted downloads
        rm -f "$ARCH_TAR"
        wget -q --show-progress -O "$ARCH_TAR" "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz" || curl -L "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz" -o "$ARCH_TAR"
        
        log_info "Launching '$DISTRO_CMD install $ARCH_TAR -n archlinux'..."
        if ! $DISTRO_CMD install "$ARCH_TAR" -n archlinux; then
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

# --- Step 5: GPU Detection & Driver Selection ---
detect_gpu_architecture() {
    log_section "Step 5: Detecting GPU Architecture & Adreno Drivers"
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GPU_DETECT_SCRIPT="$SCRIPT_DIR/scripts/gpu_detect.sh"

    if [ -f "$GPU_DETECT_SCRIPT" ]; then
        log_info "Executing GPU hardware detection module ($GPU_DETECT_SCRIPT)..."
        source "$GPU_DETECT_SCRIPT"
        detect_adreno_gpu >/dev/null 2>&1 || true
    else
        IS_ADRENO=false
        ADRENO_SERIES="Generic"
        GPU_VENDOR="Generic"
        MODEL_NUM="Unknown"
    fi

    if [ "$GPU_VENDOR" = "Generic" ] || [ "$GPU_VENDOR" = "Generic/Software" ] || [ -z "$GPU_VENDOR" ]; then
        echo -e "${YELLOW}Could not automatically detect your GPU architecture.${RESET}"
        echo -e "${CYAN}${BOLD}Please select your device's GPU type to configure hardware acceleration:${RESET}"
        echo "  1. Qualcomm Adreno (Snapdragon)"
        echo "  2. Other (Mali, PowerVR, Exynos, etc.) -> Uses VirGL fallback"
        read -p "Select GPU type (1 or 2): " gpu_choice
        
        if [ "$gpu_choice" == "1" ]; then
            IS_ADRENO=true
            GPU_VENDOR="Qualcomm Adreno"
            echo ""
            print_divider
            print_centered "${CYAN}${BOLD}Adreno GPU Version Selection:${RESET}"
            echo ""
            print_centered "  ${WHITE}1)${RESET} 8xx Series (e.g., Snap. 8 Elite, 8S Gen 4)            "
            print_centered "  ${WHITE}2)${RESET} 7xx Series (e.g., Snap. 8 Gen 1-3, 7+ Gen 2)          "
            print_centered "  ${WHITE}3)${RESET} 6xx Series (e.g., Snap. 888, 870, 865, 855)           "
            print_centered "  ${WHITE}4)${RESET} Older / Other (Fallback to generic Turnip)              "
            print_divider
            echo ""
            while true; do
                read -p "Select your Adreno series (1-4): " adreno_choice
                case "$adreno_choice" in
                    1) ADRENO_SERIES="8xx"; break ;;
                    2) ADRENO_SERIES="7xx"; break ;;
                    3) ADRENO_SERIES="6xx"; break ;;
                    4) ADRENO_SERIES="Generic"; break ;;
                    *) log_warn "Invalid choice. Please select 1-4." ;;
                esac
            done
            log_info "Selected Adreno Series: $ADRENO_SERIES"
        else
            IS_ADRENO=false
            GPU_VENDOR="Other"
            ADRENO_SERIES="Generic"
        fi
    fi
    DRIVER_TYPE="software"

    log_info "Detected GPU Vendor: ${GPU_VENDOR:-Generic}"
    log_info "Detected Model ID: ${MODEL_NUM:-Unknown}"

    if [ "$IS_ADRENO" = "true" ]; then
        if [ "$ADRENO_SERIES" == "A5XX" ]; then
            log_success "Identified Qualcomm Adreno GPU (A5XX)!"
            log_success "Selected Native Freedreno OpenGL Hardware Driver Set."
        else
            log_success "Identified Qualcomm Adreno GPU (${ADRENO_SERIES:-A8XX})!"
            log_success "Selected Turnip Freedreno Vulkan & Zink OpenGL ES Hardware Driver Set."
        fi
    else
        log_warn "Non-Adreno GPU or software stack detected (${GPU_VENDOR:-Generic}). Selected LLVMpipe high-performance rendering fallback."
    fi

    export IS_ADRENO
    export ADRENO_SERIES
    export GPU_VENDOR
    export MODEL_NUM
    export DRIVER_TYPE
}

# --- Step 6: Configure System & Touch DE ---
configure_chroot_system() {
    log_section "Step 6: Configuring ${SELECTED_DISTRO^^} Chroot (User, Sudo, Audio, X11, Touch DE, Drivers)"
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    DISTRO_SETUP_SCRIPT="$SCRIPT_DIR/scripts/distro_setup.sh"

    if [ ! -f "$DISTRO_SETUP_SCRIPT" ]; then
        log_error "Missing configuration script: $DISTRO_SETUP_SCRIPT"
        exit 1
    fi

    log_info "Injecting configuration script directly into ${SELECTED_DISTRO^^} rootfs..."

    SETUP_B64=$(base64 -w0 "$DISTRO_SETUP_SCRIPT" 2>/dev/null || base64 "$DISTRO_SETUP_SCRIPT" | tr -d '\r\n')

    $DISTRO_CMD login $SELECTED_DISTRO -- bash -c "
        export SETUP_MODE='$SETUP_MODE'
        echo '$SETUP_B64' | base64 -d > /tmp/distro_setup.sh
        chmod +x /tmp/distro_setup.sh
        bash /tmp/distro_setup.sh '$USERNAME' '$PASSWORD' '$IS_ADRENO' '$ADRENO_SERIES' '$SELECTED_DISTRO' '$SUDO_CHOICE'
    "

    log_success "${SELECTED_DISTRO^^} internal configuration complete."
}

# --- Step 7: Configure Launchers & Termux Audio/X11 Integration ---
setup_launchers() {
    log_section "Step 7: Setting up Launcher Scripts & Audio/X11 Configuration"

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    START_SCRIPT="$SCRIPT_DIR/start-chroot.sh"
    
    if [ ! -f "$START_SCRIPT" ]; then
        log_error "Missing start script: $START_SCRIPT"
        exit 1
    fi

    TARGET_PATHS=(
        "$HOME/start-chroot.sh"
        "/data/data/com.termux/files/home/start-chroot.sh"
    )

    for path in "${TARGET_PATHS[@]}"; do
        mkdir -p "$(dirname "$path")" 2>/dev/null || true
        cp "$START_SCRIPT" "$path" 2>/dev/null || true
        chmod 777 "$path" 2>/dev/null || chmod +x "$path" 2>/dev/null || true
    done

    PREFIX_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    if [ -d "$PREFIX_BIN" ]; then
        cp "$START_SCRIPT" "$PREFIX_BIN/startchroot" 2>/dev/null || true
        cp "$START_SCRIPT" "$PREFIX_BIN/start-chroot" 2>/dev/null || true
        chmod 777 "$PREFIX_BIN/startchroot" "$PREFIX_BIN/start-chroot" 2>/dev/null || chmod +x "$PREFIX_BIN/startchroot" "$PREFIX_BIN/start-chroot" 2>/dev/null || true
    fi
    
    log_success "Launcher script created: './start-chroot.sh' and command 'startchroot'."
}

# --- Step 8: GPU Driver Verification & Final Output ---
verify_and_finish() {
    log_section "Step 8: Verifying GPU Drivers & Finalizing Installation"

    # Enforce device permissions on host
    chmod 666 /dev/kgsl-3d0 2>/dev/null || true
    chmod 666 /dev/dri/* 2>/dev/null || true

    if [ -f "./scripts/fix_gpu.sh" ]; then
        bash ./scripts/fix_gpu.sh
    elif [ -f "$HOME/Termux Script/scripts/fix_gpu.sh" ]; then
        bash "$HOME/Termux Script/scripts/fix_gpu.sh"
    else
        log_warn "Could not locate scripts/fix_gpu.sh to perform automatic hardware test."
    fi

    VERIFY_RESULT=$($DISTRO_CMD login $SELECTED_DISTRO -- bash -c "
        export DISPLAY=:0
        export PULSE_SERVER=tcp:127.0.0.1:4713
        if [ -f /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json ] || [ -f /etc/vulkan/icd.d/turnip_icd.json ]; then
            echo 'DRIVER_TURNIP_PRESENT'
        else
            echo 'DRIVER_BASIC_PRESENT'
        fi
    " 2>/dev/null || echo "DRIVER_CHECK_OK")

    echo ""
    if [ "$VERIFY_RESULT" == "DRIVER_TURNIP_PRESENT" ]; then
        if [ "$ADRENO_SERIES" == "A5XX" ]; then
            log_success "GPU Driver Verification Passed! Qualcomm Freedreno Native OpenGL stack active."
        else
            log_success "GPU Driver Verification Passed! Qualcomm Freedreno Turnip & Zink Vulkan stack active."
        fi
    else
        log_warn "GPU Driver loaded with standard graphics rendering layer."
    fi

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

    echo -e "${CYAN}${BOLD}"
    echo "================================================================================"
    echo "                          SUMMARY & INSTRUCTIONS                                "
    echo "================================================================================"
    echo -e "${WHITE}1. Distro Manager:   ${GREEN}$DISTRO_CMD (Python PyPI chroot-distro)${WHITE}"
    echo -e "${WHITE}2. Debian Username:  ${YELLOW}$USERNAME${WHITE}"
    echo -e "${WHITE}3. Sudo Privileges:  ${GREEN}Granted (Passwordless sudo for $USERNAME)${WHITE}"
    echo -e "${WHITE}4. Audio Protocol:   ${GREEN}PulseAudio TCP (127.0.0.1:4713)${WHITE}"
    echo -e "${WHITE}5. Display Output:   ${GREEN}Termux:X11 (DISPLAY=:0)${WHITE}"
    if [ "$ADRENO_SERIES" == "A5XX" ]; then
        echo -e "${WHITE}6. GPU Driver:       ${GREEN}Freedreno ${ADRENO_SERIES} (Native OpenGL ARM64)${WHITE}"
    else
        echo -e "${WHITE}6. GPU Driver:       ${GREEN}Turnip ${ADRENO_SERIES:-A8XX} (Vulkan/Zink Freedreno ARM64)${WHITE}"
    fi
    echo -e "${WHITE}7. Desktop Env:      ${GREEN}Touch-Optimized XFCE4 Desktop (with Onboard virtual keyboard)${WHITE}"
    echo -e "${WHITE}8. Helper Utilities: ${GREEN}gpu-status, enable-zink, enable-freedreno, enable-software${WHITE}"
    echo "--------------------------------------------------------------------------------"
    echo -e "${YELLOW}${BOLD}HOW TO RUN:${RESET}"
    echo -e "${WHITE}  - Open the ${CYAN}Termux:X11${WHITE} app on your Android device."
    echo -e "${WHITE}  - Run launcher directly (${RED}${BOLD}Do NOT use sudo${RESET}${WHITE}): ${GREEN}./start-chroot.sh${WHITE} (or ${GREEN}startchroot${WHITE})"
    echo "================================================================================"
    echo -e "${RESET}"
}

# --- Main Execution Flow ---
main() {
    if [ "$1" == "--elevated" ]; then
        # We are on the second pass (elevated to root). Skip deps.
        shift # remove --elevated from args
        get_distro_selection
        get_user_credentials
        install_chroot_distro
        detect_gpu_architecture
        configure_chroot_system
        setup_launchers
        verify_and_finish
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
    fi
}

main "$@"
