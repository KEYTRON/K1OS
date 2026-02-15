#!/bin/bash
# Build nano for K1OS

set -e

NANO_VERSION="8.3"
NANO_URL="https://www.nano-editor.org/dist/v8/nano-${NANO_VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[nano]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[nano]${NC} $1"; }
log_error() { echo -e "${RED}[nano]${NC} $1"; }

check_deps() {
    for dep in gcc make pkg-config; do
        command -v "$dep" &>/dev/null || { log_error "Missing: $dep"; exit 1; }
    done
    pkg-config --exists ncurses 2>/dev/null || {
        log_warn "Install: sudo dnf install ncurses-devel"
        exit 1
    }
}

fetch() {
    if [ ! -f "${PKG_DIR}/nano-${NANO_VERSION}.tar.xz" ]; then
        log_info "Downloading nano ${NANO_VERSION}..."
        wget -q --show-progress "${NANO_URL}" -O "${PKG_DIR}/nano-${NANO_VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting nano..."
        mkdir -p "${BUILD_DIR}"
        tar -xJf "${PKG_DIR}/nano-${NANO_VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring nano..."
    cd "${BUILD_DIR}"
    ./configure \
        --prefix=/usr \
        --enable-color \
        --enable-mouse \
        --disable-nls \
        --silent

    log_info "Building nano..."
    make -j$(nproc) --silent
}

pkg_install() {
    log_info "Installing nano to rootfs..."
    make -C "${BUILD_DIR}" install DESTDIR="${ROOTFS_DIR}" --silent

    # Копируем зависимые библиотеки
    for lib in $(ldd "${ROOTFS_DIR}/usr/bin/nano" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$"); do
        [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done

    # Базовый nanorc
    cat > "${ROOTFS_DIR}/etc/nanorc" << 'EOF'
# K1OS nanorc
set linenumbers
set mouse
set smooth
set tabsize 4
set tabstospaces
set autoindent
set softwrap

# Syntax highlighting (включаем все)
include "/usr/share/nano/*.nanorc"
EOF

    # Симлинк: edit -> nano (удобный алиас)
    ln -sf nano "${ROOTFS_DIR}/usr/bin/edit" 2>/dev/null || true

    log_info "nano installed: $(${ROOTFS_DIR}/usr/bin/nano --version 2>/dev/null | head -1 || echo 'OK')"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && pkg_install ;;
    all)     check_deps && fetch && build && pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
