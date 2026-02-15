#!/bin/bash
# Build BusyBox for K1OS userland
# BusyBox provides ~400 Unix utilities in a single binary

set -e

BUSYBOX_VERSION="1.37.0"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[busybox]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[busybox]${NC} $1"; }
log_error() { echo -e "${RED}[busybox]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2" ]; then
        log_info "Downloading BusyBox ${BUSYBOX_VERSION}..."
        wget -q --show-progress "${BUSYBOX_URL}" -O "${PKG_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2"
    else
        log_info "BusyBox source already downloaded"
    fi

    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting BusyBox..."
        mkdir -p "${BUILD_DIR}"
        tar -xjf "${PKG_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring BusyBox (static build)..."
    make -C "${BUILD_DIR}" defconfig
    # Enable static linking (no external libc dependency)
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "${BUILD_DIR}/.config"
    sed -i 's/CONFIG_STATIC=n/CONFIG_STATIC=y/' "${BUILD_DIR}/.config"
    # Disable tc applet (uses CBQ structs removed from newer kernel headers)
    sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' "${BUILD_DIR}/.config"

    log_info "Building BusyBox..."
    make -C "${BUILD_DIR}" -j$(nproc)
}

pkg_install() {
    log_info "Installing BusyBox to rootfs..."
    make -C "${BUILD_DIR}" install CONFIG_PREFIX="${ROOTFS_DIR}"
    log_info "BusyBox installed to ${ROOTFS_DIR}"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   fetch && build ;;
    install) fetch && build && pkg_install ;;
    all)     fetch && build && pkg_install ;;
    clean)
        log_info "Cleaning BusyBox build..."
        rm -rf "${BUILD_DIR}"
        ;;
    *)
        echo "Usage: $0 [fetch|build|install|all|clean]"
        exit 1
        ;;
esac
