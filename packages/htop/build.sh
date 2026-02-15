#!/bin/bash
# Build htop for K1OS

set -e

HTOP_VERSION="3.3.0"
HTOP_URL="https://github.com/htop-dev/htop/releases/download/${HTOP_VERSION}/htop-${HTOP_VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[htop]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[htop]${NC} $1"; }
log_error() { echo -e "${RED}[htop]${NC} $1"; }

check_deps() {
    for dep in gcc make pkg-config; do
        command -v "$dep" &>/dev/null || { log_error "Missing: $dep"; exit 1; }
    done
    pkg-config --exists ncurses 2>/dev/null || {
        log_warn "Install: sudo dnf install ncurses-devel libcap-devel"
        exit 1
    }
}

fetch() {
    if [ ! -f "${PKG_DIR}/htop-${HTOP_VERSION}.tar.xz" ]; then
        log_info "Downloading htop ${HTOP_VERSION}..."
        wget -q --show-progress "${HTOP_URL}" -O "${PKG_DIR}/htop-${HTOP_VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting htop..."
        mkdir -p "${BUILD_DIR}"
        tar -xJf "${PKG_DIR}/htop-${HTOP_VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring htop..."
    cd "${BUILD_DIR}"
    ./configure \
        --prefix=/usr \
        --disable-unicode \
        --silent

    log_info "Building htop..."
    make -j$(nproc) --silent
}

pkg_install() {
    log_info "Installing htop to rootfs..."
    make -C "${BUILD_DIR}" install DESTDIR="${ROOTFS_DIR}" --silent

    # Копируем зависимые библиотеки
    for lib in $(ldd "${ROOTFS_DIR}/usr/bin/htop" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$"); do
        [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done

    log_info "htop installed: $(${ROOTFS_DIR}/usr/bin/htop --version 2>/dev/null | head -1 || echo 'OK')"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && pkg_install ;;
    all)     check_deps && fetch && build && pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
