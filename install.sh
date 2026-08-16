#!/usr/bin/env bash

# Termux Autochroot 1-Click Installer
set -e

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}========================================${RESET}"
echo -e "${CYAN}${BOLD}   Installing Termux Autochroot...      ${RESET}"
echo -e "${CYAN}${BOLD}========================================${RESET}"

echo -e "${YELLOW}Installing dependencies...${RESET}"
pkg install wget unzip bash-completion -y > /dev/null 2>&1 || true

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="$PWD"

PREFIX_ROOT="${PREFIX:-/data/data/com.termux/files/usr}"
PREFIX_BIN="$PREFIX_ROOT/bin"
REPO_DIR="$PREFIX_ROOT/Chroot-Automated-Installer"
VISIBLE_REPO_DIR="$HOME/chroot-automated-installer"

mkdir -p "$PREFIX_ROOT" "$PREFIX_BIN" 2>/dev/null || true

LOCAL_INSTALL=0
if [ "$1" = "-l" ] || [ "$1" = "--local" ]; then
    LOCAL_INSTALL=1
    echo -e "${YELLOW}Local mode enabled. Skipping GitHub download...${RESET}"
fi

# Determine valid source directory
SRC_DIR=""
if [ "$LOCAL_INSTALL" -eq 1 ]; then
    if [ -f "$SCRIPT_DIR/setup.sh" ] && [ -d "$SCRIPT_DIR/scripts" ]; then
        SRC_DIR="$SCRIPT_DIR"
    elif [ -f "$VISIBLE_REPO_DIR/setup.sh" ]; then
        SRC_DIR="$VISIBLE_REPO_DIR"
    else
        SRC_DIR="$PWD"
    fi
else
    if [ -d "$VISIBLE_REPO_DIR/.git" ]; then
        echo -e "${YELLOW}Using the existing Home-folder Git copy as installation source...${RESET}"
        cd "$VISIBLE_REPO_DIR"
        git pull origin main 2>/dev/null || true
        SRC_DIR="$VISIBLE_REPO_DIR"
    elif [ -f "$SCRIPT_DIR/setup.sh" ] && [ -d "$SCRIPT_DIR/scripts" ] && [ "$SCRIPT_DIR" != "$REPO_DIR" ]; then
        SRC_DIR="$SCRIPT_DIR"
    else
        echo -e "${YELLOW}Downloading latest release from GitHub...${RESET}"
        TEMP_DL="$HOME/tmp/autochroot_install_$$"
        mkdir -p "$TEMP_DL"
        if wget -q https://github.com/Thanasis324/chroot-automated-installer/archive/refs/heads/main.zip -O "$TEMP_DL/installer.zip"; then
            unzip -q "$TEMP_DL/installer.zip" -d "$TEMP_DL"
            SRC_DIR="$TEMP_DL/chroot-automated-installer-main"
        else
            echo -e "${RED}[ERROR] Failed to download Autochroot release archive!${RESET}"
            exit 1
        fi
    fi
fi

if [ -n "$SRC_DIR" ] && [ "$SRC_DIR" != "$REPO_DIR" ]; then
    echo -e "${YELLOW}Installing Autochroot files to $REPO_DIR...${RESET}"
    mkdir -p "$REPO_DIR"
    cp -rf "$SRC_DIR"/* "$REPO_DIR"/ 2>/dev/null || cp -a "$SRC_DIR"/. "$REPO_DIR"/
    cp -rf "$SRC_DIR"/.[!.]* "$REPO_DIR"/ 2>/dev/null || true
fi

# Cleanup temp download folder if used
[ -n "$TEMP_DL" ] && rm -rf "$TEMP_DL" 2>/dev/null || true

echo -e "${YELLOW}Setting permissions...${RESET}"
cd "$REPO_DIR"
chmod +x setup.sh start-chroot.sh configure.sh scripts/*.sh 2>/dev/null || true

echo -e "${YELLOW}Generating global 'autochroot' command...${RESET}"
PREFIX_BIN="$PREFIX_ROOT/bin"

write_wrapper() {
    local target_path="$1"
    mkdir -p "$(dirname "$target_path")" 2>/dev/null || true
    chmod u+w "$target_path" 2>/dev/null || true
    rm -f "$target_path" 2>/dev/null || true
    (
        cat << EOF > "$target_path"
#!$PREFIX_ROOT/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PREFIX
export PATH="\$PREFIX/bin:\$HOME/.local/bin:\$HOME/bin:\$PATH:/system/bin:/system/xbin"
REPO_DIR="\$PREFIX/Chroot-Automated-Installer"

show_help() {
    echo -e "\033[1m\033[36m========================================\033[0m"
    echo -e "\033[1m\033[36m   Termux Automated Chroot (autochroot)  \033[0m"
    echo -e "\033[1m========================================\033[0m"
    echo -e "\033[1mUsage:\033[0m autochroot [flags] <command> [args...]"
    echo ""
    echo -e "\033[1mCommands:\033[0m"
    echo -e "  \033[32mautochroot start\033[0m      - Launch the desktop environment"
    echo -e "  \033[32mautochroot config\033[0m     - Configure or repair the OS"
    echo -e "  \033[32mautochroot setup\033[0m      - Run the initial installer"
    echo -e "  \033[32mautochroot setup -c\033[0m   - Install a custom rootfs (custom.tar.gz)"
    echo -e "  \033[32mautochroot update\033[0m     - Update Termux or Autochroot"
    echo ""
    echo -e "\033[1mFlags:\033[0m"
    echo -e "  \033[33m-h\033[0m      - Show this help menu"
    echo -e "  \033[33m-c\033[0m      - Custom rootfs installation mode"
    echo -e "  \033[33m-m\033[0m      - Manual mode (disables auto-selections)"
    echo -e "\033[36m========================================\033[0m"
}

if [ "\$1" = "-h" ] || [ -z "\$1" ]; then
    show_help
    exit 0
fi

if [ "\$1" = "-m" ]; then
    export AUTOCHROOT_MANUAL=1
    shift
fi

COMMAND="\$1"
shift

case "\$COMMAND" in
    start) SCRIPT_PATH="\$REPO_DIR/start-chroot.sh" ;;
    config|configure) SCRIPT_PATH="\$REPO_DIR/configure.sh" ;;
    setup|install) SCRIPT_PATH="\$REPO_DIR/setup.sh" ;;
    update) SCRIPT_PATH="\$REPO_DIR/scripts/update.sh" ;;
    *) echo -e "\033[33mUnknown command: \$COMMAND\033[0m"; show_help; exit 1 ;;
esac

if [ ! -f "\$SCRIPT_PATH" ]; then
    echo -e "\033[31mError: Could not find script at \$SCRIPT_PATH\033[0m"
    exit 1
fi

BASH_BIN="\$PREFIX/bin/bash"
[ ! -x "\$BASH_BIN" ] && BASH_BIN="\$(command -v bash 2>/dev/null || echo "bash")"
exec "\$BASH_BIN" "\$SCRIPT_PATH" "\$@"
EOF
    ) 2>/dev/null || return 1
    chmod 755 "$target_path" 2>/dev/null || true
    if command -v termux-fix-shebang &>/dev/null; then
        termux-fix-shebang "$target_path" 2>/dev/null || true
    fi
    return 0
}

EXECUTABLE_PATH=""
if write_wrapper "$PREFIX_BIN/autochroot"; then
    ln -sf "$PREFIX_BIN/autochroot" "$PREFIX_BIN/startchroot" 2>/dev/null || true
    ln -sf "$PREFIX_BIN/autochroot" "$PREFIX_BIN/start-chroot" 2>/dev/null || true
    EXECUTABLE_PATH="$PREFIX_BIN/autochroot"
fi

for ubin in "$HOME/.local/bin" "$HOME/bin"; do
    mkdir -p "$ubin" 2>/dev/null || true
    if write_wrapper "$ubin/autochroot"; then
        ln -sf "$ubin/autochroot" "$ubin/startchroot" 2>/dev/null || true
        ln -sf "$ubin/autochroot" "$ubin/start-chroot" 2>/dev/null || true
        [ -z "$EXECUTABLE_PATH" ] && EXECUTABLE_PATH="$ubin/autochroot"
    fi
done

echo -e "${YELLOW}Setting up bash autocompletion...${RESET}"
mkdir -p "$PREFIX/etc/bash_completion.d" 2>/dev/null || true
cat << 'EOF' > "$PREFIX/etc/bash_completion.d/autochroot" 2>/dev/null || true
_autochroot_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="start config setup install update -h -m -c"
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}
complete -F _autochroot_completions autochroot
EOF

# Clean up temporary update and installation files before launching the help screen
rm -f "$HOME/installer.zip" 2>/dev/null || true
rm -rf "$HOME/tmp/autochroot-update-"* "$HOME/tmp/Chroot.Automated.Script.zip" 2>/dev/null || true

# Automatically run the help menu so the user sees the commands immediately
if [ -n "$EXECUTABLE_PATH" ] && [ -f "$EXECUTABLE_PATH" ]; then
    "$PREFIX/bin/bash" "$EXECUTABLE_PATH" -h
fi

echo ""
echo -e "${GREEN}${BOLD}✓ Installation Complete!${RESET}"
if [ "${AUTOCHROOT_SKIP_VISIBLE_CLEANUP:-0}" != "1" ] && [ -d "$VISIBLE_REPO_DIR" ] && [ "$(cd "$VISIBLE_REPO_DIR" && pwd)" != "$REPO_DIR" ]; then
    echo ""
    echo -e "${YELLOW}A visible source copy remains at:${RESET} $VISIBLE_REPO_DIR"
    read -rp "Delete this Home-folder copy now? [y/N]: " DELETE_VISIBLE_COPY
    case "${DELETE_VISIBLE_COPY,,}" in
        y|yes)
            cd "$HOME"
            rm -rf "$VISIBLE_REPO_DIR"
            echo -e "${GREEN}Removed the visible Home-folder copy. Autochroot remains installed at $REPO_DIR.${RESET}"
            ;;
        *)
            echo -e "${CYAN}Keeping the visible copy. Autochroot uses $REPO_DIR.${RESET}"
            ;;
    esac
fi
echo -e "Please type ${BLUE}${BOLD}exit${RESET} to finish."
echo ""
