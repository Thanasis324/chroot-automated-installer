#!/usr/bin/env bash
# ==============================================================================
# Linux X11 & Audio Launcher Script for Termux ($distro)
# NOTE: Run this script directly WITHOUT sudo!
# ==============================================================================

BOLD="\033[1m"
CYAN="\033[38;5;51m"
GREEN="\033[38;5;46m"
YELLOW="\033[38;5;226m"
RESET="\033[0m"

SELECTED_DISTRO="debian"

if command -v chroot-distro &> /dev/null; then
    DISTRO_CMD="chroot-distro"
else
    echo -e "${RED}[ERROR] chroot-distro is not installed. Please run setup.sh first.${RESET}"
    exit 1
fi

# Ensure permissions on hardware GPU device nodes
tsu -c "chmod 666 /dev/kgsl-3d0 /dev/dri/* /dev/mali* /dev/ion /dev/dma_heap/*" 2>/dev/null || \
su -c "chmod 666 /dev/kgsl-3d0 /dev/dri/* /dev/mali* /dev/ion /dev/dma_heap/*" 2>/dev/null || \
chmod 666 /dev/kgsl-3d0 /dev/dri/* /dev/mali* /dev/ion /dev/dma_heap/* 2>/dev/null || true

if [ -n "$1" ]; then
    CHROOT_USER="$1"
elif [ -f "$HOME/.${SELECTED_DISTRO}_user" ]; then
    CHROOT_USER=$(cat "$HOME/.${SELECTED_DISTRO}_user" | tr -d '\r\n')
elif [ -f "$HOME/.debian_user" ]; then
    CHROOT_USER=$(cat "$HOME/.debian_user" | tr -d '\r\n')
else
    CHROOT_USER="user"
fi

if [[ "$CHROOT_USER" =~ ^u0_a[0-9]+$ ]]; then
    CHROOT_USER="user"
fi

echo -e "${CYAN}${BOLD}Halting previous Termux:X11 sessions & output...${RESET}"
HALT_ATTEMPTS=0
MAX_ATTEMPTS=5
while pgrep -f termux-x11 >/dev/null 2>&1 && [ $HALT_ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
    /system/bin/am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
    pkill -9 -f termux-x11 >/dev/null 2>&1 || true
    pkill -9 -x virgl_test_server >/dev/null 2>&1 || true
    sleep 1
    HALT_ATTEMPTS=$((HALT_ATTEMPTS + 1))
done

PREFIX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
mkdir -p "$PREFIX_TMP/.X11-unix" /tmp/.X11-unix
chmod 1777 "$PREFIX_TMP/.X11-unix" /tmp/.X11-unix 2>/dev/null || true
rm -f "$PREFIX_TMP/.X0-lock" "$PREFIX_TMP/.X11-unix/X0-lock" "$PREFIX_TMP/.X11-unix/X0" 2>/dev/null || true
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0-lock /tmp/.X11-unix/X0 2>/dev/null || true

echo -e "${CYAN}${BOLD}Launching Termux:X11 Android App...${RESET}"
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true
/system/bin/am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity 2>/dev/null || true
sleep 1

echo -e "${CYAN}${BOLD}Starting VirGL Rendering Server...${RESET}"
if command -v virgl_test_server >/dev/null 2>&1; then
    if ! pgrep -x virgl_test_server >/dev/null 2>&1; then
        virgl_test_server --use-egl-surfaceless >/dev/null 2>&1 &
    fi
fi

echo -e "${CYAN}${BOLD}Starting PulseAudio daemon for Termux...${RESET}"
if ! pgrep -x pulseaudio >/dev/null 2>&1; then
    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1 2>/dev/null || true
else
    pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 2>/dev/null || true
fi

echo -e "${CYAN}${BOLD}Starting Termux:X11 display server on :0...${RESET}"
export DISPLAY=:0
if command -v termux-x11 &> /dev/null; then
    termux-x11 :0 -ac -listen tcp >/dev/null 2>&1 &
    sleep 2
fi

echo -e "${CYAN}${BOLD}Ensuring System D-Bus daemon is active...${RESET}"
$DISTRO_CMD login $SELECTED_DISTRO --user root -- bash -c "
    mkdir -p /run/dbus /var/run/dbus
    rm -f /run/dbus/pid /var/run/dbus/pid /run/dbus/system_bus_socket /var/run/dbus/system_bus_socket 2>/dev/null
    dbus-uuidgen --ensure 2>/dev/null || true
    if ! pgrep -f 'dbus-daemon.*system' >/dev/null 2>&1 || [ ! -S /run/dbus/system_bus_socket ]; then
        dbus-daemon --system --fork 2>/dev/null || service dbus start 2>/dev/null || true
    fi
"

echo -e "${GREEN}${BOLD}Launching ${SELECTED_DISTRO^^} Touch Desktop session for user: ${YELLOW}$CHROOT_USER${GREEN}...${RESET}"
echo ""

if [ "$DISTRO_CMD" = "chroot-distro" ]; then
    CMD_PREFIX="$DISTRO_CMD login $SELECTED_DISTRO --user $CHROOT_USER --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix -- bash -c"
else
    CMD_PREFIX="$DISTRO_CMD login $SELECTED_DISTRO --user $CHROOT_USER -- shared-tmp -- bash -c"
fi

$CMD_PREFIX "
    source /etc/profile 2>/dev/null || true
    if [ -f /etc/profile.d/termux_env.sh ]; then source /etc/profile.d/termux_env.sh; fi
    export DISPLAY=:0
    export PULSE_SERVER=tcp:127.0.0.1:4713
    
    export XDG_RUNTIME_DIR=/tmp/runtime-\$USER
    mkdir -p \$XDG_RUNTIME_DIR
    chmod 700 \$XDG_RUNTIME_DIR
    
    if command -v dbus-run-session >/dev/null 2>&1; then
        dbus-run-session -- xfce4-session || dbus-run-session -- startxfce4
    elif command -v dbus-launch >/dev/null 2>&1; then
        dbus-launch --exit-with-session xfce4-session || dbus-launch --exit-with-session startxfce4
    else
        xfce4-session || startxfce4
    fi
"
