#!/bin/bash
# Build libxkbcommon for K1OS
set -e

VERSION="1.7.0"
URL="https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-${VERSION}.tar.gz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[xkbcommon]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/xkbcommon-${VERSION}.tar.gz" ]; then
        log_info "Downloading libxkbcommon ${VERSION}..."
        wget -q --show-progress "${URL}" -O "${PKG_DIR}/xkbcommon-${VERSION}.tar.gz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        mkdir -p "${BUILD_DIR}"
        tar -xzf "${PKG_DIR}/xkbcommon-${VERSION}.tar.gz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    fetch
    mkdir -p "${BUILD_DIR}/build"
    cd "${BUILD_DIR}/build"
    meson setup .. \
        --prefix=/usr \
        --buildtype=release \
        -Denable-wayland=true \
        -Denable-x11=false \
        -Denable-docs=false \
        -Denable-bash-completion=false
    ninja -j"$(nproc)"
}

pkg_install() {
    build
    log_info "Installing libxkbcommon..."
    cd "${BUILD_DIR}/build"
    DESTDIR="${ROOTFS_DIR}" ninja install
    log_info "libxkbcommon installed"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   build ;;
    install) pkg_install ;;
    all)     pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
