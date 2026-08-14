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

LOCAL_INSTALL=0
if [ "$1" = "-l" ] || [ "$1" = "--local" ]; then
    LOCAL_INSTALL=1
    echo -e "${YELLOW}Local mode enabled. Skipping GitHub download...${RESET}"
fi

VISIBLE_REPO_DIR="$HOME/chroot-automated-installer"
PREFIX_ROOT="${PREFIX:-/data/data/com.termux/files/usr}"
REPO_DIR="$PREFIX_ROOT/Chroot-Automated-Installer"

if [ "$LOCAL_INSTALL" -eq 0 ]; then
    if [ -d "$REPO_DIR/.git" ]; then
        echo -e "${YELLOW}Existing Git repository found. Pulling latest changes...${RESET}"
        cd "$REPO_DIR"
        git pull origin main || true
    else
        if [ -d "$VISIBLE_REPO_DIR/.git" ]; then
            echo -e "${YELLOW}Using the existing Home-folder copy as the installation source...${RESET}"
            cd "$VISIBLE_REPO_DIR"
            git pull origin main || true
        else
            if [ -d "$VISIBLE_REPO_DIR" ]; then
                echo -e "${YELLOW}Existing standard Home-folder copy found. Refreshing it...${RESET}"
                rm -rf "$VISIBLE_REPO_DIR"
            fi
            echo -e "${YELLOW}Downloading latest release...${RESET}"
            cd "$HOME"
            wget -q https://github.com/Thanasis324/chroot-automated-installer/archive/refs/heads/main.zip -O installer.zip
            unzip -q installer.zip
            mv chroot-automated-installer-main chroot-automated-installer
            rm installer.zip
        fi
    fi
elif [ "$PWD" != "$REPO_DIR" ]; then
    VISIBLE_REPO_DIR="$PWD"
fi

if [ "$PWD" != "$REPO_DIR" ]; then
    echo -e "${YELLOW}Installing Autochroot files in $REPO_DIR...${RESET}"
    rm -rf "$REPO_DIR"
    mkdir -p "$PREFIX_ROOT"
    cp -a "$PWD" "$REPO_DIR"
fi

echo -e "${YELLOW}Setting permissions...${RESET}"
cd "$REPO_DIR"
chmod +x setup.sh start-chroot.sh configure.sh scripts/*.sh 2>/dev/null || true

echo -e "${YELLOW}Generating global 'autochroot' command...${RESET}"
PREFIX_BIN="$PREFIX_ROOT/bin"

# Write the global wrapper script
cat << 'EOF' > "$PREFIX_BIN/autochroot"
#!/usr/bin/env bash
REPO_DIR="${PREFIX:-/data/data/com.termux/files/usr}/Chroot-Automated-Installer"

show_help() {
    echo -e "\033[1m\033[36m========================================\033[0m"
    echo -e "\033[1m\033[36m   Termux Automated Chroot (autochroot)  \033[0m"
    echo -e "\033[1m\033[36m========================================\033[0m"
    echo -e "\033[1mUsage:\033[0m autochroot [flags] <command> [args...]"
    echo ""
    echo -e "\033[1mCommands:\033[0m"
    echo -e "  \033[32mautochroot start\033[0m   - Launch the desktop environment"
    echo -e "  \033[32mautochroot config\033[0m  - Configure or repair the OS"
    echo -e "  \033[32mautochroot setup\033[0m   - Run the initial installer"
    echo -e "  \033[32mautochroot update\033[0m  - Update Termux or Autochroot"
    echo ""
    echo -e "\033[1mFlags:\033[0m"
    echo -e "  \033[33m-h\033[0m      - Show this help menu"
    echo -e "  \033[33m-m\033[0m      - Manual mode (disables auto-selections)"
    echo -e "\033[36m========================================\033[0m"
}

if [ "$1" = "-h" ] || [ -z "$1" ]; then
    show_help
    exit 0
fi

if [ "$1" = "-m" ]; then
    export AUTOCHROOT_MANUAL=1
    shift
fi

COMMAND="$1"
shift

case "$COMMAND" in
    start) SCRIPT_PATH="$REPO_DIR/start-chroot.sh" ;;
    config|configure) SCRIPT_PATH="$REPO_DIR/configure.sh" ;;
    setup|install) SCRIPT_PATH="$REPO_DIR/setup.sh" ;;
    update) SCRIPT_PATH="$REPO_DIR/scripts/update.sh" ;;
    *) echo -e "\033[33mUnknown command: $COMMAND\033[0m"; show_help; exit 1 ;;
esac

if [ ! -f "$SCRIPT_PATH" ]; then
    echo -e "\033[31mError: Could not find script at $SCRIPT_PATH\033[0m"
    exit 1
fi
exec bash "$SCRIPT_PATH" "$@"
EOF

chmod +x "$PREFIX_BIN/autochroot" 2>/dev/null || true

# Compatibility links
ln -sf "$PREFIX_BIN/autochroot" "$PREFIX_BIN/startchroot"
ln -sf "$PREFIX_BIN/autochroot" "$PREFIX_BIN/start-chroot"

echo -e "${YELLOW}Setting up bash autocompletion...${RESET}"
mkdir -p "$PREFIX/etc/bash_completion.d" 2>/dev/null || true
cat << 'EOF' > "$PREFIX/etc/bash_completion.d/autochroot"
_autochroot_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="start config setup update -h -m"
    COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
}
complete -F _autochroot_completions autochroot
EOF

# Automatically run the help menu so the user sees the commands immediately
"$PREFIX_BIN/autochroot" -h

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
