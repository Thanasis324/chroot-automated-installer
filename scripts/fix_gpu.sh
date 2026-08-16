#!/usr/bin/env bash
# ==============================================================================
# GPU Acceleration Test & Automatic Fallback Script
# Run this from Termux (outside the chroot) to automatically test and configure
# the optimal graphics driver for your device.
# ==============================================================================

set -e

BOLD="\033[1m"
GREEN="\033[38;5;46m"
YELLOW="\033[38;5;226m"
CYAN="\033[38;5;51m"
WHITE="\033[38;5;231m"
RED="\033[31m"
RESET="\033[0m"

log_info() { echo -e "${CYAN}${BOLD}[INFO]${RESET} ${WHITE}$1${RESET}"; }
log_success() { echo -e "${GREEN}${BOLD}[SUCCESS]${RESET} ${WHITE}$1${RESET}"; }
log_warn() { echo -e "${YELLOW}${BOLD}[WARNING]${RESET} ${WHITE}$1${RESET}"; }

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
    echo -e "${RED}[ERROR] chroot-distro is not installed. Please run setup.sh first.${RESET}"
    exit 1
fi

SELECTED_DISTRO="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/autochroot_state.sh" 2>/dev/null || true

# If no distro was passed as an argument, auto-detect installed distros
if [ -z "$SELECTED_DISTRO" ]; then
    INSTALLED_DISTROS=()
    while IFS= read -r d; do [ -n "$d" ] && INSTALLED_DISTROS+=("$d"); done < <(autochroot_list_distros)
    
    if [ ${#INSTALLED_DISTROS[@]} -eq 0 ]; then
        echo -e "${YELLOW}Warning: Could not automatically detect installed distros.${RESET}"
        echo ""
        print_divider
        print_centered "${CYAN}${BOLD}Please select which environment to fix, or run the installer:${RESET}"
        print_centered "  ${WHITE}1)${RESET} debian                                       "
        print_centered "  ${WHITE}2)${RESET} fedora                                       "
        print_centered "  ${WHITE}3)${RESET} archlinux                                    "
        print_centered "  ${WHITE}4)${RESET} I haven't run setup.sh yet (Run installer) "
        print_divider
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
    elif [ ${#INSTALLED_DISTROS[@]} -eq 1 ]; then
        SELECTED_DISTRO="${INSTALLED_DISTROS[0]}"
    else
        echo -e "${CYAN}${BOLD}Multiple distributions detected. Which one do you want to fix/update?${RESET}"
        select opt in "${INSTALLED_DISTROS[@]}"; do
            if [ -n "$opt" ]; then
                SELECTED_DISTRO="$opt"
                break
            else
                echo "Invalid selection."
            fi
        done
    fi
    echo "$SELECTED_DISTRO" > "$HOME/.chroot_distro"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================= UI OVERHAUL: TIERED MENUS =================

echo ""
print_divider
print_centered "${WHITE}${BOLD}Select your device's SoC Platform:${RESET}"
echo ""
print_centered "  ${CYAN}1)${RESET} Adreno (Qualcomm Snapdragon) "
print_centered "  ${CYAN}2)${RESET} Tensor (Google Pixel)        "
print_centered "  ${CYAN}3)${RESET} Exynos (Samsung)             "
print_centered "  ${CYAN}4)${RESET} Mali / PowerVR / Other       "
print_centered "  ${CYAN}5)${RESET} Auto-Detect Hardware         "
print_divider
echo ""
read -rp "Select Platform (1-5): " plat_choice

driver_choice=""

if [ "$plat_choice" == "5" ]; then
    echo -e "${YELLOW}Running Auto-Detection...${RESET}"
    if [ -f "$SCRIPT_DIR/gpu_detect.sh" ]; then
        source "$SCRIPT_DIR/gpu_detect.sh"
        detect_adreno_gpu
        if [ "$IS_ADRENO" = true ]; then
            log_info "Detected: Adreno $ADRENO_SERIES GPU ($MODEL_NUM)"
            plat_choice="1"
            if [ "$ADRENO_SERIES" == "A8XX" ]; then gen_choice="1"; fi
            if [ "$ADRENO_SERIES" == "A7XX" ]; then gen_choice="2"; fi
            if [ "$ADRENO_SERIES" == "A6XX" ]; then gen_choice="3"; fi
            if [ "$ADRENO_SERIES" == "A5XX" ] || [ "$ADRENO_SERIES" == "Generic" ]; then gen_choice="4"; fi
        else
            log_info "Detected: $GPU_VENDOR ($MODEL_NUM)"
            plat_choice="4"
        fi
    else
        log_warn "gpu_detect.sh not found. Falling back to manual selection."
        plat_choice=""
    fi
fi

if [ "$plat_choice" == "1" ]; then
    if [ -z "$gen_choice" ]; then
        echo ""
        print_divider
        print_centered "${WHITE}${BOLD}Select your Adreno GPU Generation:${RESET}"
        echo ""
        print_centered "  ${CYAN}1)${RESET} A8XX Series (Snapdragon 8s Gen 4 / 8 Elite) "
        print_centered "  ${CYAN}2)${RESET} A7XX Series (Snapdragon 8 Gen 2 / 8 Gen 3)  "
        print_centered "  ${CYAN}3)${RESET} A6XX Series (Snapdragon 845 to 8 Gen 1)     "
        print_centered "  ${CYAN}4)${RESET} A5XX Series or older                        "
        print_divider
        echo ""
        read -rp "Select Generation (1-4): " gen_choice
    fi
    
    echo ""
    print_divider
    print_centered "${WHITE}${BOLD}Select Graphics Backend:${RESET}"
    echo ""
    if [[ "$gen_choice" == "4" ]]; then
        print_centered "  ${CYAN}1)${RESET} Freedreno (Recommended Native OpenGL)    "
        print_centered "  ${CYAN}2)${RESET} Zink/Turnip (Experimental on A5XX)       "
        print_centered "  ${CYAN}3)${RESET} VirGL (Universal hardware fallback)       "
        print_centered "  ${CYAN}4)${RESET} LLVMpipe (Pure CPU Software Rendering)    "
        print_divider
        echo ""
        read -rp "Select Driver (1-4): " drv_choice
        
        case "$drv_choice" in
            1) driver_choice="2" ;; # Freedreno
            2) driver_choice="1" ;; # Zink/Turnip
            3) driver_choice="3" ;; # VirGL
            4) driver_choice="4" ;; # LLVMpipe
            *) echo "Invalid selection."; exit 1 ;;
        esac
    else
        print_centered "  ${CYAN}1)${RESET} Zink/Turnip (Recommended Vulkan API)     "
        print_centered "  ${CYAN}2)${RESET} Freedreno (Legacy fallback)              "
        print_centered "  ${CYAN}3)${RESET} VirGL (Universal software fallback)       "
        print_centered "  ${CYAN}4)${RESET} LLVMpipe (Pure CPU Software Rendering)    "
        print_divider
        echo ""
        read -rp "Select Driver (1-4): " drv_choice
        
        case "$drv_choice" in
            1) driver_choice="1" ;; # Zink
            2) driver_choice="2" ;; # Freedreno
            3) driver_choice="3" ;; # VirGL
            4) driver_choice="4" ;; # LLVMpipe
            *) echo "Invalid selection."; exit 1 ;;
        esac
    fi

elif [[ "$plat_choice" == "2" || "$plat_choice" == "3" || "$plat_choice" == "4" ]]; then
    echo ""
    print_divider
        print_centered "${YELLOW}Device Graphics Acceleration Options${RESET}"
    echo ""
        print_centered "  ${CYAN}1)${RESET} GL4ES Standalone (OpenGL to GLES Translation for Legacy / Kernel 3.x)"
        print_centered "  ${CYAN}2)${RESET} VirGL Hardware Passthrough (Host Virtualization - Kernel >= 4.4)     "
        print_centered "  ${CYAN}3)${RESET} LLVMpipe (Pure CPU Software Rendering Fallback)                     "
    print_divider
    echo ""
    read -rp "Select Driver (1-3): " drv_choice
    
    case "$drv_choice" in
        1)
            driver_choice="5" # GL4ES Standalone
            echo ""
            read -rp "$(echo -e "${CYAN}Compile latest GL4ES from source? (Recommended) [Y/n]: ${RESET}")" COMPILE_GL4ES_PROMPT
            if [[ "${COMPILE_GL4ES_PROMPT,,}" == "n"* ]]; then
                DO_COMPILE_GL4ES="no"
            else
                DO_COMPILE_GL4ES="yes"
            fi
            ;;
        2) driver_choice="3" ;; # VirGL
        3) driver_choice="4" ;; # LLVMpipe
        *) echo "Invalid selection."; exit 1 ;;
    esac
else
    echo -e "${RED}Invalid choice. Exiting.${RESET}"
    exit 1
fi

# ==============================================================

# Enforce device permissions on host just in case
chmod 666 /dev/kgsl-3d0 2>/dev/null || true
chmod 666 /dev/dri/* 2>/dev/null || true

case "$driver_choice" in
    1|2)
        if [ "$driver_choice" == "1" ]; then
            log_info "Ensuring latest Adreno Turnip/Zink drivers (lfdevs) are installed inside $SELECTED_DISTRO..."
        else
            log_info "Ensuring latest Adreno Freedreno drivers (lfdevs) are installed inside $SELECTED_DISTRO..."
        fi
        # Download and patch lfdevs mesa drivers directly inside the chroot
        $DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c '
            # Clean up and ensure core dependencies exist (Heal broken GUI from previous removals)
            if command -v dnf >/dev/null 2>&1; then
                echo "Running dnf install..."
                dnf install -y mesa-libGL mesa-dri-drivers mesa-vulkan-drivers vulkan-loader @xfce-desktop-environment libdisplay-info git cmake gcc gcc-c++ make libX11-devel libXext-devel mesa-libEGL-devel >/dev/null 2>&1
                # Remove broken gl4es wrapper if it exists
                rm -f /usr/local/lib/libGL.so* 2>/dev/null || true
            elif command -v apt-get >/dev/null 2>&1; then
                echo "Running apt-get install..."
                rm -f /etc/apt/sources.list.d/gfx-ci.list
                apt-get update >/dev/null 2>&1
                apt-get install -y libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 xfce4 xfwm4 libdisplay-info-dev >/dev/null 2>&1 || true
            elif command -v pacman >/dev/null 2>&1; then
                pacman -Sy --noconfirm vulkan-freedreno vulkan-swrast vulkan-mesa-layers vulkan-icd-loader xfce4 xfwm4 libdisplay-info >/dev/null 2>&1 || true
            fi
            
            # Failsafe: Symlink libdisplay-info if the host provides a different ABI version than lfdevs expects
            echo "Checking libdisplay-info.so.2..."
            if [ ! -f /usr/lib64/libdisplay-info.so.2 ] && ls /usr/lib64/libdisplay-info.so.* 1> /dev/null 2>&1; then
                echo "Symlinking libdisplay-info.so.2 in /usr/lib64..."
                (cd /usr/lib64 && ln -sf $(basename $(ls libdisplay-info.so.* | grep -v "\.so\.2$" | head -n 1)) libdisplay-info.so.2)
            fi
            if [ ! -f /usr/lib/aarch64-linux-gnu/libdisplay-info.so.2 ] && ls /usr/lib/aarch64-linux-gnu/libdisplay-info.so.* 1> /dev/null 2>&1; then
                echo "Symlinking libdisplay-info.so.2 in /usr/lib/aarch64-linux-gnu..."
                (cd /usr/lib/aarch64-linux-gnu && ln -sf $(basename $(ls libdisplay-info.so.* | grep -v "\.so\.2$" | head -n 1)) libdisplay-info.so.2)
            fi
            
            # Auto-detect hardware architecture
            RAW_ARCH=$(uname -m)
            case "$RAW_ARCH" in
                aarch64|arm64)
                    ARCH_SUFFIX="arm64"
                    ARCH_ARCH="arm64"
                    ;;
                armv7*|armv8l|armhf|arm)
                    ARCH_SUFFIX="armhf"
                    ARCH_ARCH="arm"
                    ;;
                x86_64|amd64)
                    ARCH_SUFFIX="x86_64"
                    ARCH_ARCH="x86_64"
                    ;;
                i*86|x86)
                    ARCH_SUFFIX="x86"
                    ARCH_ARCH="x86"
                    ;;
                *)
                    ARCH_SUFFIX="$RAW_ARCH"
                    ARCH_ARCH="$RAW_ARCH"
                    ;;
            esac

            IS_UBUNTU=0
            if [ -f /etc/os-release ] && grep -qi "ubuntu" /etc/os-release; then
                IS_UBUNTU=1
            fi
            
            if [ "$1" = "debian" ] && [ "$IS_UBUNTU" -eq 0 ] && [ "$ARCH_SUFFIX" = "arm64" ]; then
                echo "Downloading custom Debian Mesa bundle for $ARCH_SUFFIX..."
                cd /tmp
                wget -q https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip || curl -sL -o mesa-debs-trixie.zip https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip
                
                if [ -f "mesa-debs-trixie.zip" ] && unzip -t mesa-debs-trixie.zip >/dev/null 2>&1; then
                    echo "Valid Mesa zip found. Extracting and installing..."
                    unzip -q mesa-debs-trixie.zip
                    apt-get install -y --no-install-recommends ./mesa_debs/*.deb || true
                    rm -rf mesa-debs-trixie.zip mesa_debs
                else
                    echo "[ERROR] Failed to download or verify Debian Mesa bundle from GitHub!"
                    rm -f mesa-debs-trixie.zip
                fi
            else
                echo "Auto-detected architecture: $RAW_ARCH ($ARCH_SUFFIX)"
                if [ "$1" = "fedora" ]; then
                    FEDORA_VER=$(grep -oP "(?<=^VERSION_ID=).+" /etc/os-release | tr -d \")
                    LFDEVS_PATTERN="fedora_${FEDORA_VER}_${ARCH_SUFFIX}\.tar\.gz"
                elif [ "$1" = "archlinux" ]; then
                    LFDEVS_PATTERN="archlinux_${ARCH_ARCH}\.tar"
                elif [ "$IS_UBUNTU" -eq 1 ] || grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
                    UBUNTU_CODENAME=$(grep -oP "(?<=^VERSION_CODENAME=).+" /etc/os-release | tr -d \")
                    [ -z "$UBUNTU_CODENAME" ] && UBUNTU_CODENAME=$(grep -oP "(?<=^UBUNTU_CODENAME=).+" /etc/os-release | tr -d \")
                    [ -z "$UBUNTU_CODENAME" ] && UBUNTU_CODENAME="noble"
                    LFDEVS_PATTERN="ubuntu_${UBUNTU_CODENAME}_${ARCH_SUFFIX}\.tar\.gz"
                else
                    LFDEVS_PATTERN="debian_.*_${ARCH_SUFFIX}\.tar\.gz"
                fi
                # Bypass strict API rate limits by scraping the expanded_assets HTML fragment directly
                LATEST_URL=$(curl -sI https://github.com/lfdevs/mesa-for-android-container/releases/latest | grep -i "^location:" | sed "s/\r//" | awk "{print \$2}")
                TAG=$(echo "$LATEST_URL" | awk -F "/" "{print \$NF}")
                DOWNLOAD_URL=$(curl -sL "https://github.com/lfdevs/mesa-for-android-container/releases/expanded_assets/$TAG" | grep -oE "href=\"[^\"]*$LFDEVS_PATTERN\"" | head -n 1 | cut -d "\"" -f 2)
                if [ -z "$DOWNLOAD_URL" ]; then
                    DOWNLOAD_URL=$(curl -sL "https://github.com/lfdevs/mesa-for-android-container/releases/expanded_assets/$TAG" | grep -oE "href=\"[^\"]*${ARCH_SUFFIX}\.tar\.gz\"" | head -n 1 | cut -d "\"" -f 2)
                fi
                if [ -n "$DOWNLOAD_URL" ]; then
                    DOWNLOAD_URL="https://github.com$DOWNLOAD_URL"
                fi
                
                if [ -n "$DOWNLOAD_URL" ]; then
                    cd /tmp
                    # Remove old lfdevs patches if they exist (clean update)
                    rm -rf /usr/lib64/libvulkan_freedreno.so /usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so 2>/dev/null || true

                    wget -q -O mesa-turnip.tar.gz "$DOWNLOAD_URL" || curl -sL "$DOWNLOAD_URL" -o mesa-turnip.tar.gz
                    if [ "$1" = "archlinux" ]; then
                        mkdir -p /tmp/mesa-turnip
                        tar -xf mesa-turnip.tar.gz -C /tmp/mesa-turnip/ 2>/dev/null || tar -xf mesa-turnip.tar -C /tmp/mesa-turnip/ 2>/dev/null
                        pacman -U --noconfirm --overwrite "*" /tmp/mesa-turnip/*.pkg.tar.xz >/dev/null 2>&1
                        rm -rf /tmp/mesa-turnip
                    else
                        tar -zxf mesa-turnip.tar.gz -C / >/dev/null 2>&1
                        ldconfig 2>/dev/null || true
                    fi
                    rm -f mesa-turnip.tar.gz mesa-turnip.tar
                else
                    echo "[INFO] No prebuilt lfdevs package matching $ARCH_SUFFIX found (or API rate limited)."
                    echo "Using standard distribution Mesa and GLES libraries."
                fi
            fi
        ' -- "$SELECTED_DISTRO" "$driver_choice"
        
        if [ "$driver_choice" == "1" ]; then
            if [ "$gen_choice" == "3" ] || [ "$gen_choice" == "4" ]; then
                OPT_TU_DEBUG="kgsl,sysmem,noconform"
            else
                OPT_TU_DEBUG="kgsl,sysmem,noconform,nolrz"
            fi
            
            log_info "Configuring environment for Zink..."
            $DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c "
                # We DO NOT force GALLIUM_DRIVER=zink globally, as it crashes XFCE4 compositor.
                # Use zink-run for specific applications instead.
                sed -i '/export GALLIUM_DRIVER/d' /etc/profile.d/termux_env.sh 2>/dev/null || true
                sed -i '/export MESA_LOADER_DRIVER_OVERRIDE/d' /etc/profile.d/termux_env.sh 2>/dev/null || true

                sed -i '/export LIBGL_ALWAYS_SOFTWARE/d' /etc/profile.d/termux_env.sh 2>/dev/null || true
                
                # Critical Vulkan variables for Turnip on Adreno 7xx/8xx
                if ! grep -q 'VK_ICD_FILENAMES' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json:/etc/vulkan/icd.d/turnip_icd.json' >> /etc/profile.d/termux_env.sh
                fi
                if ! grep -q 'TU_DEBUG' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export TU_DEBUG=$OPT_TU_DEBUG' >> /etc/profile.d/termux_env.sh
                else
                    sed -i 's/TU_DEBUG=.*/TU_DEBUG=$OPT_TU_DEBUG/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
                fi
                if ! grep -q 'ZINK_DESCRIPTORS=lazy' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export ZINK_DESCRIPTORS=lazy' >> /etc/profile.d/termux_env.sh
                    echo 'export ZINK_DEBUG=compact' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_GL_VERSION_OVERRIDE=4.6' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_GLES_VERSION_OVERRIDE=3.2' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_VK_WINSYS=x11' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_VK_WSI_DEBUG=sw' >> /etc/profile.d/termux_env.sh
                fi
                
                # Flush broken shader caches to heal bugged environments
                rm -rf /home/*/.cache/mesa_shader_cache /root/.cache/mesa_shader_cache 2>/dev/null || true
                if ! grep -q 'XDG_RUNTIME_DIR' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export XDG_RUNTIME_DIR=/tmp/runtime-$USER' >> /etc/profile.d/termux_env.sh
                    echo 'mkdir -p $XDG_RUNTIME_DIR' >> /etc/profile.d/termux_env.sh
                    echo 'chmod 700 $XDG_RUNTIME_DIR' >> /etc/profile.d/termux_env.sh
                fi

                # Create helper runner script for Zink
                cat << 'RUNEOF' > /usr/local/bin/zink-run
#!/usr/bin/env bash
export GALLIUM_DRIVER=zink
export MESA_LOADER_DRIVER_OVERRIDE=zink
export ZINK_DESCRIPTORS=lazy
exec "$@"
RUNEOF
                chmod +x /usr/local/bin/zink-run
            "
        else
            log_info "Configuring environment for Freedreno..."
            $DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c "
                if ! grep -q 'GALLIUM_DRIVER' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export GALLIUM_DRIVER=freedreno' >> /etc/profile.d/termux_env.sh
                else
                    sed -i 's/GALLIUM_DRIVER=.*/GALLIUM_DRIVER=freedreno/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
                fi
                if ! grep -q 'MESA_LOADER_DRIVER_OVERRIDE' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export MESA_LOADER_DRIVER_OVERRIDE=freedreno' >> /etc/profile.d/termux_env.sh
                else
                    sed -i 's/MESA_LOADER_DRIVER_OVERRIDE=.*/MESA_LOADER_DRIVER_OVERRIDE=freedreno/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
                fi
                sed -i '/export LIBGL_ALWAYS_SOFTWARE/d' /etc/profile.d/termux_env.sh 2>/dev/null || true
            "
        fi
        ;;
    3)
        log_info "Configuring environment for VirGL (Mali/PowerVR/Exynos/Tensor)..."
        $DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c "
            if ! grep -q 'GALLIUM_DRIVER' /etc/profile.d/termux_env.sh 2>/dev/null; then
                echo 'export GALLIUM_DRIVER=virpipe' >> /etc/profile.d/termux_env.sh
            else
                sed -i 's/GALLIUM_DRIVER=.*/GALLIUM_DRIVER=virpipe/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
            fi
            if ! grep -q 'MESA_LOADER_DRIVER_OVERRIDE' /etc/profile.d/termux_env.sh 2>/dev/null; then
                echo 'export MESA_LOADER_DRIVER_OVERRIDE=virgl' >> /etc/profile.d/termux_env.sh
            else
                sed -i 's/MESA_LOADER_DRIVER_OVERRIDE=.*/MESA_LOADER_DRIVER_OVERRIDE=virgl/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
            fi
            sed -i '/export LIBGL_ALWAYS_SOFTWARE/d' /etc/profile.d/termux_env.sh 2>/dev/null || true

            cat << 'RUNEOF' > /usr/local/bin/virgl-run
#!/usr/bin/env bash
export GALLIUM_DRIVER=virpipe
export MESA_LOADER_DRIVER_OVERRIDE=virgl
exec "$@"
RUNEOF
            chmod +x /usr/local/bin/virgl-run
        "
        ;;
    4)
        log_info "Configuring environment for LLVMpipe (Software Rendering)..."
        $DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c "
            if ! grep -q 'GALLIUM_DRIVER' /etc/profile.d/termux_env.sh 2>/dev/null; then
                echo 'export GALLIUM_DRIVER=llvmpipe' >> /etc/profile.d/termux_env.sh
            else
                sed -i 's/GALLIUM_DRIVER=.*/GALLIUM_DRIVER=llvmpipe/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
            fi
            if ! grep -q 'MESA_LOADER_DRIVER_OVERRIDE' /etc/profile.d/termux_env.sh 2>/dev/null; then
                echo 'export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe' >> /etc/profile.d/termux_env.sh
            else
                sed -i 's/MESA_LOADER_DRIVER_OVERRIDE=.*/MESA_LOADER_DRIVER_OVERRIDE=llvmpipe/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
            fi
            if ! grep -q 'LIBGL_ALWAYS_SOFTWARE' /etc/profile.d/termux_env.sh 2>/dev/null; then
                echo 'export LIBGL_ALWAYS_SOFTWARE=1' >> /etc/profile.d/termux_env.sh
            fi
        "
        ;;
    5)
        log_info "Configuring GL4ES Standalone (OpenGL to OpenGLES translation engine)..."
        $DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c '
            DISTRO_NAME="$1"
            DO_COMPILE="$2"

            sed -i "/export GALLIUM_DRIVER/d;/export MESA_LOADER_DRIVER_OVERRIDE/d;/export LIBGL_ALWAYS_SOFTWARE/d;/export LIBGL_ES/d;/export LIBGL_GL/d;/export LIBGL_NOBANNER/d" /etc/profile.d/termux_env.sh 2>/dev/null || true
            
            # 1. Ensure core dependencies and GLES libraries are installed
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update >/dev/null 2>&1
                apt-get install -y libgl1-mesa-dri libgles2 libegl1 libgl1 xfce4 xfwm4 libdisplay-info-dev >/dev/null 2>&1 || true
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y mesa-libGL mesa-libEGL mesa-libGLES mesa-dri-drivers @xfce-desktop-environment libdisplay-info >/dev/null 2>&1 || true
            elif command -v pacman >/dev/null 2>&1; then
                pacman -Sy --noconfirm mesa libglvnd xfce4 xfwm4 libdisplay-info >/dev/null 2>&1 || true
            fi

            # 2. Install Mesa for Android Container
            RAW_ARCH=$(uname -m)
            case "$RAW_ARCH" in
                aarch64|arm64)
                    ARCH_SUFFIX="arm64"
                    ARCH_ARCH="arm64"
                    ;;
                armv7*|armv8l|armhf|arm)
                    ARCH_SUFFIX="armhf"
                    ARCH_ARCH="arm"
                    ;;
                x86_64|amd64)
                    ARCH_SUFFIX="x86_64"
                    ARCH_ARCH="x86_64"
                    ;;
                i*86|x86)
                    ARCH_SUFFIX="x86"
                    ARCH_ARCH="x86"
                    ;;
                *)
                    ARCH_SUFFIX="$RAW_ARCH"
                    ARCH_ARCH="$RAW_ARCH"
                    ;;
            esac

            IS_UBUNTU=0
            if [ -f /etc/os-release ] && grep -qi "ubuntu" /etc/os-release; then
                IS_UBUNTU=1
            fi
            
            if [ "$DISTRO_NAME" = "debian" ] && [ "$IS_UBUNTU" -eq 0 ] && [ "$ARCH_SUFFIX" = "arm64" ]; then
                echo "Downloading Mesa for Android container (Debian bundle for $ARCH_SUFFIX)..."
                cd /tmp
                wget -q https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip || curl -sL -o mesa-debs-trixie.zip https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip
                if [ -f "mesa-debs-trixie.zip" ] && unzip -t mesa-debs-trixie.zip >/dev/null 2>&1; then
                    echo "Installing container Mesa drivers..."
                    unzip -q mesa-debs-trixie.zip
                    apt-get install -y --no-install-recommends ./mesa_debs/*.deb || true
                    rm -rf mesa-debs-trixie.zip mesa_debs
                fi
            else
                echo "Auto-detected architecture: $RAW_ARCH ($ARCH_SUFFIX)"
                if [ "$DISTRO_NAME" = "fedora" ]; then
                    FEDORA_VER=$(grep -oP "(?<=^VERSION_ID=).+" /etc/os-release | tr -d \")
                    LFDEVS_PATTERN="fedora_${FEDORA_VER}_${ARCH_SUFFIX}\.tar\.gz"
                elif [ "$DISTRO_NAME" = "archlinux" ]; then
                    LFDEVS_PATTERN="archlinux_${ARCH_ARCH}\.tar"
                elif [ "$IS_UBUNTU" -eq 1 ] || grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
                    UBUNTU_CODENAME=$(grep -oP "(?<=^VERSION_CODENAME=).+" /etc/os-release | tr -d \")
                    [ -z "$UBUNTU_CODENAME" ] && UBUNTU_CODENAME=$(grep -oP "(?<=^UBUNTU_CODENAME=).+" /etc/os-release | tr -d \")
                    [ -z "$UBUNTU_CODENAME" ] && UBUNTU_CODENAME="noble"
                    LFDEVS_PATTERN="ubuntu_${UBUNTU_CODENAME}_${ARCH_SUFFIX}\.tar\.gz"
                else
                    LFDEVS_PATTERN="debian_.*_${ARCH_SUFFIX}\.tar\.gz"
                fi
                LATEST_URL=$(curl -sI https://github.com/lfdevs/mesa-for-android-container/releases/latest | grep -i "^location:" | sed "s/\r//" | awk "{print \$2}")
                TAG=$(echo "$LATEST_URL" | awk -F "/" "{print \$NF}")
                DOWNLOAD_URL=$(curl -sL "https://github.com/lfdevs/mesa-for-android-container/releases/expanded_assets/$TAG" | grep -oE "href=\"[^\"]*$LFDEVS_PATTERN\"" | head -n 1 | cut -d "\"" -f 2)
                if [ -z "$DOWNLOAD_URL" ]; then
                    DOWNLOAD_URL=$(curl -sL "https://github.com/lfdevs/mesa-for-android-container/releases/expanded_assets/$TAG" | grep -oE "href=\"[^\"]*${ARCH_SUFFIX}\.tar\.gz\"" | head -n 1 | cut -d "\"" -f 2)
                fi
                if [ -n "$DOWNLOAD_URL" ]; then
                    DOWNLOAD_URL="https://github.com$DOWNLOAD_URL"
                    cd /tmp
                    wget -q -O mesa-container.tar.gz "$DOWNLOAD_URL" || curl -sL "$DOWNLOAD_URL" -o mesa-container.tar.gz
                    if [ "$DISTRO_NAME" = "archlinux" ]; then
                        mkdir -p /tmp/mesa-container
                        tar -xf mesa-container.tar.gz -C /tmp/mesa-container/ 2>/dev/null || tar -xf mesa-container.tar -C /tmp/mesa-container/ 2>/dev/null
                        pacman -U --noconfirm --overwrite "*" /tmp/mesa-container/*.pkg.tar.xz >/dev/null 2>&1 || true
                        rm -rf /tmp/mesa-container
                    else
                        tar -zxf mesa-container.tar.gz -C / >/dev/null 2>&1 || true
                        ldconfig 2>/dev/null || true
                    fi
                    rm -f mesa-container.tar.gz mesa-container.tar
                fi
            fi

            # 3. Compile or configure GL4ES
            if [ "$DO_COMPILE" = "yes" ]; then
                echo "Installing build tools and compiling GL4ES from source (ptitSeb/gl4es)..."
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get install -y build-essential git cmake gcc g++ make libx11-dev libxext-dev libegl1-mesa-dev libgles2-mesa-dev libgl1-mesa-dev >/dev/null 2>&1 || true
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y gcc gcc-c++ make git cmake libX11-devel libXext-devel mesa-libEGL-devel mesa-libGLES-devel mesa-libGL-devel >/dev/null 2>&1 || true
                elif command -v pacman >/dev/null 2>&1; then
                    pacman -Sy --noconfirm base-devel git cmake libx11 libxext mesa >/dev/null 2>&1 || true
                fi

                cd /tmp
                rm -rf gl4es
                if git clone --depth 1 https://github.com/ptitSeb/gl4es.git; then
                    cd gl4es
                    mkdir -p build && cd build
                    cmake .. -DCMAKE_BUILD_TYPE=Release -DDEFAULT_ES=2 -DNOX11=OFF -DNOEGL=OFF >/dev/null 2>&1 || cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1
                    make -j$(nproc 2>/dev/null || echo 2) >/dev/null 2>&1
                    mkdir -p /usr/local/lib/gl4es /usr/local/lib
                    cp -f lib/libGL.so.1 /usr/local/lib/gl4es/ 2>/dev/null || true
                    cp -f lib/libGL.so.1 /usr/local/lib/ 2>/dev/null || true
                    ln -sf /usr/local/lib/gl4es/libGL.so.1 /usr/local/lib/gl4es/libGL.so 2>/dev/null || true
                    ln -sf /usr/local/lib/libGL.so.1 /usr/local/lib/libGL.so 2>/dev/null || true
                    ldconfig 2>/dev/null || true
                    cd /tmp && rm -rf gl4es
                fi
            else
                echo "Skipping GL4ES source compilation. Using existing/system OpenGL libraries..."
                mkdir -p /usr/local/lib/gl4es /usr/local/lib
                if [ -f /usr/local/lib/gl4es/libGL.so.1 ]; then
                    cp -f /usr/local/lib/gl4es/libGL.so.1 /usr/local/lib/ 2>/dev/null || true
                    ln -sf /usr/local/lib/libGL.so.1 /usr/local/lib/libGL.so 2>/dev/null || true
                fi
            fi

            # 4. Helper runner script gl4es-run
            cat << "RUNEOF" > /usr/local/bin/gl4es-run
#!/usr/bin/env bash
export LIBGL_ES=2
export LIBGL_GL=21
export LIBGL_NOBANNER=1
export LD_LIBRARY_PATH=/usr/local/lib/gl4es:/usr/local/lib:$LD_LIBRARY_PATH
exec "$@"
RUNEOF
            chmod +x /usr/local/bin/gl4es-run

            # 5. Export GL4ES Standalone translation parameters
            cat << "ENVEOF" >> /etc/profile.d/termux_env.sh
# GL4ES Standalone Hardware Translation
export LIBGL_ES=2
export LIBGL_GL=21
export LIBGL_NOBANNER=1
export LD_LIBRARY_PATH=/usr/local/lib/gl4es:/usr/local/lib:$LD_LIBRARY_PATH
ENVEOF
        ' -- "$SELECTED_DISTRO" "$DO_COMPILE_GL4ES"
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${RESET}"
        exit 1
        ;;
esac

case "$driver_choice" in
    1) autochroot_save_renderer "$SELECTED_DISTRO" zink ;;
    2) autochroot_save_renderer "$SELECTED_DISTRO" freedreno ;;
    3) autochroot_save_renderer "$SELECTED_DISTRO" virgl ;;
    4) autochroot_save_renderer "$SELECTED_DISTRO" llvmpipe ;;
    5) autochroot_save_renderer "$SELECTED_DISTRO" gl4es ;;
esac

log_success "Graphics drivers successfully updated for $SELECTED_DISTRO!"
log_info "You may now run ./start-chroot.sh to enjoy your hardware-accelerated desktop."

log_success "Graphics optimization complete!"

print_divider
print_centered "${YELLOW}${BOLD}Verifying Hardware Acceleration...${RESET}"

# Start a headless, invisible test display server
export DISPLAY=:99
if command -v termux-x11 &> /dev/null; then
    termux-x11 :99 -ac >/dev/null 2>&1 &
    TERMUX_X11_PID=$!
    sleep 2
fi

# Run glxinfo inside the container to test OpenGL/Vulkan acceleration
$DISTRO_CMD login $SELECTED_DISTRO --user root --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix -- bash -c '
    DRIVER_CHOICE="$1"
    if command -v glxinfo >/dev/null 2>&1; then
        export DISPLAY=:99
        TEST_CMD="glxinfo -B"
        if [ "$DRIVER_CHOICE" = "1" ]; then
            TEST_CMD="GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink glxinfo -B"
        elif [ "$DRIVER_CHOICE" = "2" ]; then
            TEST_CMD="GALLIUM_DRIVER=freedreno MESA_LOADER_DRIVER_OVERRIDE=freedreno glxinfo -B"
        elif [ "$DRIVER_CHOICE" = "3" ]; then
            TEST_CMD="GALLIUM_DRIVER=virpipe glxinfo -B"
        elif [ "$DRIVER_CHOICE" = "5" ]; then
            TEST_CMD="LD_LIBRARY_PATH=/usr/local/lib/gl4es:/usr/local/lib:$LD_LIBRARY_PATH LIBGL_ES=2 LIBGL_GL=21 LIBGL_NOBANNER=1 glxinfo -B"
        fi
        
        GL_OUTPUT=$(eval "$TEST_CMD" 2>/dev/null || true)
        if echo "$GL_OUTPUT" | grep -qiE "renderer string:.*(zink|freedreno|virgl|turnip|adreno|mali|gl4es|gles|opengl es)"; then
            DRIVER=$(echo "$GL_OUTPUT" | grep "OpenGL renderer string" | cut -d ":" -f 2 | sed "s/^[[:space:]]*//")
            echo -e "\n\033[38;5;46m\033[1m[SUCCESS]\033[0m \033[38;5;231mHardware acceleration VERIFIED! Active Driver: \033[38;5;51m$DRIVER\033[0m\n"
        elif echo "$GL_OUTPUT" | grep -q "Accelerated: yes"; then
            DRIVER=$(echo "$GL_OUTPUT" | grep "OpenGL renderer string" | cut -d ":" -f 2 | sed "s/^[[:space:]]*//")
            echo -e "\n\033[38;5;46m\033[1m[SUCCESS]\033[0m \033[38;5;231mHardware acceleration VERIFIED! Active Driver: \033[38;5;51m$DRIVER\033[0m\n"
        else
            echo -e "\n\033[31m[ERROR] OpenGL failed to accelerate. Your device may require different settings or VirGL.\033[0m\n"
            echo "$GL_OUTPUT" | grep "OpenGL renderer string" || true
        fi
    else
        echo -e "\n\033[38;5;226m[WARNING] glxinfo not installed. Skipping automatic verification.\033[0m\n"
    fi
' -- "$driver_choice"

# Shut down the test display server
if [ -n "$TERMUX_X11_PID" ]; then
    kill $TERMUX_X11_PID 2>/dev/null || true
    pkill -f 'termux-x11 :99' 2>/dev/null || true
fi
