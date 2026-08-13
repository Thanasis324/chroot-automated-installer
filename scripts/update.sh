#!/usr/bin/env bash

set -e

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
WHITE="\033[37m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${CYAN}${BOLD}========================================${RESET}"
echo -e "${CYAN}${BOLD}       Autochroot Update Utility        ${RESET}"
echo -e "${CYAN}${BOLD}========================================${RESET}"
echo -e "What would you like to update?"
echo -e "  ${WHITE}1)${RESET} Update Termux Packages"
echo -e "  ${WHITE}2)${RESET} Update Autochroot (pull latest from GitHub)"
echo -e "  ${WHITE}3)${RESET} Both"
echo -e "  ${WHITE}4)${RESET} Cancel"
echo -e "${CYAN}${BOLD}========================================${RESET}"

read -p "Select an option (1-4): " choice
echo ""

update_termux() {
    echo -e "${YELLOW}Updating Termux packages...${RESET}"
    pkg update -y && pkg upgrade -y
    echo -e "${GREEN}Termux packages updated successfully!${RESET}"
    echo ""
}

update_autochroot() {
    echo -e "${YELLOW}Updating Autochroot from GitHub...${RESET}"
    curl -sL https://raw.githubusercontent.com/Thanasis324/chroot-automated-installer/main/install.sh | bash
    # install.sh might exit the script, so keep this last
}

case "$choice" in
    1)
        update_termux
        ;;
    2)
        update_autochroot
        ;;
    3)
        update_termux
        update_autochroot
        ;;
    4)
        echo "Update cancelled."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice.${RESET}"
        exit 1
        ;;
esac
