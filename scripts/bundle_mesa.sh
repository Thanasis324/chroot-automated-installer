#!/usr/bin/env bash
set -e

PREFIX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
INSTALL_DIR="${PREFIX:-/data/data/com.termux/files/usr}/Chroot-Automated-Installer"

# Temporary directory for downloading
mkdir -p "$PREFIX_TMP/mesa_debs"
cd "$PREFIX_TMP/mesa_debs"
rm -f *.deb

echo "Fetching latest Mesa packages from Freedesktop gfx-ci (Debian Trixie)..."
BASE_URL="https://gitlab.freedesktop.org/gfx-ci/ci-deb-repo/-/raw/trixie/dists/trixie/main/binary-arm64"

# Define required packages
PKGS=(
    "libgl1-mesa-dri"
    "mesa-vulkan-drivers"
    "libvulkan1"
    "libglx-mesa0"
    "libegl-mesa0"
    "mesa-libgallium"
    "libgl1"
    "mesa-utils"
    "libglapi-mesa"
    "libgbm1"
)

# Download packages
curl -sL "$BASE_URL/Packages" > Packages.txt || true
for pkg in "${PKGS[@]}"; do
    FILE_PATH=$(awk -v pkg="^Package: $pkg\$" '$0 ~ pkg {found=1} found && /^Filename:/ {print $2; exit}' Packages.txt 2>/dev/null || true)
    if [ -n "$FILE_PATH" ]; then
        DOWNLOAD_URL="https://gitlab.freedesktop.org/gfx-ci/ci-deb-repo/-/raw/trixie/$FILE_PATH"
        echo "Downloading $pkg..."
        curl -f -sL "$DOWNLOAD_URL" -o "$(basename "$FILE_PATH")" || echo "Warning: Failed to download $pkg from $DOWNLOAD_URL"
    else
        echo "Warning: Could not find path for $pkg in Freedesktop Packages index"
    fi
done

DEB_COUNT=$(ls -1 "$PREFIX_TMP/mesa_debs"/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -ge 5 ]; then
    echo "Bundling into mesa-debs-trixie.zip ($DEB_COUNT debs)..."
    cd "$PREFIX_TMP"
    zip -r mesa-debs-trixie.zip mesa_debs/*.deb
    mv mesa-debs-trixie.zip "$INSTALL_DIR/"
    [ -d "/data/data/com.termux/files/home/chroot-automated-installer" ] && cp "$INSTALL_DIR/mesa-debs-trixie.zip" "/data/data/com.termux/files/home/chroot-automated-installer/" 2>/dev/null || true
    rm -rf "$PREFIX_TMP/mesa_debs"
    echo "Done! The zip file is ready at $INSTALL_DIR/mesa-debs-trixie.zip"
else
    echo "Warning: Freedesktop download incomplete ($DEB_COUNT debs downloaded)."
    echo "Falling back to previous release mesa-debs-trixie.zip from GitHub..."
    cd "$PREFIX_TMP"
    rm -rf "$PREFIX_TMP/mesa_debs"
    
    FALLBACK_DOWNLOADED=0
    FALLBACK_URL="https://github.com/Thanasis324/chroot-automated-installer/releases/latest/download/mesa-debs-trixie.zip"
    if curl -fL --retry 3 "$FALLBACK_URL" -o "$PREFIX_TMP/mesa-debs-trixie.zip" 2>/dev/null && unzip -tq "$PREFIX_TMP/mesa-debs-trixie.zip" >/dev/null 2>&1; then
        FALLBACK_DOWNLOADED=1
    elif command -v gh &>/dev/null; then
        echo "Trying previous release tags with GitHub CLI..."
        for tag in $(gh release list --limit 5 2>/dev/null | awk '{print $1}'); do
            if gh release download "$tag" -p "mesa-debs-trixie.zip" --dir "$PREFIX_TMP" --clobber 2>/dev/null; then
                if [ -f "$PREFIX_TMP/mesa-debs-trixie.zip" ] && unzip -tq "$PREFIX_TMP/mesa-debs-trixie.zip" >/dev/null 2>&1; then
                    echo "Found and downloaded verified Mesa bundle from release '$tag'."
                    FALLBACK_DOWNLOADED=1
                    break
                fi
            fi
        done
    fi

    if [ "$FALLBACK_DOWNLOADED" -eq 1 ]; then
        mv "$PREFIX_TMP/mesa-debs-trixie.zip" "$INSTALL_DIR/"
        [ -d "/data/data/com.termux/files/home/chroot-automated-installer" ] && cp "$INSTALL_DIR/mesa-debs-trixie.zip" "/data/data/com.termux/files/home/chroot-automated-installer/" 2>/dev/null || true
        echo "Done! Reused verified Mesa bundle from previous release for new release."
    else
        echo "Error: Failed to fetch Mesa debs from Freedesktop and failed to retrieve GitHub fallback release asset."
        exit 1
    fi
fi
