#!/usr/bin/env bash
set -e

PREFIX_TMP="${PREFIX:-/data/data/com.termux/files/usr}/tmp"

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
curl -sL "$BASE_URL/Packages" > Packages.txt
for pkg in "${PKGS[@]}"; do
    FILE_PATH=$(awk -v pkg="^Package: $pkg\$" '$0 ~ pkg {found=1} found && /^Filename:/ {print $2; exit}' Packages.txt)
    if [ -n "$FILE_PATH" ]; then
        DOWNLOAD_URL="https://gitlab.freedesktop.org/gfx-ci/ci-deb-repo/-/raw/trixie/$FILE_PATH"
        echo "Downloading $pkg..."
        curl -sL "$DOWNLOAD_URL" -o "$(basename "$FILE_PATH")"
    else
        echo "Warning: Could not find path for $pkg"
    fi
done

echo "Bundling into mesa-debs-trixie.zip..."
cd "$PREFIX_TMP"
zip -r mesa-debs-trixie.zip mesa_debs/*.deb
mv mesa-debs-trixie.zip /data/data/com.termux/files/home/chroot-automated-installer/
rm -rf "$PREFIX_TMP/mesa_debs"

echo "Done! The zip file is ready at ~/chroot-automated-installer/mesa-debs-trixie.zip"
