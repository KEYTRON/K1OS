#!/bin/bash
# Build fish shell for K1OS
# fish: friendly interactive shell — default shell for K1OS

set -e

FISH_VERSION="4.0.1"
FISH_URL="https://github.com/fish-shell/fish-shell/releases/download/${FISH_VERSION}/fish-${FISH_VERSION}.tar.xz"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[fish]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[fish]${NC} $1"; }
log_error() { echo -e "${RED}[fish]${NC} $1"; }

check_deps() {
    local missing=()
    for dep in cmake ninja gcc g++ rustc; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing build dependencies: ${missing[*]}"
        log_warn "Install with: sudo dnf install cmake ninja-build gcc gcc-c++ rust"
        exit 1
    fi
}

fetch() {
    if [ ! -f "${PKG_DIR}/fish-${FISH_VERSION}.tar.xz" ]; then
        log_info "Downloading fish ${FISH_VERSION}..."
        wget -q --show-progress "${FISH_URL}" -O "${PKG_DIR}/fish-${FISH_VERSION}.tar.xz"
    else
        log_info "fish source already downloaded"
    fi

    if [ ! -d "${BUILD_DIR}/src" ]; then
        log_info "Extracting fish..."
        mkdir -p "${BUILD_DIR}/src"
        tar -xJf "${PKG_DIR}/fish-${FISH_VERSION}.tar.xz" -C "${BUILD_DIR}/src" --strip-components=1
    fi
}

build() {
    log_info "Configuring fish with cmake..."
    cmake -S "${BUILD_DIR}/src" \
          -B "${BUILD_DIR}/cmake-build" \
          -G Ninja \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX=/usr \
          -DCMAKE_INSTALL_SYSCONFDIR=/etc

    log_info "Building fish..."
    ninja -C "${BUILD_DIR}/cmake-build" -j$(nproc)
}

install() {
    log_info "Installing fish to rootfs..."
    DESTDIR="${ROOTFS_DIR}" ninja -C "${BUILD_DIR}/cmake-build" install

    # Register fish as a valid shell
    grep -qxF '/usr/bin/fish' "${ROOTFS_DIR}/etc/shells" 2>/dev/null \
        || echo '/usr/bin/fish' >> "${ROOTFS_DIR}/etc/shells"

    log_info "fish installed to ${ROOTFS_DIR}"
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   check_deps && fetch && build ;;
    install) check_deps && fetch && build && install ;;
    all)     check_deps && fetch && build && install ;;
    clean)
        log_info "Cleaning fish build..."
        rm -rf "${BUILD_DIR}"
        ;;
    *)
        echo "Usage: $0 [fetch|build|install|all|clean]"
        exit 1
        ;;
esac
