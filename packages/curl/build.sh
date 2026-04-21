#!/bin/bash
# Build curl for K1OS

set -e

CURL_VERSION="8.11.0"
CURL_URL="https://curl.se/download/curl-${CURL_VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[curl]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[curl]${NC} $1"; }
log_error() { echo -e "${RED}[curl]${NC} $1"; }

check_deps() {
    for dep in gcc make pkg-config; do
        command -v "$dep" &>/dev/null || { log_error "Missing: $dep"; exit 1; }
    done
    # Нужны openssl и zlib заголовки
    pkg-config --exists openssl zlib 2>/dev/null || {
        log_warn "Install: sudo dnf install openssl-devel zlib-devel"
        exit 1
    }
}

fetch() {
    if [ ! -f "${PKG_DIR}/curl-${CURL_VERSION}.tar.xz" ]; then
        log_info "Downloading curl ${CURL_VERSION}..."
        wget -q --show-progress "${CURL_URL}" -O "${PKG_DIR}/curl-${CURL_VERSION}.tar.xz"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting curl..."
        mkdir -p "${BUILD_DIR}"
        tar -xJf "${PKG_DIR}/curl-${CURL_VERSION}.tar.xz" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring curl..."
    cd "${BUILD_DIR}"
    ./configure \
        --prefix=/usr \
        --with-openssl \
        --with-zlib \
        --enable-ipv6 \
        --enable-unix-sockets \
        --disable-ldap \
        --disable-ldaps \
        --disable-rtsp \
        --disable-dict \
        --disable-telnet \
        --disable-tftp \
        --disable-pop3 \
        --disable-imap \
        --disable-smb \
        --disable-smtp \
        --disable-gopher \
        --without-libidn2 \
        --without-libpsl \
        --silent

    log_info "Building curl..."
    make -j"$(nproc)" --silent
}

pkg_install() {
    log_info "Installing curl to rootfs..."
    make -C "${BUILD_DIR}" install DESTDIR="${ROOTFS_DIR}" --silent

    # Копируем нужные .so
    for lib in $(ldd "${ROOTFS_DIR}/usr/bin/curl" | grep "=>" | awk '{print $3}' | grep -v "^$"); do
        [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    done

    # CA-сертификаты для HTTPS
    mkdir -p "${ROOTFS_DIR}/etc/ssl/certs"
    if [ -f /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem ]; then
        install -m 644 /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem \
           "${ROOTFS_DIR}/etc/ssl/certs/ca-certificates.crt"
        log_info "CA certificates copied"
    fi

    log_info "curl installed: $("${ROOTFS_DIR}"/usr/bin/curl --version 2>/dev/null | head -1 || echo 'OK')"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && pkg_install ;;
    all)     check_deps && fetch && build && pkg_install ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
