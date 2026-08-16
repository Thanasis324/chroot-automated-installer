# Termux Automated Linux Chroot Setup Script

An automated, touch-optimized, and graphically appealing installation script for running **Fedora**, **Debian**, or **Arch Linux** inside **Termux** natively using **`chroot-distro`**. This script integrates **Termux:X11** display output, **PulseAudio** sound, and hardware-accelerated **Qualcomm Adreno Turnip/Zink (A6XX / A7XX / A8XX) GPU Drivers**, alongside **VirGL** (host 3D virtualization for Kernel $\ge$ 4.4), **GL4ES** (standalone OpenGL-to-GLES translation for legacy Kernel 3.x / non-Adreno devices), and **LLVMpipe** (CPU software rendering).

---

> [!NOTE]
> ### 📱 Hardware & Architecture Compatibility
> - **Primary Target**: **64-bit ARM (`arm64` / `aarch64`)** is recommended for modern Turnip Vulkan and Mesa driver pipelines.
> - **32-bit ARM (`armhf` / `arm32`) & Legacy Support**: Devices running in 32-bit mode (such as Adreno 5xx devices forced into 32-bit userland by OEMs, or older Mali/Kernel 3.x devices) are supported via distribution Mesa packages and standalone GL4ES translation.
> - **Bug Reports Welcome**: If you run into issues on 32-bit, Adreno 5xx, or legacy devices, please open an issue so we can continue expanding device compatibility!

---

## 📊 Project Status

- **Debian**: 🟢 Fully supported and tested. Hardware acceleration works flawlessly with all supported GPU pipelines (Turnip/Zink, Freedreno, VirGL, Standalone GL4ES).
- **Fedora**: 🟢 Fully supported and tested. Hardware acceleration works flawlessly with all supported GPU pipelines (Turnip/Zink, Freedreno, VirGL, Standalone GL4ES).
- **Arch Linux**: 🟢 Fully supported and tested. Hardware acceleration works flawlessly with all supported GPU pipelines (Turnip/Zink, Freedreno, VirGL, Standalone GL4ES).
- **Custom Distro**: 🟡 Generally works, but is intended for advanced users (supports importing custom `.tar.gz` rootfs archives with automated touch desktop and GPU configuration).

---

## 🚀 How to Run in Termux

### Prerequisites
- **Termux** app installed. (Download the latest release from [F-Droid](https://f-droid.org/packages/com.termux/) or [GitHub](https://github.com/termux/termux-app/releases))
- **Termux:X11** app installed. (Download the latest nightly release from [GitHub](https://github.com/termux/termux-x11/releases/tag/nightly))
- **Rooted Device** (Required for `chroot-distro`). *Supports [Magisk](https://topjohnwu.github.io/Magisk/) and [KernelSU](https://kernelsu.org/). Root privilege escalation automatically falls back across `sudo`, `tsu`, and native `su`.*
- **Recommended Termux:X11 Settings:**
  1. Output ➔ **Fullscreen**: `on`
  2. Pointer ➔ **Touchscreen input mode**: `Direct touch`
  3. Keyboard ➔ **Show additional keyboard**: `off`

### Installation Guide

#### Step 1: Install Autochroot
Open Termux and run the one-line automated installer:
```bash
curl -sL https://raw.githubusercontent.com/Thanasis324/chroot-automated-installer/main/install.sh | bash
```

After installation finishes, restart your Termux session:
```bash
exit
```

Autochroot installs its managed binaries in `$PREFIX/Chroot-Automated-Installer` and links the global `autochroot` command into your path.

#### Step 2: Run the Installer
Launch setup directly as your standard Termux user (**Do NOT manually run with sudo!** The installer handles privilege elevation cleanly):
```bash
autochroot setup
# Use 'autochroot setup -c' to install a custom rootfs (place custom.tar.gz in ~/):
# autochroot setup -c
```

#### Step 3: Interactive Setup & Configuration
The setup wizard will guide you through:
1. **Repository Mirror Selection**: Automatically launches `termux-change-repo` so you can select the fastest mirror for your region.
2. **Linux Distribution Selection**: 
   - **Debian** *(Recommended - Rock-solid stability, maximum compatibility)*
   - **Fedora** *(Cutting-edge packages and modern stack)*
   - **Arch Linux** *(Rolling-release for advanced users)*
3. **User Account Registration**: Configures your standard non-root username, password, and optional passwordless sudo.
4. **GPU Architecture Detection & Driver Selection**:
   - **Adreno Turnip + Zink** *(Snapdragon A6xx / A7xx / A8xx Vulkan & OpenGL acceleration)*
   - **Adreno Freedreno** *(Native OpenGL driver for older Adreno chips)*
   - **VirGL Hardware Passthrough** *(Host 3D virtualization for Kernel $\ge$ 4.4 on Mali / Tensor / Exynos)*
   - **GL4ES Standalone** *(OpenGL-to-GLES translation for legacy Kernel 3.x / non-Adreno devices without VirGL)*
   - **LLVMpipe** *(CPU software rendering fallback)*

#### Step 4: Launch your Touch Desktop
Once installation is complete, start your system:
1. Open the **Termux:X11** app on your Android device.
2. Return to Termux and launch your desktop session:
   ```bash
   autochroot start
   ```

---

## 🛠️ Post-Install Configuration (`autochroot config`)

If you need to adjust your settings, change drivers, repair packages, or safely remove a distribution, run:

```bash
autochroot config
```

**Available Options:**
1. **Fix / Update GPU Drivers**: Interactive GPU management hub to change your SoC platform, Adreno generation, or graphics backend (Turnip+Zink / Freedreno / VirGL / GL4ES Standalone / LLVMpipe). Includes optional GL4ES source compilation (`ptitSeb/gl4es`) and container Mesa optimization.
2. **Repair Distro Packages & Settings**: Modular repair wizard that lets you selectively:
   - Reinstall and heal core system packages (fixing broken `apt`/`dnf`/`pacman` states).
   - Rebuild X11, Display, and PulseAudio environment configurations.
   - Reconfigure user credentials, passwords, and passwordless sudo privileges.
3. **Manage Passwordless Sudo**: Dynamically toggle whether your Linux user account requires a password for root commands.
4. **Manage Storage / Uninstall**: Cleanly remove individual Linux distributions or completely uninstall autochroot and its components.

---

## 🔄 Keeping Updated (`autochroot update`)

You can check for updates or sync with the latest repository changes at any time:

```bash
# Update to latest stable release
autochroot update

# Sync with latest development branch
autochroot update -d
```

---

## 🌟 Key Features

1. **Near-Native Performance**: Built around `chroot-distro`, allowing Linux to execute directly against the host Linux kernel for near-native CPU and graphics throughput without PRoot emulation overhead.
2. **Plug & Play Gamepad & Controller Support**: Connect gamepads via Bluetooth or USB with automatic detection, rumble (force-feedback), and LED support (Xbox, DualShock/DualSense, Switch Pro, 8BitDo, GameSir).
3. **Comprehensive Graphics Acceleration**:
   - **Snapdragon / Adreno**: Hardware Vulkan (Turnip) and desktop OpenGL (Zink) via `lfdevs/mesa-for-android-container`. Supports Adreno 6xx, 7xx, and 8xx (Snapdragon 8 Gen 4 / 8 Elite).
   - **Mali, Tensor, Exynos, PowerVR (Kernel $\ge$ 4.4)**: VirGL 3D host hardware virtualization over `/tmp/.virgl_test`.
   - **Legacy Devices & Kernel 3.x**: Standalone GL4ES userspace OpenGL $\rightarrow$ OpenGLES translation engine without server socket dependencies.
   - **Universal CPU Fallback**: Optimized LLVMpipe with JIT stability flags (`GALLIVM_PERF=nopt`, `OPENSSL_armcap=0`).
4. **Touch-Optimized Desktop Experience**:
   - Pre-configured Dark Mode XFCE4 desktop.
   - Single-tap execution mode tailored for Android touchscreens.
   - Auto-docking on-screen virtual keyboard (**Onboard**).
   - Dedicated "Shutdown OS" desktop action for safe container unmounting.

---

## 🧠 For Advanced Users & Developers

**1. Container & Process Isolation**
* Bypasses PRoot completely using native `chroot` privilege boundaries.
* Base environment variables and DBus socket definitions are statically populated in `/etc/profile.d/termux_env.sh`.
* X11 is routed to Termux:X11 via `/tmp/.X11-unix` socket mapping, and PulseAudio streams via TCP loopback (`PULSE_SERVER=tcp:127.0.0.1:4713`).

**2. GPU Acceleration Pipelines**
* **Turnip + Zink (`MESA_VK_WSI_DEBUG=sw`)**: Ingests Turnip Vulkan rendering and bridges to X11 via software shared-memory presentation buffers, preventing `CreateSwapchainKHR` crashes.
* **Adreno 8xx Stability**: Stabilized with `TU_DEBUG=kgsl,noconform,nolrz` and KGSL surface patches.
* **VirGL Daemon Management**: Launchers conditionally start `virgl_test_server` and bind `/tmp/.virgl_test` strictly when `RENDERER=virgl`.
* **Standalone GL4ES**: Bypasses VirGL sockets entirely and translates desktop GL calls directly to hardware OpenGLES 2.0. Runner helpers `gl4es-run`, `zink-run`, and `virgl-run` are pre-injected into `/usr/local/bin/`.

**3. Desktop Compositor Safeguards**
* XFCE window compositing is explicitly disabled in `xfwm4.xml` and enforced via `disable-compositor.desktop` to prevent legacy X11 extensions from crashing hardware Vulkan/Zink pipelines.

---

## 🐛 Known Issues & Troubleshooting

**1. "Container is busy" or "/dev/null Permission Denied"**
* **Cause**: Soft reboots (SystemUI or SurfaceFlinger crash) leave kernel chroot mounts orphaned in Android's namespace.
* **Fix**: Perform a full hardware reboot of your Android device to cleanly flush all mount points.

**2. 32-Bit ARM (`armhf`) & OEM-Constrained Devices (e.g. Adreno 5xx)**
* Devices with 32-bit userlands (such as budget Samsung models running 32-bit Android on 64-bit hardware, or Adreno 5xx chips) automatically fall back to standard distribution Mesa packages and standalone GL4ES compilation. If you encounter any bugs on these setups, please report them!

---

## 🙏 Credits & Acknowledgments

* **[chroot-distro](https://github.com/sabamdarif/chroot-distro)**: High-performance native chroot containerization on Android.
* **[Termux](https://termux.dev/) & [Termux:X11](https://github.com/termux/termux-x11)**: Core terminal environment and Android X11 display server.
* **[Mesa Project](https://www.mesa3d.org/)**: Open-source Turnip (Vulkan) and Zink (OpenGL) drivers.
* **[lfdevs/mesa-for-android-container](https://github.com/lfdevs/mesa-for-android-container)**: Optimized Mesa driver builds for Linux containers on Android.
* **[ptitSeb/gl4es](https://github.com/ptitSeb/gl4es)**: OpenGL-to-OpenGLES translation engine for embedded/legacy devices.
* **[VirGL](https://virgil3d.github.io/)**: 3D hardware virtualization passthrough for non-Adreno chipsets.
* **[XFCE](https://xfce.org/)**: Fast, lightweight, touch-friendly desktop environment.
* **[PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/)**: Seamless audio routing between container and host.
* **[Magisk](https://topjohnwu.github.io/Magisk/) & [KernelSU](https://kernelsu.org/)**: Android root privilege management frameworks.
* **[Debian](https://www.debian.org/)**, **[Fedora](https://fedoraproject.org/)**, and **[Arch Linux](https://archlinux.org/)**: Robust base Linux operating systems.
