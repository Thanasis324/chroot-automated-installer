#!/usr/bin/env bash
# ==============================================================================
# Internal Debian Chroot Setup Script
# Executed inside Debian rootfs during installation phase
# Configures User, Groups, Audio, X11, Touch DE & Automatic GPU Drivers
# ==============================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

USERNAME="${1:-user}"
PASSWORD="${2:-password}"
IS_ADRENO="${3:-false}"
ADRENO_SERIES="${4:-A8XX}"
DISTRO_NAME="${5:-debian}"
SUDO_CHOICE="${6:-yes}"

SETUP_MODE="${SETUP_MODE:-true}"
RUN_PKGS="yes"
RUN_ENV="yes"
RUN_USER="yes"

BOLD="\033[1m"
GREEN="\033[38;5;46m"
CYAN="\033[38;5;51m"
YELLOW="\033[38;5;226m"
WHITE="\033[38;5;231m"
RESET="\033[0m"

if [ "$SETUP_MODE" == "false" ]; then
    echo -e "\n${YELLOW}${BOLD}=== Interactive Repair Mode ===${RESET}"
    
    read -rp "$(echo -e "${CYAN}1. Reinstall and update all core packages? [Y/n]: ${RESET}")" PKG_PROMPT
    [[ "${PKG_PROMPT,,}" == "n"* ]] && RUN_PKGS="no"
    
    read -rp "$(echo -e "${CYAN}2. Rebuild X11 and Audio environment configs? [Y/n]: ${RESET}")" ENV_PROMPT
    [[ "${ENV_PROMPT,,}" == "n"* ]] && RUN_ENV="no"
    
    read -rp "$(echo -e "${CYAN}3. Reset user passwords and permissions? [Y/n]: ${RESET}")" USER_PROMPT
    [[ "${USER_PROMPT,,}" == "n"* ]] && RUN_USER="no"
    
    if [ "$RUN_USER" == "yes" ]; then
        echo ""
        read -rp "$(echo -e "${CYAN}Please enter the username to configure (default: ${USERNAME}): ${RESET}")" PROMPT_USER
        USERNAME="${PROMPT_USER:-$USERNAME}"
        
        read -rsp "$(echo -e "${CYAN}Enter new password for $USERNAME: ${RESET}")" PASSWORD
        echo ""
        read -rp "$(echo -e "${CYAN}Enable passwordless sudo? [y/N]: ${RESET}")" SUDO_PROMPT
        case "${SUDO_PROMPT,,}" in
            y|yes) SUDO_CHOICE="yes" ;;
            *) SUDO_CHOICE="no" ;;
        esac
    else
        # If user setup is skipped, set default fallbacks so the variables exist
        PASSWORD="password"
        SUDO_CHOICE="no"
    fi
    echo -e "${YELLOW}===============================${RESET}\n"
fi

echo -e "${CYAN}${BOLD}[${DISTRO_NAME^^} SETUP] Initializing environment configuration...${RESET}"

# --- 1. Fix Permissions on Hardware Device Nodes ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Adjusting permissions on Android hardware device nodes...${RESET}"
chmod 666 /dev/kgsl-3d0 2>/dev/null || true
chmod 666 /dev/dri/* 2>/dev/null || true
chmod 666 /dev/mali* 2>/dev/null || true
chmod 666 /dev/ion 2>/dev/null || true
chmod 666 /dev/dma_heap/* 2>/dev/null || true

# --- 2. Package Installation ---
if [ "${RUN_PKGS:-yes}" = "yes" ]; then
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Updating package repositories and installing dependencies...${RESET}"

if [ "$DISTRO_NAME" = "fedora" ]; then
    dnf update -y
    dnf install -y @xfce-desktop-environment || true
    dnf install -y sudo dbus dbus-x11 dconf pulseaudio-utils alsa-utils curl wget git figlet pciutils lshw florence arc-theme papirus-icon-theme google-noto-sans-fonts vulkan-loader mesa-vulkan-drivers mesa-dri-drivers mesa-libGL glx-utils vulkan-tools libdisplay-info polkit-gnome || true
elif [ "$DISTRO_NAME" = "archlinux" ]; then
    # Disable pacman sandbox which crashes in Android chroots (Landlock/ALPM user errors)
    if grep -q "^#DisableSandbox" /etc/pacman.conf; then
        sed -i 's/^#DisableSandbox/DisableSandbox/g' /etc/pacman.conf
    elif ! grep -q "^DisableSandbox" /etc/pacman.conf; then
        sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
    fi
    
    # Disable CheckSpace as it fails to determine mount points inside chroot
    sed -i 's/^CheckSpace/#CheckSpace/g' /etc/pacman.conf

    # Initialize pacman keyring for Arch Linux ARM
    pacman-key --init
    pacman-key --populate archlinuxarm || pacman-key --populate archlinux
    pacman -Syu --noconfirm

    ARCH_DEPS=(sudo dbus dbus-glib pulseaudio alsa-utils curl wget git figlet pciutils lshw xfce4 xfce4-goodies xfce4-terminal onboard arc-gtk-theme papirus-icon-theme noto-fonts mesa vulkan-icd-loader vulkan-freedreno vulkan-swrast vulkan-mesa-layers mesa-utils vulkan-tools libdisplay-info chromium polkit-gnome)
    
    # Bulk install first for speed, fallback to sequential if a package is invalid
    if ! pacman -S --noconfirm "${ARCH_DEPS[@]}"; then
        echo -e "${YELLOW}Bulk installation failed. Retrying packages sequentially...${RESET}"
        for dep in "${ARCH_DEPS[@]}"; do
            pacman -S --noconfirm "$dep" || echo -e "${RED}Skipped missing package: $dep${RESET}"
        done
    fi
else
    export DEBIAN_FRONTEND=noninteractive
    
    # Fix any broken package locks from previously interrupted installations
    dpkg --configure -a 2>/dev/null || true
    
    apt-get update -y || true
    apt-get upgrade -y || true

    DEB_DEPS=(sudo dbus dbus-x11 dconf-cli pulseaudio-utils alsa-utils curl wget git ca-certificates gnupg figlet pciutils lshw xfce4 xfce4-goodies xfce4-terminal onboard arc-theme papirus-icon-theme fonts-noto fonts-dejavu vulkan-tools virgl-server libvirglrenderer1 firefox-esr libdisplay-info-dev mesa-utils)
    
    echo -e "${YELLOW}Installing core system packages...${RESET}"
    if ! apt-get install -y --no-install-recommends "${DEB_DEPS[@]}"; then
        echo -e "${YELLOW}Bulk core installation failed. Retrying sequentially...${RESET}"
        for dep in "${DEB_DEPS[@]}"; do
            apt-get install -y --no-install-recommends "$dep" || echo -e "${RED}Skipped missing package: $dep${RESET}"
        done
    fi

    echo -e "${YELLOW}Acquiring bleeding-edge Mesa drivers...${RESET}"
    cd /tmp
    
    # 1. Try downloading from GitHub if not already present
    if [ ! -f "mesa-debs-trixie.zip" ]; then
        wget -q https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip || curl -sL -o mesa-debs-trixie.zip https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip
    fi
    
    # 2. Check if ZIP is valid
    if [ -f "mesa-debs-trixie.zip" ] && unzip -t mesa-debs-trixie.zip >/dev/null 2>&1; then
        echo -e "${GREEN}Valid Mesa zip found. Extracting...${RESET}"
        unzip -q mesa-debs-trixie.zip
        echo -e "${YELLOW}Installing Mesa packages...${RESET}"
        apt-get install -y --no-install-recommends ./mesa_debs/*.deb || true
        rm -rf mesa-debs-trixie.zip mesa_debs
    else
        echo -e "${RED}[WARNING] GitHub ZIP failed or invalid. Falling back to direct Freedesktop download...${RESET}"
        rm -f mesa-debs-trixie.zip
        
        # 3. Direct Fallback to GitLab
        mkdir -p /tmp/mesa_debs
        cd /tmp/mesa_debs
        BASE_URL="https://gitlab.freedesktop.org/gfx-ci/ci-deb-repo/-/raw/trixie/dists/trixie/main/binary-arm64"
        PKGS=("libgl1-mesa-dri" "mesa-vulkan-drivers" "libvulkan1" "libglx-mesa0" "libegl-mesa0" "mesa-libgallium" "libgl1" "mesa-utils" "libglapi-mesa" "libgbm1")
        
        curl -sL "$BASE_URL/Packages" > Packages.txt
        for pkg in "${PKGS[@]}"; do
            FILE_PATH=$(awk -v pkg="^Package: $pkg\$" '$0 ~ pkg {found=1} found && /^Filename:/ {print $2; exit}' Packages.txt)
            if [ -n "$FILE_PATH" ]; then
                echo "Downloading $pkg..."
                curl -sL "https://gitlab.freedesktop.org/gfx-ci/ci-deb-repo/-/raw/trixie/$FILE_PATH" -o "$(basename "$FILE_PATH")"
            fi
        done
        
        echo -e "${YELLOW}Installing Mesa packages...${RESET}"
        if ls ./*.deb 1> /dev/null 2>&1; then
            apt-get install -y --no-install-recommends ./*.deb || true
        else
            echo -e "${RED}[CRITICAL] Both GitHub and GitLab downloads failed! Falling back to standard Debian repository...${RESET}"
            apt-get install -y --no-install-recommends libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 libglx-mesa0 libegl-mesa0 libgl1 libglapi-mesa libgbm1 || true
        fi
        
        cd /tmp
        rm -rf mesa_debs
    fi
fi
fi

# --- 2.5. Initialize D-Bus Machine ID ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Initializing D-Bus machine ID & system directories...${RESET}"
mkdir -p /run/dbus /var/run/dbus
dbus-uuidgen --ensure 2>/dev/null || true

# --- 3. Group Creation, User Setup & Android Hardware GID Mapping ---
if [ "${RUN_USER:-yes}" = "yes" ]; then
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Setting up user '$USERNAME' with passwordless sudo & graphics permissions...${RESET}"

# Ensure essential groups exist, including Android AID_GRAPHICS (GID 1003)
groupadd -f sudo
groupadd -f video
groupadd -f audio
groupadd -f render
groupadd -f input
groupadd -g 1003 aid_graphics 2>/dev/null || groupadd -f aid_graphics || true
groupadd -f graphics 2>/dev/null || true

if id "$USERNAME" &>/dev/null; then
    echo -e "${YELLOW}User '$USERNAME' already exists. Updating password...${RESET}"
else
    useradd -m -s /bin/bash "$USERNAME"
fi

echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd

# Add user to hardware and permission groups
usermod -aG sudo,video,audio,render,input,aid_graphics,graphics,aid_input,aid_bluetooth "$USERNAME" 2>/dev/null || true

# Grant Sudo privileges without password prompt for touch convenience (if selected)
if [ "$SUDO_CHOICE" == "yes" ]; then
    mkdir -p /etc/sudoers.d
    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
    chmod 0440 "/etc/sudoers.d/$USERNAME"
fi
fi

# --- 4. Audio & X11 Environment Configuration ---
if [ "${RUN_ENV:-yes}" = "yes" ]; then
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Configuring Audio (PulseAudio TCP) & X11 Display...${RESET}"

cat << 'EOF' > /etc/profile.d/termux_env.sh
# Termux X11 & PulseAudio Environment Variables
export DISPLAY=:0
export PULSE_SERVER=tcp:127.0.0.1:4713
export GDK_SCALE=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export MOZ_ENABLE_WAYLAND=0
export MOZ_USE_XINPUT2=1

export XDG_RUNTIME_DIR=/tmp/runtime-$USER
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

export MESA_VK_WSI_DEBUG=sw
export OPENSSL_armcap=0
export GALLIVM_PERF=nopt

# Disable SDL HIDAPI dualshock/dualsense drivers to force evdev (fake_udev) usage
export SDL_JOYSTICK_HIDAPI_PS4=0
export SDL_JOYSTICK_HIDAPI_PS5=0
EOF

chmod +x /etc/profile.d/termux_env.sh

USER_HOME="/home/$USERNAME"
mkdir -p "$USER_HOME"

if ! grep -q "termux_env.sh" "$USER_HOME/.bashrc" 2>/dev/null; then
    cat << 'EOF' >> "$USER_HOME/.bashrc"

# Termux Desktop Environment Variables
if [ -f /etc/profile.d/termux_env.sh ]; then
    source /etc/profile.d/termux_env.sh
fi
EOF
fi



# Create GPU status and mode switcher helper scripts
cat << 'EOF' > /usr/local/bin/gpu-status
#!/usr/bin/env bash
echo "--- GPU Hardware & Driver Status ---"
echo "Gallium Driver: ${GALLIUM_DRIVER:-default}"
echo "Mesa Loader Override: ${MESA_LOADER_DRIVER_OVERRIDE:-default}"
echo "Vulkan ICD Filenames: ${VK_ICD_FILENAMES:-default}"
echo "TU_DEBUG: ${TU_DEBUG:-none}"
echo ""
echo "--- OpenGL Renderer Info (glxinfo) ---"
if command -v glxinfo &>/dev/null && [ -n "$DISPLAY" ]; then
    glxinfo -B 2>/dev/null || echo "Display server not active or glxinfo query failed."
else
    echo "glxinfo not available or DISPLAY not set."
fi
echo ""
echo "--- Vulkan Info Summary ---"
if command -v vulkaninfo &>/dev/null; then
    vulkaninfo --summary 2>/dev/null || echo "Vulkan summary query returned non-zero (Turnip KGSL waiting for X session)."
else
    echo "vulkaninfo not installed."
fi
EOF
chmod +x /usr/local/bin/gpu-status

cat << 'EOF' > /usr/local/bin/enable-zink
#!/usr/bin/env bash
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json:/etc/vulkan/icd.d/turnip_icd.json
export GALLIUM_DRIVER=zink
export MESA_LOADER_DRIVER_OVERRIDE=zink
export MESA_GL_VERSION_OVERRIDE=4.6
export MESA_GLES_VERSION_OVERRIDE=3.2
export TU_DEBUG=kgsl,noconform,nolrz
export MESA_VK_WINSYS=x11
export MESA_VK_WSI_DEBUG=sw
export ZINK_DESCRIPTORS=lazy
unset LIBGL_ALWAYS_SOFTWARE
echo "Switched to Turnip + Zink GPU hardware acceleration mode."
EOF
chmod +x /usr/local/bin/enable-zink

cat << 'EOF' > /usr/local/bin/enable-freedreno
#!/usr/bin/env bash
unset MESA_LOADER_DRIVER_OVERRIDE
export GALLIUM_DRIVER=freedreno
unset VK_ICD_FILENAMES
echo "Switched to Native Qualcomm Freedreno OpenGL driver mode."
EOF
chmod +x /usr/local/bin/enable-freedreno

cat << 'EOF' > /usr/local/bin/enable-software
#!/usr/bin/env bash
export GALLIUM_DRIVER=llvmpipe
export MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
export LIBGL_ALWAYS_SOFTWARE=1
echo "Switched to LLVMpipe Software Rendering fallback mode."
EOF
chmod +x /usr/local/bin/enable-software

# --- 6. Touch DE Aesthetic Polish & Onboard Keyboard Shortcuts ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Applying touch-friendly XFCE4 aesthetics & Onboard virtual keyboard...${RESET}"

mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$USER_HOME/.config/autostart"
mkdir -p "$USER_HOME/Desktop"

# Configure GTK Theme to Arc-Dark & Papirus-Dark Icons
cat << 'EOF' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 11"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="24"/>
  </property>
</channel>
EOF

# Configure Window Manager Theme to Arc-Dark
cat << 'EOF' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
EOF

# Configure Single-Click for Desktop Icons (Touch friendly)
cat << 'EOF' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="single-click" type="bool" value="true"/>
  </property>
</channel>
EOF

# Configure Single-Click for Thunar File Manager
cat << 'EOF' > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="thunar" version="1.0">
  <property name="misc-single-click" type="bool" value="true"/>
</channel>
EOF
# --- 5.5 Fake UDEV Daemon for Gamepads ---
cat << 'EOF' > /usr/local/bin/termux-udevd
#!/bin/bash
mkdir -p /run/udev/data
while true; do
    for dev in /sys/class/input/event*; do
        if [ -d "$dev" ]; then
            # Filter for Gamepads to prevent mapping Mice/Keyboards/Headsets
            # Converts everything to lowercase to perfectly handle capitalization
            dev_name=$(cat "$dev/device/name" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            if echo "$dev_name" | grep -iqE "xbox|playstation|dualshock|dualsense|nintendo|controller|gamepad|joy-con|8bitdo|gamesir|ipega|razer|logitech|flydigi|machenike|steam"; then
                major_minor=$(cat "$dev/dev" 2>/dev/null)
                if [ -n "$major_minor" ]; then
                    cat <<UDEV > "/run/udev/data/c$major_minor"
I:1234567
E:ID_INPUT=1
E:ID_INPUT_JOYSTICK=1
UDEV
                    # Force read/write permissions for the gamepad node
                    chmod 666 "/dev/input/$(basename "$dev")" 2>/dev/null || true
                fi
            fi
        fi
    done
    sleep 10
done
EOF
chmod +x /usr/local/bin/termux-udevd

# --- 5.6 Shutdown OS Shortcut ---
cat << 'EOF' > "$USER_HOME/Desktop/Shutdown OS.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Shutdown OS
Comment=Safely shutdown the Linux environment
Exec=bash -c "touch ~/.do_shutdown && xfce4-session-logout --logout"
Icon=system-shutdown
Terminal=false
Categories=System;
EOF
chmod +x "$USER_HOME/Desktop/Shutdown OS.desktop"
cp "$USER_HOME/Desktop/Shutdown OS.desktop" "/usr/share/applications/termux-shutdown.desktop" 2>/dev/null || true

# --- 6. XFCE4 Compositor Disable ---
cat << 'EOF' > "$USER_HOME/.config/autostart/disable-compositor.desktop"
[Desktop Entry]
Type=Application
Exec=xfconf-query -c xfwm4 -p /general/use_compositing -s false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Disable Compositor
Comment=Prevents Zink black screen crashes
EOF

# Autostart virtual keyboard depending on distro availability
if [ "$DISTRO_NAME" = "fedora" ]; then
    mkdir -p "$USER_HOME/.config/autostart"
    cat << 'EOF' > "$USER_HOME/.config/autostart/florence.desktop"
[Desktop Entry]
Type=Application
Exec=florence
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Florence Virtual Keyboard
Comment=Start Florence on login
EOF
else
    # Onboard for Debian and Archlinux
    mkdir -p "$USER_HOME/.config/autostart"
    cat << 'EOF' > "$USER_HOME/.config/autostart/onboard.desktop"
[Desktop Entry]
Type=Application
Exec=onboard
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Onboard Virtual Keyboard
Comment=Start Onboard on login
EOF

    # Configure Onboard settings (docked to bottom, dark theme, auto-show)
    mkdir -p "$USER_HOME/.config/dconf"
    if command -v dconf &>/dev/null || command -v dconf-cli &>/dev/null; then
        # This will be loaded when DBus is active
        cat << 'EOF' > "$USER_HOME/.config/onboard-settings.ini"
[org/onboard]
theme='/usr/share/onboard/themes/Nightshade.theme'
layout='/usr/share/onboard/layouts/Compact.onboard'
xembed-onobard=true

[org/onboard/window]
docking-enabled=true
docking-edge='bottom'
force-to-top=true

[org/onboard/auto-show]
enabled=true
EOF
    fi
fi

if [ "$DISTRO_NAME" != "fedora" ]; then
    # Desktop shortcut for easy access to Onboard Keyboard
    cat << 'EOF' > "$USER_HOME/Desktop/Onboard.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Onscreen Keyboard
Comment=Toggle Onboard virtual touch keyboard
Exec=onboard
Icon=onboard
Terminal=false
Categories=Utility;Accessibility;
EOF
    chmod +x "$USER_HOME/Desktop/Onboard.desktop"

    cat << 'EOF' > "$USER_HOME/.config/autostart/onboard-settings.desktop"
[Desktop Entry]
Type=Application
Name=Onboard Settings Initializer
Comment=Applies Onboard dark theme, auto-show, and floating icon on first boot
Exec=bash -c "sleep 2 && gsettings set org.onboard theme 'Nightshade' && gsettings set org.onboard.auto-show enabled true && gsettings set org.onboard.window docking-enabled true && gsettings set org.onboard.window docking-edge 'bottom' && gsettings set org.onboard.window.landscape dock-expand true && gsettings set org.onboard.window.portrait dock-expand true && gsettings set org.onboard.icon-palette in-use true && rm -f ~/.config/autostart/onboard-settings.desktop"
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF
else
    # Desktop shortcut for Florence Keyboard
    cat << 'EOF' > "$USER_HOME/Desktop/Florence.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Onscreen Keyboard
Comment=Toggle Florence virtual touch keyboard
Exec=florence
Icon=florence
Terminal=false
Categories=Utility;Accessibility;
EOF
    chmod +x "$USER_HOME/Desktop/Florence.desktop"
fi

# Touchscreen GTK3 style adjustments for larger scrollbars & tap target areas
mkdir -p "$USER_HOME/.config/gtk-3.0"
cat << 'EOF' > "$USER_HOME/.config/gtk-3.0/gtk.css"
/* Touch optimized scrollbars and control targets */
scrollbar slider {
    min-width: 20px;
    min-height: 20px;
    border-radius: 10px;
}
button {
    min-height: 36px;
    min-width: 36px;
}
EOF

# Fix permissions on home directory
chown -R "$USERNAME:$USERNAME" "$USER_HOME"

# --- 7. GPU Driver Verification Test ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Verifying GPU Driver stack installation...${RESET}"
if [ -f /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json ] || [ -f /etc/vulkan/icd.d/turnip_icd.json ]; then
    echo -e "${GREEN}${BOLD}[${DISTRO_NAME^^} SETUP] Turnip Vulkan driver ICD configuration verified!${RESET}"
else
    echo -e "${YELLOW}[${DISTRO_NAME^^} SETUP] Base driver suite ready.${RESET}"
fi
fi

echo -e "${GREEN}${BOLD}[${DISTRO_NAME^^} SETUP] Chroot environment configuration completed successfully!${RESET}"
