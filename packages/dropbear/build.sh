#!/bin/bash
# Build dropbear SSH for K1OS (lightweight SSH client + server)

set -e

DROPBEAR_VERSION="2024.86"
DROPBEAR_URL="https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${PKG_DIR}/../.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
BUILD_DIR="${PKG_DIR}/build"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[dropbear]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[dropbear]${NC} $1"; }
log_error() { echo -e "${RED}[dropbear]${NC} $1"; }

fetch() {
    if [ ! -f "${PKG_DIR}/dropbear-${DROPBEAR_VERSION}.tar.bz2" ]; then
        log_info "Downloading dropbear ${DROPBEAR_VERSION}..."
        wget -q --show-progress "${DROPBEAR_URL}" -O "${PKG_DIR}/dropbear-${DROPBEAR_VERSION}.tar.bz2"
    fi
    if [ ! -d "${BUILD_DIR}" ]; then
        log_info "Extracting dropbear..."
        mkdir -p "${BUILD_DIR}"
        tar -xjf "${PKG_DIR}/dropbear-${DROPBEAR_VERSION}.tar.bz2" -C "${BUILD_DIR}" --strip-components=1
    fi
}

build() {
    log_info "Configuring dropbear..."
    cd "${BUILD_DIR}"
    ./configure \
        --prefix=/usr \
        --disable-zlib \
        --enable-bundled-libtom \
        --silent

    log_info "Building dropbear..."
    make -j$(nproc) PROGRAMS="dropbear dbclient dropbearkey scp" --silent
}

install() {
    log_info "Installing dropbear to rootfs..."
    make -C "${BUILD_DIR}" install \
        DESTDIR="${ROOTFS_DIR}" \
        PROGRAMS="dropbear dbclient dropbearkey scp" \
        --silent

    # ssh → dbclient симлинк
    ln -sf dbclient "${ROOTFS_DIR}/usr/bin/ssh" 2>/dev/null || true

    # Директория для host keys
    mkdir -p "${ROOTFS_DIR}/etc/dropbear"

    # Runit сервис для sshd
    mkdir -p "${ROOTFS_DIR}/etc/sv/sshd"
    cat > "${ROOTFS_DIR}/etc/sv/sshd/run" << 'RUNEOF'
#!/bin/sh
# Генерируем host keys если нет
[ -f /etc/dropbear/dropbear_rsa_host_key ] || \
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
[ -f /etc/dropbear/dropbear_ed25519_host_key ] || \
    dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key

exec dropbear -F -E -p 22
RUNEOF
    chmod +x "${ROOTFS_DIR}/etc/sv/sshd/run"

    log_info "dropbear installed (ssh client: dbclient/ssh, server: dropbear)"
}

setup_service() {
    log_info "Enabling sshd service..."
    ln -sf /etc/sv/sshd "${ROOTFS_DIR}/var/service/sshd" 2>/dev/null || true
}

case "${1:-all}" in
    fetch)   fetch ;;
    build)   fetch && build ;;
    install) fetch && build && install && setup_service ;;
    all)     fetch && build && install && setup_service ;;
    clean)   rm -rf "${BUILD_DIR}" ;;
    *) echo "Usage: $0 [fetch|build|install|all|clean]"; exit 1 ;;
esac
