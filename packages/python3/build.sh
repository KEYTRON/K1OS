#!/bin/bash
# Build Python 3 for K1OS

set -e

PY_VERSION="3.13.2"
PY_URL="https://www.python.org/ftp/python/${PY_VERSION}/Python-${PY_VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[python3]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[python3]${NC} $1"; }
log_error() { echo -e "${RED}[python3]${NC} $1"; }

check_deps() {
    for dep in gcc make pkg-config; do
        command -v "$dep" &>/dev/null || { log_error "Missing: $dep"; exit 1; }
    done
    pkg-config --exists openssl zlib libffi 2>/dev/null || {
        log_warn "Install: sudo dnf install openssl-devel zlib-devel libffi-devel bzip2-devel readline-devel sqlite-devel xz-devel"
        exit 1
    }
}

fetch() {
    if [ ! -f "${PKG_DIR}/Python-${PY_VERSION}.tar.xz" ]; then
        log_info "Downloading Python ${PY_VERSION}..."
        wget -q --show-progress "${PY_URL}" -O "${PKG_DIR}/Python-${PY_VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting Python..."
        mkdir -p "${BUILD_DIR}"
        tar -xJf "${PKG_DIR}/Python-${PY_VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring Python ${PY_VERSION}..."
    cd "${BUILD_DIR}"
    ./configure \
        --prefix=/usr \
        --enable-shared \
        --with-ensurepip=install \
        --with-openssl=/usr \
        --disable-test-modules \
        --without-doc-strings \
        --silent

    log_info "Building Python (this takes a while)..."
    make -j$(nproc) --silent
}

pkg_install() {
    log_info "Installing Python to rootfs..."
    make -C "${BUILD_DIR}" install DESTDIR="${ROOTFS_DIR}" --silent

    # Симлинки
    ln -sf python3 "${ROOTFS_DIR}/usr/bin/python" 2>/dev/null || true
    ln -sf pip3 "${ROOTFS_DIR}/usr/bin/pip" 2>/dev/null || true

    # Копируем зависимые библиотеки
    for lib in $(ldd "${ROOTFS_DIR}/usr/bin/python3" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$"); do
        [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done
    # libpython shared lib
    find "${ROOTFS_DIR}/usr/lib" -name "libpython3*.so*" 2>/dev/null | while read lib; do
        cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done

    log_info "Python installed: $(${ROOTFS_DIR}/usr/bin/python3 --version 2>/dev/null || echo 'OK')"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && pkg_install ;;
    all)     check_deps && fetch && build && pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
