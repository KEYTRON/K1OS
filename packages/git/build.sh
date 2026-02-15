#!/bin/bash
# Build git for K1OS

set -e

GIT_VERSION="2.48.1"
GIT_URL="https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[git]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[git]${NC} $1"; }
log_error() { echo -e "${RED}[git]${NC} $1"; }

check_deps() {
    for dep in gcc make autoconf; do
        command -v "$dep" &>/dev/null || { log_error "Missing: $dep"; exit 1; }
    done
    pkg-config --exists openssl zlib libpcre2-8 2>/dev/null || {
        log_warn "Install: sudo dnf install openssl-devel zlib-devel pcre2-devel"
        exit 1
    }
    # curl нужен для git clone по https
    [ -f "${ROOTFS_DIR}/usr/bin/curl" ] || {
        log_warn "curl not in rootfs — build curl first: packages/curl/build.sh"
    }
}

fetch() {
    if [ ! -f "${PKG_DIR}/git-${GIT_VERSION}.tar.xz" ]; then
        log_info "Downloading git ${GIT_VERSION}..."
        wget -q --show-progress "${GIT_URL}" -O "${PKG_DIR}/git-${GIT_VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting git..."
        mkdir -p "${BUILD_DIR}"
        tar -xJf "${PKG_DIR}/git-${GIT_VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring git..."
    cd "${BUILD_DIR}"

    make configure --silent 2>/dev/null || true

    ./configure \
        --prefix=/usr \
        --with-openssl \
        --with-curl \
        --with-libpcre2 \
        --without-tcltk \
        --silent

    log_info "Building git (this takes a while)..."
    make -j$(nproc) \
        NO_TCLTK=1 \
        NO_GETTEXT=1 \
        NO_INSTALL_HARDLINKS=1 \
        CFLAGS="-Uunreachable" \
        --silent
}

install() {
    log_info "Installing git to rootfs..."
    make -C "${BUILD_DIR}" install \
        DESTDIR="${ROOTFS_DIR}" \
        NO_TCLTK=1 \
        NO_GETTEXT=1 \
        --silent

    # Копируем зависимые библиотеки
    for lib in $(ldd "${ROOTFS_DIR}/usr/bin/git" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$"); do
        [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done

    # Базовый git конфиг для K1OS
    cat > "${ROOTFS_DIR}/etc/gitconfig" << 'EOF'
[core]
    editor = vi
    autocrlf = input
[init]
    defaultBranch = main
[color]
    ui = auto
[pull]
    rebase = false
EOF

    log_info "git installed: $(${ROOTFS_DIR}/usr/bin/git --version 2>/dev/null || echo 'OK')"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && install ;;
    all)     check_deps && fetch && build && install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
