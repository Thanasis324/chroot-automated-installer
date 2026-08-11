# Termux Automated Linux Chroot Setup Script

An automated, touch-optimized, and graphically appealing installation script for running **Fedora**, **Debian**, or **Arch Linux** inside **Termux** natively using **`chroot-distro`**. This script integrates **Termux:X11** display output, **PulseAudio** sound, and flawless hardware-accelerated **Qualcomm Adreno Turnip/Zink (A6XX / A7XX / A8XX) GPU Drivers** (alongside VirGL fallbacks).

---

## 🚀 How to Run in Termux

### Step 1: Open Termux & Prepare Files
Extract/Place the files into your Termux home directory:
```bash
cd ~
chmod +x setup.sh uninstall.sh scripts/*.sh
```

### Step 2: Launch Installer
Run the setup script directly as your standard Termux user (**Do NOT run with sudo!** The script intelligently elevates privileges automatically when needed):
```bash
./setup.sh
```

### Step 3: Interactive Setup & Mirror Selection
The script features an advanced setup UI that will guide you through:
1. **Repository Mirror Selection**: Automatically launches `termux-change-repo` so you can select the fastest mirror for your region.
2. **Linux Distribution Selection**: 
   - **Fedora** *(Recommended - Easy to use, excellent driver support)*
   - **Debian** *(Highly stable core)*
   - **Archlinux** *(For advanced rolling-release users)*
3. **Desired Username & Password**
4. **GPU Architecture Fallback**: If it cannot auto-detect your GPU, it will ask you to select between **Adreno 8xx/7xx/6xx** or **VirGL (Mali/PowerVR/Exynos)**.

### Step 4: Launch your Touch Desktop (Do NOT use sudo!)
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
2. **Advanced Adreno GPU Stack**:
   - Accurately detects and maps Qualcomm Adreno GPUs, supporting **6xx**, **7xx**, and the bleeding-edge **8xx Series** (e.g., Snapdragon 8 Elite, 8S Gen 4).
   - Installs the complete official Khronos Vulkan pipeline (`vulkan-loader-generic`, `mesa-vulkan-icd-freedreno`, `mesa-zink`) to bypass generic software rendering.
   - Provides a guaranteed **VirGL** fallback renderer for non-Adreno chipsets (Mali, PowerVR, Exynos Xclipse).
3. **Smart Privilege Dropping**: Setup script safely navigates Termux's root constraints by using `su -c` dropping mechanisms and raw `apt full-upgrade` commands to prevent `pkg` crashes on fresh installs.
4. **Touch-Optimized XFCE4 Environment**:
   - Pre-configures a sleek system-wide Dark Mode scenario (**Arc-Dark GTK theme** & **Papirus-Dark icons**).
   - Bundles the **Onboard Virtual Keyboard** pre-configured to autostart, dock cleanly, and dynamically appear for text input.
5. **Secure DBus & Audio Isolation**: Uses `XDG_RUNTIME_DIR=/tmp/runtime-$USER` inside isolated DBus sessions to guarantee perfectly stable XFCE4 boots every time.

---

## 🧠 For Advanced Users & AI Assistants

If you are a developer, a power user, or an AI assistant (like me!) tasked with debugging or extending this environment, here is the technical blueprint of how everything connects under the hood:

**1. Installation & Boot Architecture**
*   **The Chroot:** This setup completely bypasses PRoot and uses `chroot-distro` (requiring a rooted device) to communicate directly with the Android kernel for maximum bare-metal performance.
*   **Environment Injection:** The base environment variables (like `XDG_RUNTIME_DIR` and DBus socket definitions) are statically generated into `/etc/profile.d/termux_env.sh` during setup. `start_fedora.sh` binds the container and executes the XFCE4 session using `dbus-run-session`.
*   **Display & Audio:** X11 is piped directly to the `Termux:X11` Android app via local sockets (`DISPLAY=:0`). Audio is streamed via TCP to the Termux PulseAudio server (`PULSE_SERVER=tcp:127.0.0.1:4713`).

**2. The GPU Acceleration Stack (Turnip + Zink)**
*   **The Hardware Bridge:** Adreno GPUs (especially the 8xx series like Snapdragon 8s Gen 4 / 8 Elite) use the **Turnip** Vulkan ICD (`freedreno_icd.aarch64.json`). OpenGL is layered on top of Vulkan using the **Zink** gallium driver.
*   **Critical Vulkan/X11 Fix (`MESA_VK_WSI_DEBUG=sw`):** Termux:X11 operates over a socket and cannot natively ingest hardware DMA-BUF surfaces from Turnip. To prevent `CreateSwapchainKHR` and `GLXBadCurrentWindow` crashes in applications, we forcefully inject `MESA_VK_WSI_DEBUG=sw`. This commands Mesa's Window System Integration to utilize a software shared-memory buffer to present the final hardware-rendered frame to X11.
*   **Adreno 8xx Stability:** Modern Adreno chips frequently hang on experimental Turnip drivers. We stabilize them by injecting `TU_DEBUG=kgsl,noconform,sysmem,nolrz`.
*   **Helper Scripts:** The environment generates `/usr/local/bin/enable-zink` and `/usr/local/bin/enable-freedreno` to allow users to hot-swap graphics stacks via bash aliases if an application misbehaves.

**3. Desktop Environment (XFCE4) & Compositing**
*   Because Zink intercepts the OpenGL pipeline globally, it can violently crash if the XFCE window manager attempts to composite shadows and transparencies using unsupported legacy X11 extensions. 
*   We forcefully disable compositing in `xfwm4.xml` and inject a `disable-compositor.desktop` autostart script to guarantee XFCE never tries to render composited effects, protecting the GPU pipeline for actual games/applications.

**4. Native Steam (ARM64 & x86) and Kernel IPC Constraints**
*   **The Emulation Route:** Running x86 games requires FEX-Emu/Box64. This relies on the kernel flag `CONFIG_BINFMT_MISC=y` to automatically catch and translate x86 binaries.
*   **The Native ARM64 Steam Route:** Even if you use a native ARM64 build of the Steam Client, **Steam will fail to launch** (`threadtools.cpp : Assertion Failed: Function not implemented`) on standard Android kernels.
*   **The Kernel Requirement:** Valve's Steam engine intrinsically relies on legacy **System V IPC Semaphores** (`semget`). Android disables this globally for security. You **cannot** bypass this in a true chroot using `LD_PRELOAD` shims (like `libandroid-shmem`, which only handles shared memory, not semaphores). **You MUST flash a custom Android kernel with `CONFIG_SYSVIPC=y` compiled in** if you want Steam to boot.
