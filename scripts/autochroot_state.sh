#!/usr/bin/env bash
# Persistent state is deliberately outside the managed repository.
AUTOCHROOT_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
AUTOCHROOT_STATE_DIR="$AUTOCHROOT_PREFIX/var/lib/autochroot"

autochroot_valid_name() { [[ "$1" =~ ^[a-z][a-z0-9_-]*$ ]]; }
autochroot_meta_file() { printf '%s/distros/%s.conf' "$AUTOCHROOT_STATE_DIR" "$1"; }
autochroot_renderer_file() { printf '%s/renderers/%s.conf' "$AUTOCHROOT_STATE_DIR" "$1"; }

autochroot_save_distro() {
    mkdir -p "$AUTOCHROOT_STATE_DIR/distros"
    printf "DISTRO_FAMILY='%s'\nSETUP_MODE='%s'\nCHROOT_USER='%s'\n" "$2" "$3" "$4" > "$(autochroot_meta_file "$1")"
}
autochroot_load_distro() {
    DISTRO_FAMILY=""; SETUP_MODE=""; CHROOT_USER=""
    [ -f "$(autochroot_meta_file "$1")" ] && source "$(autochroot_meta_file "$1")"
}
autochroot_remove_distro_state() { rm -f "$(autochroot_meta_file "$1")" "$(autochroot_renderer_file "$1")"; }
autochroot_save_renderer() { mkdir -p "$AUTOCHROOT_STATE_DIR/renderers"; printf "RENDERER='%s'\n" "$2" > "$(autochroot_renderer_file "$1")"; }
autochroot_load_renderer() { RENDERER=""; [ -f "$(autochroot_renderer_file "$1")" ] && source "$(autochroot_renderer_file "$1")"; }

autochroot_list_distros() {
    local root entry name seen=" "
    for root in "$AUTOCHROOT_PREFIX/var/lib/chroot-distro/containers" "$AUTOCHROOT_PREFIX/var/lib/chroot-distro/installed-rootfs"; do
        [ -d "$root" ] || continue
        for entry in "$root"/*; do
            [ -d "$entry" ] || continue
            name="${entry##*/}"
            # Only list valid containers (must exist in containers/ or have a populated rootfs)
            if [ -d "$AUTOCHROOT_PREFIX/var/lib/chroot-distro/containers/$name" ] || [ -f "$entry/etc/os-release" ] || [ -f "$entry/bin/sh" ] || [ -f "$entry/bin/bash" ]; then
                case "$seen" in *" $name "*) ;; *) printf '%s\n' "$name"; seen="$seen$name ";; esac
            fi
        done
    done
}
