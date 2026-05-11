#!/bin/bash
# Build wayland-protocols for K1OS
set -e

VERSION="1.36"
URL="https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/${VERSION}/downloads/wayland-protocols-${VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[wl-proto]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/wayland-protocols-${VERSION}.tar.xz" ]; then
        log_info "Downloading wayland-protocols ${VERSION}..."
        wget -q --show-progress "${URL}" -O "${PKG_DIR}/wayland-protocols-${VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        mkdir -p "${BUILD_DIR}"
        tar -xf "${PKG_DIR}/wayland-protocols-${VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    fetch
    mkdir -p "${BUILD_DIR}/build"
    cd "${BUILD_DIR}/build"
    meson setup .. --prefix=/usr --buildtype=release
    ninja -j"$(nproc)"
}

pkg_install() {
    build
    log_info "Installing wayland-protocols..."
    cd "${BUILD_DIR}/build"
    DESTDIR="${ROOTFS_DIR}" ninja install
    log_info "wayland-protocols installed"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   build ;;
    install) pkg_install ;;
    all)     pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
