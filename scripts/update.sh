#!/usr/bin/env bash

set -e

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
WHITE="\033[37m"
RED="\033[31m"
RESET="\033[0m"

REQUESTED_TAG=""
BUILD_MESA_RELEASE_ASSET=0

# --- Secret Dev Utility Mode ---
if [ "$1" == "-d" ]; then
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -m) BUILD_MESA_RELEASE_ASSET=1 ;;
            *)
                echo -e "${RED}Usage: autochroot update -d [-m]${RESET}"
                exit 1
                ;;
        esac
        shift
    done

    echo -e "${CYAN}${BOLD}=== Developer Release Mode ===${RESET}"
    PREFIX_ROOT="${PREFIX:-/data/data/com.termux/files/usr}"
    REPO_DIR="$PREFIX_ROOT/Chroot-Automated-Installer"

    if [ ! -d "$REPO_DIR/.git" ]; then
        echo -e "${RED}[ERROR] Managed Autochroot repository not found at $REPO_DIR.${RESET}"
        echo -e "Run the installer first so ${WHITE}autochroot update -d${RESET} uses the hidden installation copy."
        exit 1
    fi

    echo -e "${CYAN}Using managed repository: $REPO_DIR${RESET}"
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
    if ! command -v zip &> /dev/null || ! command -v gh &> /dev/null || ! command -v git &> /dev/null || { [ "$BUILD_MESA_RELEASE_ASSET" -eq 1 ] && ! command -v curl &> /dev/null; }; then
        echo -e "${YELLOW}Installing required dev packages (zip, gh, git, curl)...${RESET}"
        pkg install zip gh git curl -y
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
        GIT_EDITOR=true git pull --rebase origin main || true
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

        if [ "$BUILD_MESA_RELEASE_ASSET" -eq 1 ]; then
            echo -e "${YELLOW}Building Mesa release asset...${RESET}"
            bash "$REPO_DIR/scripts/bundle_mesa.sh"
            if [ ! -f "$REPO_DIR/mesa-debs-trixie.zip" ]; then
                echo -e "${RED}Mesa bundle was not created. Release cancelled.${RESET}"
                exit 1
            fi
        fi
        
        # Create the ZIP archive
        ZIP_NAME="Chroot.Automated.Script.zip"
        echo -e "${YELLOW}Bundling files into $ZIP_NAME...${RESET}"
        rm -f "$ZIP_NAME"
        FILES_TO_ZIP="start-chroot.sh setup.sh install.sh configure.sh scripts/"
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

while getopts ":t:" opt; do
    case "$opt" in
        t) REQUESTED_TAG="$OPTARG" ;;
        *)
            echo -e "${RED}Usage: autochroot update [-t release-tag]${RESET}"
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [ -n "$REQUESTED_TAG" ] && [[ ! "$REQUESTED_TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo -e "${RED}Invalid release tag. Use only letters, numbers, dots, underscores, or hyphens.${RESET}"
    exit 1
fi

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
    local release_name="${REQUESTED_TAG:-latest}"
    local release_url
    local temp_root="$HOME/tmp"
    local update_dir="$temp_root/autochroot-update-$release_name"
    local archive="$temp_root/Chroot.Automated.Script.zip"

    if [ "$release_name" = "latest" ]; then
        release_url="https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/Chroot.Automated.Script.zip"
    else
        release_url="https://github.com/Thanasis324/chroot-automated-installer/releases/download/$release_name/Chroot.Automated.Script.zip"
    fi

    echo -e "${YELLOW}Downloading Autochroot release: $release_name...${RESET}"
    if ! command -v curl &> /dev/null || ! command -v unzip &> /dev/null; then
        echo -e "${YELLOW}Installing required update tools...${RESET}"
        pkg install -y curl unzip
    fi

    mkdir -p "$temp_root"
    rm -rf "$update_dir"

    if ! curl -fL --retry 3 "$release_url" -o "$archive"; then
        echo -e "${RED}Failed to download release '$release_name'. Check that the tag and release asset exist.${RESET}"
        exit 1
    fi

    if ! unzip -tq "$archive" > /dev/null; then
        echo -e "${RED}Downloaded release archive is invalid. Update cancelled.${RESET}"
        exit 1
    fi

    mkdir -p "$update_dir"
    unzip -q "$archive" -d "$update_dir"
    if [ ! -f "$update_dir/install.sh" ]; then
        echo -e "${RED}Release archive does not contain install.sh. Update cancelled.${RESET}"
        exit 1
    fi

    echo -e "${YELLOW}Installing release $release_name...${RESET}"
    (
        cd "$update_dir"
        AUTOCHROOT_SKIP_VISIBLE_CLEANUP=1 bash ./install.sh --local
    )

    rm -rf "$update_dir" "$archive"
    echo -e "${GREEN}Autochroot updated successfully from release $release_name.${RESET}"
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
