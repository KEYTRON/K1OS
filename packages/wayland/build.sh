#!/bin/bash
# Build wayland library for K1OS
set -e

VERSION="1.23.1"
URL="https://gitlab.freedesktop.org/wayland/wayland/-/releases/${VERSION}/downloads/wayland-${VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[wayland]${NC} $1"; }
log_error() { echo -e "${RED}[wayland]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/wayland-${VERSION}.tar.xz" ]; then
        log_info "Downloading wayland ${VERSION}..."
        wget -q --show-progress "${URL}" -O "${PKG_DIR}/wayland-${VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        mkdir -p "${BUILD_DIR}"
        tar -xf "${PKG_DIR}/wayland-${VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    fetch
    log_info "Configuring wayland..."
    mkdir -p "${BUILD_DIR}/build"
    cd "${BUILD_DIR}/build"
    meson setup .. \
        --prefix=/usr \
        --buildtype=release \
        -Dlibraries=true \
        -Dtests=false \
        -Ddocumentation=false \
        -Ddtd_validation=false
    log_info "Building wayland..."
    ninja -j"$(nproc)"
}

pkg_install() {
    build
    log_info "Installing wayland to rootfs..."
    cd "${BUILD_DIR}/build"
    DESTDIR="${ROOTFS_DIR}" ninja install
    log_info "wayland installed"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   build ;;
    install) pkg_install ;;
    all)     pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
