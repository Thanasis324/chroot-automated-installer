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

BOLD="\033[1m"
GREEN="\033[38;5;46m"
CYAN="\033[38;5;51m"
YELLOW="\033[38;5;226m"
WHITE="\033[38;5;231m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}[${DISTRO_NAME^^} SETUP] Initializing environment configuration...${RESET}"

# --- 1. Fix Permissions on Hardware Device Nodes ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Adjusting permissions on Android hardware device nodes...${RESET}"
chmod 666 /dev/kgsl-3d0 2>/dev/null || true
chmod 666 /dev/dri/* 2>/dev/null || true
chmod 666 /dev/mali* 2>/dev/null || true
chmod 666 /dev/ion 2>/dev/null || true
chmod 666 /dev/dma_heap/* 2>/dev/null || true

# --- 2. Package Installation ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Updating package repositories and installing dependencies...${RESET}"

if [ "$DISTRO_NAME" = "fedora" ]; then
    dnf update -y
    dnf install -y @xfce-desktop-environment || true
    dnf install -y sudo dbus dbus-x11 dconf pulseaudio-utils alsa-utils curl wget git figlet pciutils lshw florence arc-theme papirus-icon-theme google-noto-sans-fonts vulkan-loader mesa-vulkan-drivers mesa-dri-drivers mesa-libGL glx-utils vulkan-tools libdisplay-info || true
elif [ "$DISTRO_NAME" = "archlinux" ]; then
    pacman -Syu --noconfirm
    pacman -S --noconfirm sudo dbus dbus-glib pulseaudio alsa-utils curl wget git figlet pciutils lshw xfce4 xfce4-goodies xfce4-terminal onboard arc-gtk-theme papirus-icon-theme noto-fonts vulkan-freedreno vulkan-swrast vulkan-mesa-layers mesa-utils vulkan-tools libdisplay-info || true
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get upgrade -y
    apt-get install -y --no-install-recommends \
        sudo dbus dbus-x11 dconf-cli pulseaudio-utils alsa-utils curl wget git ca-certificates gnupg figlet pciutils lshw xfce4 xfce4-goodies xfce4-terminal onboard arc-theme papirus-icon-theme fonts-noto fonts-dejavu libvulkan1 mesa-vulkan-drivers libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libgl1 mesa-utils vulkan-tools virglrenderer libvirglrenderer1 libdisplay-info1 || apt-get install -y sudo dbus dbus-x11 dconf-cli pulseaudio-utils xfce4 xfce4-goodies onboard mesa-utils mesa-vulkan-drivers libgl1-mesa-dri libdisplay-info1
fi

# --- 2.5. Initialize D-Bus Machine ID ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Initializing D-Bus machine ID & system directories...${RESET}"
mkdir -p /run/dbus /var/run/dbus
dbus-uuidgen --ensure 2>/dev/null || true

# --- 3. Group Creation, User Setup & Android Hardware GID Mapping ---
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
usermod -aG sudo,video,audio,render,input,aid_graphics,graphics "$USERNAME" 2>/dev/null || true

# Grant Sudo privileges without password prompt for touch convenience
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL:ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 0440 "/etc/sudoers.d/$USERNAME"

# --- 4. Audio & X11 Environment Configuration ---
echo -e "${CYAN}[${DISTRO_NAME^^} SETUP] Configuring Audio (PulseAudio TCP) & X11 Display...${RESET}"

cat << 'EOF' > /etc/profile.d/termux_env.sh
# Termux X11 & PulseAudio Environment Variables
export DISPLAY=:0
export PULSE_SERVER=tcp:127.0.0.1:4713
export GDK_SCALE=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export MOZ_ENABLE_WAYLAND=0

export XDG_RUNTIME_DIR=/tmp/runtime-$USER
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

export MESA_VK_WSI_DEBUG=sw
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
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
export GALLIUM_DRIVER=zink
export MESA_LOADER_DRIVER_OVERRIDE=zink
export MESA_GL_VERSION_OVERRIDE=4.6
export MESA_GLES_VERSION_OVERRIDE=3.2
export TU_DEBUG=kgsl,noconform,sysmem,nolrz
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

# Create Autostart script to forcefully disable XFCE compositor on login to protect Zink
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

    # Create first-run initialization script for Onboard settings (dconf/gsettings requires active DBus session)
    cat << 'EOF' > "$USER_HOME/.config/autostart/onboard-settings.desktop"
[Desktop Entry]
Type=Application
Name=Onboard Settings Initializer
Comment=Applies Onboard dark theme, auto-show, and floating icon on first boot
Exec=bash -c "gsettings set org.onboard theme 'Nightshade' && gsettings set org.onboard.auto-show enabled true && gsettings set org.onboard.window docking-enabled true && gsettings set org.onboard.window docking-edge 'bottom' && gsettings set org.onboard.icon-palette in-use true && rm -f ~/.config/autostart/onboard-settings.desktop"
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
    min-width: 16px;
    min-height: 16px;
    border-radius: 8px;
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

echo -e "${GREEN}${BOLD}[${DISTRO_NAME^^} SETUP] Internal setup complete!${RESET}"
