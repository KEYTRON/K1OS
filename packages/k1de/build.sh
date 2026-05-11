#!/bin/bash
# Build K1DE compositor for K1OS
set -e

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[k1de]${NC} $1"; }
log_error() { echo -e "${RED}[k1de]${NC} $1"; }

check_deps() {
    if ! PKG_CONFIG_PATH="/home/keytron46/git/K1OS/rootfs/usr/lib64/pkgconfig:/home/keytron46/git/K1OS/rootfs/usr/share/pkgconfig" pkg-config --exists wayland-server wayland-client wlroots xkbcommon; then
        log_error "Missing deps. Install wayland, wlroots, libxkbcommon first."
        log_error "Run: make wayland wlroots libxkbcommon"
        exit 1
    fi
    if ! command -v wayland-scanner >/dev/null 2>&1; then
        log_error "Missing wayland-scanner on the build host."
        exit 1
    fi
}

build() {
    check_deps
    log_info "Building K1DE compositor and demo client..."
    make -C "${PKG_DIR}" clean 2>/dev/null || true
    make -C "${PKG_DIR}" -j"$(nproc)"
    log_info "Build complete: ${PKG_DIR}/k1de-compositor ${PKG_DIR}/k1de-demo-app"
}

pkg_install() {
    build
    log_info "Installing K1DE to rootfs..."
    make -C "${PKG_DIR}" install DESTDIR="${ROOTFS_DIR}"
    mkdir -p "${ROOTFS_DIR}/etc/k1de"
    log_info "K1DE installed to ${ROOTFS_DIR}/usr/bin/k1de-compositor and ${ROOTFS_DIR}/usr/bin/k1de-demo-app"
}

case "${1:-all}" in
    build)   build ;;
    install) pkg_install ;;
    all)     pkg_install ;;
    clean)   make -C "${PKG_DIR}" clean ;;
    *) echo "Usage: $0 [build|install|all|clean]"; exit 1 ;;
esac
