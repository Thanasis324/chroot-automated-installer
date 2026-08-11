# Termux Automated Linux Chroot Setup Script

An automated, touch-optimized, and graphically appealing installation script for running **Fedora**, **Debian**, or **Arch Linux** inside **Termux** natively using **`chroot-distro`**. This script integrates **Termux:X11** display output, **PulseAudio** sound, and flawless hardware-accelerated **Qualcomm Adreno Turnip/Zink (A6XX / A7XX / A8XX) GPU Drivers** (alongside VirGL fallbacks).

---

## 🚀 How to Run in Termux

### Prerequisites
- **Termux** app installed.
- **Termux:X11** app installed.
- **Rooted Device** (Required for `chroot-distro`).
- **Recommended Termux:X11 Settings : **
1)output -> Fullscreen : on
2)pointer -> touchscreen input mode: Direct touch

### Installation Guide

#### Step 1: Clone the Repository
Open Termux and install Git, then clone this repository:
```bash
pkg install git -y
git clone https://github.com/Thanasis324/chroot-automated-installer.git
cd chroot-automated-installer
```

#### Step 2: Set Permissions
Make all the installation and boot scripts executable:
```bash
chmod +x setup.sh start-chroot.sh uninstall.sh scripts/*.sh
```

#### Step 3: Launch Installer
Run the setup script directly as your standard Termux user (**Do NOT run with sudo!** The script intelligently elevates privileges automatically when needed):
```bash
./setup.sh
```

#### Step 4: Interactive Setup & Mirror Selection
The script features an advanced setup UI that will guide you through:
1. **Repository Mirror Selection**: Automatically launches `termux-change-repo` so you can select the fastest mirror for your region.
2. **Linux Distribution Selection**: 
   - **Fedora** *(Recommended - Easy to use, excellent driver support)*
   - **Debian** *(Highly stable core)*
   - **Archlinux** *(For advanced rolling-release users)*
3. **Desired Username & Password**
4. **GPU Architecture Fallback**: If it cannot auto-detect your GPU, it will ask you to select between **Adreno 8xx/7xx/6xx** or **VirGL (Mali/PowerVR/Exynos/Tensor)**.

#### Step 5: Launch your Touch Desktop (Do NOT use sudo!)
Once installation finishes, start your system:
1. Open the **Termux:X11** app on your Android device.
2. Launch the desktop directly as a regular Termux user:
   ```bash
   ./start-chroot.sh
   # OR simply type
   startchroot
   ```

---

## 🛠️ Repository Architecture

- **`setup.sh`**: The master installer. Features smart privilege-dropping to safely execute `apt`/`pkg` commands (fixing Termux Curl/SSL fresh-install bugs), then cleanly elevates to root.
- **`start-chroot.sh`**: A master delegator that dynamically detects installed distributions via `chroot-distro list` and executes the corresponding OS launcher.
- **`scripts/start_*.sh`**: Modular, distro-specific boot scripts that handle DBus isolation (`dbus-run-session`), XFCE4 configurations, and GPU environment variables natively.
- **`scripts/gpu_detect.sh`**: Hardware identification module designed to read Android properties (`getprop`) and sysfs nodes to intelligently configure Adreno Turnip profiles.
- **`uninstall.sh`**: Safely and cleanly uninstalls the distributions and removes configuration files without harming your base Termux.

---

## 🌟 Key Features

1. **Native Chroot Performance**: Built exclusively around `chroot-distro` for true native hardware mounting, ensuring maximum performance compared to PRoot environments.
2. **Native Bluetooth Gamepad Support**: Automatically maps Android's secure input groups (`aid_input`) into the chroot and runs a lightweight background `termux-udevd` daemon to bypass missing `udev` dependencies. 
   - Xbox, PlayStation (DualShock/DualSense), Nintendo, 8BitDo, GameSir, and generic Bluetooth controllers work natively in Linux games without root hacks!
   - Full support for **Rumble (Force-Feedback)** and LED controls via automated secure permission injections (`chmod 666`).
   - Disables aggressive SDL HIDAPI polling so controllers flawlessly fall back to standard `evdev`.
3. **Advanced Adreno GPU Stack**:
   - Accurately detects and maps Qualcomm Adreno GPUs, supporting **6xx**, **7xx**, and the bleeding-edge **8xx Series** (e.g., Snapdragon 8 Elite, 8S Gen 4).
   - Installs the complete official Khronos Vulkan pipeline (`vulkan-loader-generic`, `mesa-vulkan-icd-freedreno`, `mesa-zink`) to bypass generic software rendering.
   - Provides a guaranteed **VirGL** fallback renderer for non-Adreno chipsets (Mali, PowerVR, Exynos Xclipse, Google Tensor).
3. **Smart Privilege Dropping**: Setup script safely navigates Termux's root constraints by using `su -c` dropping mechanisms and raw `apt full-upgrade` commands to prevent `pkg` crashes on fresh installs.
4. **Touch-Optimized XFCE4 Environment**:
   - Pre-configures a sleek system-wide Dark Mode scenario (**Arc-Dark GTK theme** & **Papirus-Dark icons**).
   - **Single-Click UI**: Desktop icons and Thunar File Manager are pre-configured to open with a single tap, drastically improving the touchscreen experience.
   - **Shutdown OS**: Bypasses systemd constraints by injecting a custom "Shutdown OS" desktop shortcut that elegantly terminates the XFCE session and cleanly unmounts the chroot from Termux.
   - Bundles the **Onboard Virtual Keyboard** pre-configured to autostart, dock cleanly, and dynamically appear for text input.
5. **Secure DBus & Audio Isolation**: Uses `XDG_RUNTIME_DIR=/tmp/runtime-$USER` inside isolated DBus sessions to guarantee perfectly stable XFCE4 boots every time.

---

## 🧠 For Advanced Users & Developers

If you are a developer or a power user tasked with debugging or extending this environment, here is the technical blueprint of how everything connects under the hood:

**1. Installation & Boot Architecture**
*   **The Chroot:** This setup completely bypasses PRoot and uses `chroot-distro` (requiring a rooted device) to communicate directly with the Android kernel for maximum bare-metal performance.
*   **Environment Injection:** The base environment variables (like `XDG_RUNTIME_DIR` and DBus socket definitions) are statically generated into `/etc/profile.d/termux_env.sh` during setup. `start_fedora.sh` binds the container and executes the XFCE4 session using `dbus-run-session`.
*   **Display & Audio:** X11 is piped directly to the `Termux:X11` Android app via local sockets (`DISPLAY=:0`). Audio is streamed via TCP to the Termux PulseAudio server (`PULSE_SERVER=tcp:127.0.0.1:4713`).

**2. The GPU Acceleration Stack (Turnip + Zink)**
*   **The Hardware Bridge:** Adreno GPUs (especially the 8xx series like Snapdragon 8s Gen 4 / 8 Elite) use the **Turnip** Vulkan ICD (`freedreno_icd.aarch64.json`). OpenGL is layered on top of Vulkan using the **Zink** gallium driver.
*   **Critical Vulkan/X11 Fix (`MESA_VK_WSI_DEBUG=sw`):** Termux:X11 operates over a socket and cannot natively ingest hardware DMA-BUF surfaces from Turnip. To prevent `CreateSwapchainKHR` and `GLXBadCurrentWindow` crashes in applications, we forcefully inject `MESA_VK_WSI_DEBUG=sw`. This commands Mesa's Window System Integration to utilize a software shared-memory buffer to present the final hardware-rendered frame to X11.
*   **Adreno 8xx Stability:** Modern Adreno chips frequently hang on experimental Turnip drivers. We stabilize them by injecting `TU_DEBUG=kgsl,noconform,nolrz`.
*   **Software Rendering & CPU Compatibility:** When falling back to `LLVMpipe`, modern ARM CPUs may falsely report SVE capabilities, causing illegal instruction crashes (`SIGILL`) in 3D apps. We inject `GALLIVM_PERF=nopt` to disable these buggy JIT optimizations. Additionally, `OPENSSL_armcap=0` is set to prevent `libcrypto` from crashing during hardware capability probing on newer Snapdragon chips.
*   **Helper Scripts:** The environment generates `/usr/local/bin/enable-zink` and `/usr/local/bin/enable-freedreno` to allow users to hot-swap graphics stacks via bash aliases if an application misbehaves.

**3. Desktop Environment (XFCE4) & Compositing**
*   Because Zink intercepts the OpenGL pipeline globally, it can violently crash if the XFCE window manager attempts to composite shadows and transparencies using unsupported legacy X11 extensions. 
*   We forcefully disable compositing in `xfwm4.xml` and inject a `disable-compositor.desktop` autostart script to guarantee XFCE never tries to render composited effects, protecting the GPU pipeline for actual games/applications.

**4. Native Steam (ARM64 & x86) and Kernel IPC Constraints**
*   **The Emulation Route:** Running x86 games requires FEX-Emu/Box64. This relies on the kernel flag `CONFIG_BINFMT_MISC=y` to automatically catch and translate x86 binaries.
*   **The Native ARM64 Steam Route:** Even if you use a native ARM64 build of the Steam Client, **Steam will fail to launch** (`threadtools.cpp : Assertion Failed: Function not implemented`) on standard Android kernels.
*   **The Kernel Requirement:** Valve's Steam engine intrinsically relies on legacy **System V IPC Semaphores** (`semget`). Android disables this globally for security. You **cannot** bypass this in a true chroot using `LD_PRELOAD` shims (like `libandroid-shmem`, which only handles shared memory, not semaphores). **You MUST flash a custom Android kernel with `CONFIG_SYSVIPC=y` compiled in** if you want Steam to boot.

---

## 🐛 Known Bugs & Troubleshooting

**1. "Container fedora is busy" or "/dev/null Permission Denied"**
*   **Cause:** If your Android device undergoes a "soft reboot" (e.g. SurfaceFlinger or SystemUI crashes and restarts) while the chroot is active, Android's kernel does not restart. This leaves the `chroot-distro` mounts (like `/dev` and `/tmp`) orphaned and locked in a broken state.
*   **Fix:** Do a full hardware restart of your phone. Rebooting the device will cleanly flush all orphaned kernel namespaces and mounts, allowing `./start-chroot.sh` to work perfectly again.

---

## 🙏 Credits & Acknowledgments

*   **[chroot-distro](https://github.com/sabamdarif/chroot-distro)**: This project is heavily reliant on the incredible work done by the `chroot-distro` project to provide native, high-performance containerization on Android.
*   **[Termux](https://termux.dev/) & [Termux:X11](https://github.com/termux/termux-x11)**: For providing the core terminal environment and the robust X11 display server that makes the graphical interface possible.
*   **[Mesa Project](https://www.mesa3d.org/)**: For the open-source Turnip (Vulkan) and Zink (OpenGL) drivers.
*   **[lfdevs/mesa-for-android-container](https://github.com/lfdevs/mesa-for-android-container)**: Huge thanks for providing pre-compiled, highly-optimized Mesa drivers specifically tailored for Android containers that bring true hardware acceleration to Adreno GPUs.
*   **[XFCE](https://xfce.org/)**: For the lightweight, fast, and touch-friendly desktop environment used in this setup.
*   **[PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/)**: For enabling seamless audio streaming between the chroot and Android.
*   **[VirGL](https://virgil3d.github.io/)**: For providing the fallback 3D acceleration for non-Adreno GPUs.
*   **[Arc Theme](https://github.com/horst3180/arc-theme) & [Papirus Icons](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)**: For the sleek and beautiful dark mode desktop aesthetics.
*   **[Onboard](https://launchpad.net/onboard)**: For the touch-optimized virtual keyboard that makes interacting with the desktop possible.
*   **[Box64](https://box86.org/) & [FEX-Emu](https://fex-emu.com/)**: For their incredible x86 emulation technologies that make PC gaming possible on ARM devices.
*   **Linux Distributions**: Thanks to the **[Fedora](https://fedoraproject.org/)**, **[Debian](https://www.debian.org/)**, and **[Arch Linux](https://archlinux.org/)** projects for their robust operating systems.
