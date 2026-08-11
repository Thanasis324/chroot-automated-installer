#!/usr/bin/env bash
# ==============================================================================
# GPU Architecture & Driver Detection Module for Termux Android Environment
# Identifies Qualcomm Adreno (A6XX/A7XX/A8XX), ARM Mali, PowerVR, Exynos Xclipse
# ==============================================================================

detect_adreno_gpu() {
    GPU_MODEL=""
    IS_ADRENO=false
    ADRENO_SERIES="Generic"
    MODEL_NUM=""
    GPU_VENDOR="Generic"
    DRIVER_TYPE="software"

    # Helper function to invoke getprop safely on Android
    get_android_prop() {
        local prop_name="$1"
        local val=""
        if command -v getprop &>/dev/null; then
            val=$(getprop "$prop_name" 2>/dev/null)
        fi
        if [ -z "$val" ] && [ -x "/system/bin/getprop" ]; then
            val=$(/system/bin/getprop "$prop_name" 2>/dev/null)
        fi
        if [ -z "$val" ] && [ -x "/vendor/bin/getprop" ]; then
            val=$(/vendor/bin/getprop "$prop_name" 2>/dev/null)
        fi
        echo "$val"
    }

    # 1. Sysfs Qualcomm KGSL GPU Model Check
    if [ -f "/sys/class/kgsl/kgsl-3d0/gpu_model" ]; then
        GPU_MODEL=$(cat /sys/class/kgsl/kgsl-3d0/gpu_model 2>/dev/null)
    elif [ -f "/sys/class/kgsl/kgsl-3d0/devsys/gpu_model" ]; then
        GPU_MODEL=$(cat /sys/class/kgsl/kgsl-3d0/devsys/gpu_model 2>/dev/null)
    elif [ -f "/sys/class/kgsl/kgsl-3d0/subsys_name" ]; then
        GPU_MODEL=$(cat /sys/class/kgsl/kgsl-3d0/subsys_name 2>/dev/null)
    fi

    # Check for matched platform sysfs nodes
    if [ -z "$GPU_MODEL" ]; then
        for path in /sys/devices/platform/soc/*.qcom,kgsl-3d0/gpu_model; do
            if [ -f "$path" ]; then
                GPU_MODEL=$(cat "$path" 2>/dev/null)
                break
            fi
        done
    fi

    # 2. Android System Properties Gathering
    local PROP_EGL=$(get_android_prop "ro.hardware.egl")
    local PROP_GFX=$(get_android_prop "ro.gfx.driver.0")
    local PROP_SOC=$(get_android_prop "ro.soc.model")
    local PROP_BOARD=$(get_android_prop "ro.board.platform")
    local PROP_HARDWARE=$(get_android_prop "ro.hardware")
    local PROP_CHIP=$(get_android_prop "ro.chipname")

    # Combine collected hardware info
    local ALL_INFO="$GPU_MODEL $PROP_EGL $PROP_GFX $PROP_SOC $PROP_BOARD $PROP_HARDWARE $PROP_CHIP"
    if [ -f "/proc/cpuinfo" ]; then
        ALL_INFO="$ALL_INFO $(grep -i "Hardware" /proc/cpuinfo 2>/dev/null || true)"
    fi

    # 3. Detect Qualcomm Adreno GPU
    if echo "$ALL_INFO" | grep -iq "adreno" || [ -c "/dev/kgsl-3d0" ]; then
        IS_ADRENO=true
        GPU_VENDOR="Qualcomm"
        DRIVER_TYPE="turnip_zink"

        # Attempt to extract numeric model ID (e.g. 650, 730, 740, 830)
        MODEL_NUM=$(echo "$ALL_INFO" | grep -oE "[aA]dreno[[:blank:]]*(\(TM\)|\(R\))?[[:blank:]]*[0-9]+" | grep -oE "[0-9]+" | head -n 1 || true)

        if [ -z "$MODEL_NUM" ]; then
            MODEL_NUM=$(echo "$ALL_INFO" | grep -oE "\b(6[0-9]{2}|7[0-9]{2}|8[0-9]{2})\b" | head -n 1 || true)
        fi

        if [[ "$MODEL_NUM" =~ ^[0-9]+$ ]]; then
            if [ "$MODEL_NUM" -ge 800 ]; then
                ADRENO_SERIES="A8XX"
            elif [ "$MODEL_NUM" -ge 700 ]; then
                ADRENO_SERIES="A7XX"
            elif [ "$MODEL_NUM" -ge 600 ]; then
                ADRENO_SERIES="A6XX"
            else
                ADRENO_SERIES="A6XX"
            fi
        else
            ADRENO_SERIES="A8XX"
            MODEL_NUM="Generic"
        fi
    elif echo "$ALL_INFO" | grep -iq "mali" || [ -c "/dev/mali0" ] || [ -c "/dev/mali" ]; then
        GPU_VENDOR="ARM Mali"
        DRIVER_TYPE="panfrost_sw"
        IS_ADRENO=false
        ADRENO_SERIES="Mali"
        MODEL_NUM=$(echo "$ALL_INFO" | grep -oE "Mali[[:blank:]]*-[GgTt][0-9]+" | head -n 1 || echo "Mali")
    elif echo "$ALL_INFO" | grep -iq "xclipse"; then
        GPU_VENDOR="Samsung Exynos (AMD Xclipse)"
        DRIVER_TYPE="radv_sw"
        IS_ADRENO=false
        ADRENO_SERIES="Xclipse"
        MODEL_NUM="Xclipse"
    elif echo "$ALL_INFO" | grep -iq "powervr" || [ -c "/dev/pvrsrvkm" ]; then
        GPU_VENDOR="PowerVR"
        DRIVER_TYPE="pvr_sw"
        IS_ADRENO=false
        ADRENO_SERIES="PowerVR"
        MODEL_NUM="PowerVR"
    else
        GPU_VENDOR="Generic/Software"
        DRIVER_TYPE="llvmpipe"
        IS_ADRENO=false
        ADRENO_SERIES="Generic"
        MODEL_NUM="Unknown"
    fi

    # Export variables cleanly
    export IS_ADRENO
    export ADRENO_SERIES
    export GPU_VENDOR
    export MODEL_NUM
    export DRIVER_TYPE
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_adreno_gpu
    echo "IS_ADRENO='$IS_ADRENO'"
    echo "ADRENO_SERIES='$ADRENO_SERIES'"
    echo "GPU_VENDOR='$GPU_VENDOR'"
    echo "MODEL_NUM='$MODEL_NUM'"
    echo "DRIVER_TYPE='$DRIVER_TYPE'"
fi
