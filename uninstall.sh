#!/usr/bin/env bash
# ==============================================================================
# Uninstall Script for Termux Chroot Environment
# ==============================================================================

BOLD="\033[1m"
RED="\033[38;5;196m"
GREEN="\033[38;5;46m"
CYAN="\033[38;5;51m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}Uninstalling Termux Chroot Environment...${RESET}"

if command -v chroot-distro &> /dev/null; then
    DISTRO_CMD="chroot-distro"
else
    echo -e "${RED}chroot-distro is not installed. Nothing to remove.${RESET}"
    exit 0
fi

echo -e "${CYAN}Removing installed distributions (Debian, Fedora, Archlinux)...${RESET}"
$DISTRO_CMD remove debian 2>/dev/null || true
$DISTRO_CMD remove fedora 2>/dev/null || true
$DISTRO_CMD remove archlinux 2>/dev/null || true

echo -e "${CYAN}Removing configuration files...${RESET}"
rm -f "$HOME/.debian_user" "$HOME/.chroot_distro" 2>/dev/null || true
rm -f "/data/data/com.termux/files/home/.debian_user" "/data/data/com.termux/files/home/.chroot_distro" 2>/dev/null || true

PREFIX_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
rm -f "$PREFIX_BIN/startdebian" "$PREFIX_BIN/start-debian" "$PREFIX_BIN/startchroot" "$PREFIX_BIN/start-chroot" 2>/dev/null || true

TARGET_PATHS=(
    "./start-debian.sh"
    "./start-chroot.sh"
    "$HOME/start-debian.sh"
    "$HOME/start-chroot.sh"
    "/data/data/com.termux/files/home/start-debian.sh"
    "/data/data/com.termux/files/home/start-chroot.sh"
)

for path in "${TARGET_PATHS[@]}"; do
    rm -f "$path" 2>/dev/null || true
done

echo -e "${GREEN}${BOLD}Uninstallation Complete!${RESET} Base Termux packages were kept."
