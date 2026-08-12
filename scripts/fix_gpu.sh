#!/usr/bin/env bash
# ==============================================================================
# GPU Acceleration Test & Automatic Fallback Script
# Run this from Termux (outside the chroot) to automatically test and configure
# the optimal graphics driver for your device.
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[38;5;46m"
YELLOW="\033[38;5;226m"
CYAN="\033[38;5;51m"
WHITE="\033[38;5;231m"
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

# If no distro was passed as an argument, auto-detect installed distros
if [ -z "$SELECTED_DISTRO" ]; then
    PREFIX_VAR="${PREFIX:-/data/data/com.termux/files/usr}/var/lib"
    INSTALLED_DISTROS=()
    for d in debian fedora archlinux; do
        if [ -d "$PREFIX_VAR/chroot-distro/containers/$d" ] || [ -d "$PREFIX_VAR/chroot-distro/installed-rootfs/$d" ] || [ -d "/data/local/chroot-distro/$d" ]; then
            INSTALLED_DISTROS+=("$d")
        fi
    done
    
    if [ ${#INSTALLED_DISTROS[@]} -eq 0 ]; then
        echo -e "${YELLOW}Warning: Could not automatically detect installed distros.${RESET}"
        echo ""
        print_divider
        print_centered "${CYAN}${BOLD}Please select which environment to fix, or run the installer:${RESET}"
        print_centered "  ${WHITE}1)${RESET} fedora                                       "
        print_centered "  ${WHITE}2)${RESET} debian                                       "
        print_centered "  ${WHITE}3)${RESET} archlinux                                    "
        print_centered "  ${WHITE}4)${RESET} I haven't run setup.sh yet (Run installer) "
        print_divider
        read -p "Select a number (1-4): " fallback_choice
        
        case "$fallback_choice" in
            1) SELECTED_DISTRO="fedora" ;;
            2) SELECTED_DISTRO="debian" ;;
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

echo -e "${CYAN}${BOLD}Please select the graphics driver backend you want to apply to ${SELECTED_DISTRO}:${RESET}"
echo "  1. Zink (Vulkan to OpenGL) - Best for Adreno 6xx, 7xx, 8xx"
echo "  2. Freedreno (Native OpenGL) - Best for older Adrenos or if Zink fails"
echo "  3. VirGL - Required for Mali, PowerVR, Exynos, Tensor chipsets"
echo "  4. LLVMpipe - Software Rendering (Slowest, maximum compatibility)"
read -p "Select driver (1-4): " driver_choice

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
            elif command -v apt-get >/dev/null 2>&1; then
                echo "Running apt-get install..."
                apt-get install -y libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 xfce4 xfwm4 git cmake gcc g++ make libx11-dev libxext-dev libegl1-mesa-dev libdisplay-info-dev >/dev/null 2>&1 || true
            elif command -v pacman >/dev/null 2>&1; then
                echo "Running pacman install..."
                pacman -Sy --noconfirm vulkan-freedreno vulkan-swrast vulkan-mesa-layers vulkan-icd-loader xfce4 xfwm4 libdisplay-info git cmake gcc make libx11 libxext mesa >/dev/null 2>&1 || true
            fi
            
            if [ ! -f /usr/local/lib/libGL.so.1 ]; then
                echo "Compiling gl4es for native OpenGL wrapper support..."
                cd /tmp
                rm -rf gl4es
                git clone https://github.com/ptitSeb/gl4es.git >/dev/null 2>&1
                cd gl4es
                mkdir -p build && cd build
                cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1
                make -j$(nproc) >/dev/null 2>&1
                mkdir -p /usr/local/lib
                cp lib/libGL.so.1 /usr/local/lib/
                ln -sf /usr/local/lib/libGL.so.1 /usr/local/lib/libGL.so
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
            
            if [ "$1" = "fedora" ]; then LFDEVS_PATTERN="fedora_.*_arm64\.tar\.gz"; elif [ "$1" = "archlinux" ]; then LFDEVS_PATTERN="archlinux_arm64\.tar"; else LFDEVS_PATTERN="debian_.*_arm64\.tar\.gz"; fi
            DOWNLOAD_URL=$(curl -s https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest | grep -o "\"browser_download_url\": \"[^\"]*\"" | cut -d"\"" -f4 | grep -iE "$LFDEVS_PATTERN" | head -n 1)
            
            if [ -n "$DOWNLOAD_URL" ]; then
                cd /tmp
                # Remove old lfdevs patches if they exist (clean update)
                rm -rf /usr/lib64/libvulkan_freedreno.so /usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so 2>/dev/null || true

                wget -q -O mesa-turnip.tar.gz "$DOWNLOAD_URL" || curl -sL "$DOWNLOAD_URL" -o mesa-turnip.tar.gz
                if [ "$1" = "archlinux" ]; then
                    mkdir -p /tmp/mesa-turnip
                    tar -xf mesa-turnip.tar.gz -C /tmp/mesa-turnip/ 2>/dev/null || tar -xf mesa-turnip.tar -C /tmp/mesa-turnip/ 2>/dev/null
                    pacman -U --noconfirm /tmp/mesa-turnip/*.pkg.tar.xz >/dev/null 2>&1
                    rm -rf /tmp/mesa-turnip
                else
                    tar -zxf mesa-turnip.tar.gz -C / >/dev/null 2>&1
                    ldconfig 2>/dev/null || true
                fi
                rm -f mesa-turnip.tar.gz mesa-turnip.tar
            else
                echo "[ERROR] Failed to fetch lfdevs download URL! You might be rate-limited by GitHub API."
                echo "Skipping driver download, but dependencies have been repaired."
            fi
        ' -- "$SELECTED_DISTRO" "$driver_choice"
        
        if [ "$driver_choice" == "1" ]; then
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
                    echo 'export TU_DEBUG=kgsl,noconform,nolrz' >> /etc/profile.d/termux_env.sh
                else
                    sed -i 's/TU_DEBUG=.*/TU_DEBUG=kgsl,noconform,nolrz/g' /etc/profile.d/termux_env.sh 2>/dev/null || true
                fi
                if ! grep -q 'ZINK_DESCRIPTORS=lazy' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export ZINK_DESCRIPTORS=lazy' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_GL_VERSION_OVERRIDE=4.6' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_GLES_VERSION_OVERRIDE=3.2' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_VK_WINSYS=x11' >> /etc/profile.d/termux_env.sh
                    echo 'export MESA_VK_WSI_DEBUG=sw' >> /etc/profile.d/termux_env.sh
                    echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >> /etc/profile.d/termux_env.sh
                fi
                if ! grep -q 'XDG_RUNTIME_DIR' /etc/profile.d/termux_env.sh 2>/dev/null; then
                    echo 'export XDG_RUNTIME_DIR=/tmp/runtime-$USER' >> /etc/profile.d/termux_env.sh
                    echo 'mkdir -p $XDG_RUNTIME_DIR' >> /etc/profile.d/termux_env.sh
                    echo 'chmod 700 $XDG_RUNTIME_DIR' >> /etc/profile.d/termux_env.sh
                fi

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
    *)
        echo -e "${RED}Invalid choice. Exiting.${RESET}"
        exit 1
        ;;
esac

log_success "Graphics drivers successfully updated for $SELECTED_DISTRO!"
log_info "You may now run ./start-chroot.sh to enjoy your hardware-accelerated desktop."

log_success "Graphics optimization complete! You can now start your desktop."
