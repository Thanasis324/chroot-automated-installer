#!/usr/bin/env bash

set -e

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
WHITE="\033[37m"
RED="\033[31m"
RESET="\033[0m"

# --- Secret Dev Utility Mode ---
if [ "$1" == "-d" ]; then
    echo -e "${CYAN}${BOLD}=== Developer Release Mode ===${RESET}"
    REPO_DIR="/data/data/com.termux/files/home/chroot-automated-installer"
    echo -e "What would you like to do?"
    echo -e "  ${WHITE}1)${RESET} Commit only (push changes to main)"
    echo -e "  ${WHITE}2)${RESET} Release only (create tag and GitHub release)"
    echo -e "  ${WHITE}3)${RESET} Both (commit changes and create release)"
    echo -e "  ${WHITE}4)${RESET} Cancel"
    read -p "Select an option (1-4): " dev_choice
    
    if [ "$dev_choice" == "4" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    # 1. Ensure required tools are installed
    if ! command -v zip &> /dev/null || ! command -v gh &> /dev/null || ! command -v git &> /dev/null; then
        echo -e "${YELLOW}Installing required dev packages (zip, gh, git)...${RESET}"
        pkg install zip gh git -y
    fi
    
    cd "$REPO_DIR" || exit 1
    
    # COMMIT LOGIC
    if [ "$dev_choice" == "1" ] || [ "$dev_choice" == "3" ]; then
        read -p "Enter commit message: " commit_msg
        if [ -z "$commit_msg" ]; then
            echo -e "${RED}Commit message cannot be empty. Aborting.${RESET}"
            exit 1
        fi
        echo -e "${YELLOW}Committing and pushing to GitHub main branch...${RESET}"
        git add .
        git commit -m "$commit_msg" || true
        git push origin main
        if [ "$dev_choice" == "1" ]; then
            echo -e "${GREEN}${BOLD}Changes committed and pushed successfully!${RESET}"
            exit 0
        fi
    fi
    
    # RELEASE LOGIC
    if [ "$dev_choice" == "2" ] || [ "$dev_choice" == "3" ]; then
        # Check GitHub CLI Authentication
        if ! gh auth status &>/dev/null; then
            echo -e "${RED}[ERROR] You are not logged into the GitHub CLI.${RESET}"
            echo -e "Please run: ${WHITE}gh auth login${RESET} to authenticate your GitHub account, then run this again."
            exit 1
        fi
        
        read -p "Enter the new release tag (e.g., 0.6): " rel_tag
        if [ -z "$rel_tag" ]; then
            echo -e "${RED}Tag cannot be empty. Aborting.${RESET}"
            exit 1
        fi
        
        # Create the ZIP archive
        ZIP_NAME="Chroot.Automated.Script.zip"
        echo -e "${YELLOW}Bundling files into $ZIP_NAME...${RESET}"
        rm -f "$ZIP_NAME"
        FILES_TO_ZIP="start-chroot.sh setup.sh install.sh scripts/"
        [ -f "config.sh" ] && FILES_TO_ZIP="config.sh $FILES_TO_ZIP"
        zip -r "$ZIP_NAME" $FILES_TO_ZIP
        
        echo -e "${YELLOW}Pushing release tag to GitHub...${RESET}"
        git tag "$rel_tag" || true
        git push origin "$rel_tag"
        
        # Create GitHub Release
        echo -e "${YELLOW}Creating GitHub Release V${rel_tag}...${RESET}"
        if [ -f "mesa-debs-trixie.zip" ]; then
            gh release create "$rel_tag" "$ZIP_NAME" "mesa-debs-trixie.zip" --title "V${rel_tag}" --notes "Automated release V${rel_tag}"
        else
            gh release create "$rel_tag" "$ZIP_NAME" --title "V${rel_tag}" --notes "Automated release V${rel_tag}"
        fi
        
        # Clean up local zip
        rm -f "$ZIP_NAME"
        
        echo -e "${GREEN}${BOLD}Release V${rel_tag} published successfully!${RESET}"
        exit 0
    fi
fi
# -------------------------------

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
