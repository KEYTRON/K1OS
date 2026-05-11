#!/bin/bash
# Build wlroots for K1OS
set -e

VERSION="0.14.1"
URL="https://gitlab.freedesktop.org/swaywm/wlroots/-/archive/${VERSION}/wlroots-${VERSION}.tar.gz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
SOURCE_DIR="${PKG_DIR}/build"
TARBALL="${PKG_DIR}/wlroots-${VERSION}.tar.gz"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[wlroots]${NC} $1"; }
log_error() { echo -e "${RED}[wlroots]${NC} $1"; }

fetch() {
    if [ -f "${SOURCE_DIR}/meson.build" ]; then
        log_info "Using existing wlroots ${VERSION} source tree in ${SOURCE_DIR}"
        return
    fi
    if [ ! -f "${TARBALL}" ]; then
        log_info "Downloading wlroots ${VERSION}..."
        wget -q --show-progress "${URL}" -O "${TARBALL}"
    fi
    if [ ! -d "${SOURCE_DIR}" ]; then
        mkdir -p "${SOURCE_DIR}"
        tar -xzf "${TARBALL}" -C "${SOURCE_DIR}" --strip-components=1
    fi
}

build() {
    fetch
    mkdir -p "${SOURCE_DIR}/build"
    cd "${SOURCE_DIR}/build"
    if [ ! -f build.ninja ]; then
        meson setup .. \
            --prefix=/usr \
            --buildtype=release \
            -Drenderers=gles2 \
            -Dexamples=false \
            -Dxwayland=disabled \
            -Dxcb-errors=disabled \
            -Dwerror=false
    fi
    ninja -j"$(nproc)"
}

pkg_install() {
    build
    log_info "Installing wlroots..."
    cd "${SOURCE_DIR}/build"
    DESTDIR="${ROOTFS_DIR}" ninja install
    log_info "wlroots installed"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   build ;;
    install) pkg_install ;;
    all)     pkg_install ;;
    clean)   rm -rf "${SOURCE_DIR}/build" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
