#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

export TARGET_ENABLE_CHECKELF=true

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_FIRMWARE=
ONLY_TARGET=
KANG=
SECTION=
CARRIER_SKIP_FILES=()

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        system_ext/etc/permissions/moto-telephony.xml)
            [ "$2" = "" ] && return 0
            sed -i "s#/system/#/system_ext/#" "${2}"
            ;;
        system_ext/priv-app/ims/ims.apk)
            [ "$2" = "" ] && return 0
            apktool_patch "${2}" "$MY_DIR/ims-patches"
            ;;
        vendor/etc/init/android.hardware.nfc@1.2-service-moto.rc)
            [ "$2" = "" ] && return 0
            sed -i "s/class hal/override\n    class hal/" "${2}"
            ;;
        vendor/etc/init/android.hardware.nfc@1.2-service.sec.rc)
            [ "$2" = "" ] && return 0
            sed -i "s/sec/samsung/g" "${2}"
            sed -i "s/class hal/override\n    class hal/" "${2}"
            ;;
        vendor/etc/init/android.hardware.nfc@1.2-service.st-moto.rc)
            [ "$2" = "" ] && return 0
            sed -i "s/class hal/override\n    class hal/" "${2}"
            ;;
        vendor/lib64/camera/components/com.qti.node.gpu.so | \
            vendor/lib64/com.qti.feature2.gs.so | \
            vendor/lib64/com.qti.feature2.rt.so | \
            vendor/lib64/hw/camera.qcom.so | \
            vendor/lib64/hw/com.qti.chi.override.so)
            [ "$2" = "" ] && return 0
            sed -i "s/camera.mot.is.coming.cts/vendor.camera.coming.cts/g" "${2}"
            ;;
        vendor/lib64/vendor.qti.hardware.camera.postproc@1.0-service-impl.so)
            [ "$2" = "" ] && return 0
            hexdump -ve '1/1 "%.2X"' "${2}" | sed "s/130A0094/1F2003D5/g" | xxd -r -p > "${EXTRACT_TMP_DIR}/${1##*/}"
            mv "${EXTRACT_TMP_DIR}/${1##*/}" "${2}"
            ;;
        *)
            return 1
            ;;
        vendor/lib64/sensors.moto.so)
            "${PATCHELF}" --replace-needed "libutils.so" "libutils-v33.so" "${2}"
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

function prepare_firmware() {
    if [ "${SRC}" != "adb" ]; then
        local STAR="${ANDROID_ROOT}"/lineage/scripts/motorola/star.sh
        for IMAGE in bootloader radio; do
            if [ -f "${SRC}/${IMAGE}.img" ]; then
                echo "Extracting Motorola star image ${SRC}/${IMAGE}.img"
                sh "${STAR}" "${SRC}/${IMAGE}.img" "${SRC}"
            fi
        done
    fi
}

if [ -z "${ONLY_FIRMWARE}" ] && [ -z "${ONLY_TARGET}" ]; then
    # Initialize the helper for common device
    setup_vendor "${DEVICE_COMMON}" "${VENDOR_COMMON:-$VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../../${VENDOR}/${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    if [ -z "${ONLY_FIRMWARE}" ]; then
        extract "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

        if [ -f "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files-carriersettings.txt" ]; then
            generate_prop_list_from_image "product.img" "${MY_DIR}/../../proprietary-files-carriersettings.txt" CARRIER_SKIP_FILES carriersettings
            extract "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-files-carriersettings.txt" "${SRC}" "${KANG}" --section "${SECTION}"

            extract_carriersettings
        fi
    fi

    if [ -z "${SECTION}" ] && [ -f "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-firmware.txt" ]; then
        extract_firmware "${MY_DIR}/../../${VENDOR}/${DEVICE}/proprietary-firmware.txt" "${SRC}"
    fi
fi

"${MY_DIR}/setup-makefiles.sh"
