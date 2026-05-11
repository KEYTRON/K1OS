#!/bin/bash
# Build warp for K1OS from the standalone KEYTRON/WARP repository

set -e

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"
WARP_REPO_URL="${WARP_REPO_URL:-https://github.com/KEYTRON/WARP.git}"
WARP_REPO_REF="${WARP_REPO_REF:-main}"
WARP_SOURCE_DIR="${WARP_SOURCE_DIR:-}"
SOURCE_DIR=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[warp]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[warp]${NC} $1"; }
log_error() { echo -e "${RED}[warp]${NC} $1"; }

check_deps() {
    for dep in gcc curl-config openssl; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "Missing build dependency: $dep"
            log_warn  "Install: sudo dnf install gcc libcurl-devel openssl-devel"
            exit 1
        fi
    done
}

fetch_source() {
    if [ -n "${WARP_SOURCE_DIR}" ] && [ -d "${WARP_SOURCE_DIR}" ]; then
        SOURCE_DIR="$(cd "${WARP_SOURCE_DIR}" && pwd)"
        log_info "Using WARP source from ${SOURCE_DIR}"
        return
    fi

    if [ -d "${ROOT_DIR}/../WARP/.git" ]; then
        SOURCE_DIR="$(cd "${ROOT_DIR}/../WARP" && pwd)"
        log_info "Using sibling WARP checkout at ${SOURCE_DIR}"
        return
    fi

    if ! command -v git &>/dev/null; then
        log_error "Missing build dependency: git"
        log_warn  "Install: sudo dnf install git gcc libcurl-devel openssl-devel"
        exit 1
    fi

    mkdir -p "${BUILD_DIR}"
    if [ ! -d "${BUILD_DIR}/warp-src/.git" ]; then
        log_info "Cloning WARP from ${WARP_REPO_URL} (${WARP_REPO_REF})..."
        git clone --depth 1 --branch "${WARP_REPO_REF}" "${WARP_REPO_URL}" "${BUILD_DIR}/warp-src"
    else
        log_info "Updating cached WARP checkout..."
        git -C "${BUILD_DIR}/warp-src" fetch --depth 1 origin "${WARP_REPO_REF}"
        git -C "${BUILD_DIR}/warp-src" checkout --detach FETCH_HEAD
    fi

    SOURCE_DIR="${BUILD_DIR}/warp-src"
}

build() {
    log_info "Building warp from ${SOURCE_DIR}..."
    make -C "${SOURCE_DIR}" clean 2>/dev/null || true
    make -C "${SOURCE_DIR}" -j"$(nproc)"
    log_info "Build complete: ${SOURCE_DIR}/warp"
}

pkg_install() {
    log_info "Installing warp to rootfs..."
    install -Dm755 "${SOURCE_DIR}/warp" "${ROOTFS_DIR}/usr/bin/warp"
    log_info "warp installed: /usr/bin/warp"
}

case "${1:-all}" in
    build)   check_deps && fetch_source && build ;;
    install) check_deps && fetch_source && build && pkg_install ;;
    all)     check_deps && fetch_source && build && pkg_install ;;
    clean)
        make -C "${PKG_DIR}" clean 2>/dev/null || true
        rm -rf "${BUILD_DIR}/warp-src"
        ;;
    *)
        echo "Usage: $0 [build|install|all|clean]"
        exit 1
        ;;
esac
