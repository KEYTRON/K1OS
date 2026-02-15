#!/bin/bash
# Build K1OS rootfs
# Assembles all components into a bootable root filesystem

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTFS_DIR="${ROOT_DIR}/rootfs"
PACKAGES_DIR="${ROOT_DIR}/packages"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[rootfs]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[rootfs]${NC} $1"; }
log_error() { echo -e "${RED}[rootfs]${NC} $1"; }

create_base_dirs() {
    log_info "Creating base directory structure..."
    mkdir -p "${ROOTFS_DIR}"/{bin,sbin,lib,lib64,usr/{bin,sbin,lib,share},etc,var/{log,run,service},tmp,proc,sys,dev,run,home,root,mnt,opt}
    chmod 1777 "${ROOTFS_DIR}/tmp"
    chmod 700  "${ROOTFS_DIR}/root"
}

create_base_config() {
    log_info "Creating base system configuration..."

    # /etc/passwd
    cat > "${ROOTFS_DIR}/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/usr/bin/fish
nobody:x:99:99:nobody:/:/bin/false
EOF

    # /etc/group
    cat > "${ROOTFS_DIR}/etc/group" << 'EOF'
root:x:0:
nobody:x:99:
wheel:x:10:root
EOF

    # /etc/shadow (root with no password for initial setup)
    cat > "${ROOTFS_DIR}/etc/shadow" << 'EOF'
root::0:0:99999:7:::
nobody:!:0:0:99999:7:::
EOF
    chmod 600 "${ROOTFS_DIR}/etc/shadow"

    # /etc/hostname
    echo "k1os" > "${ROOTFS_DIR}/etc/hostname"

    # /etc/hosts
    cat > "${ROOTFS_DIR}/etc/hosts" << 'EOF'
127.0.0.1   localhost
127.0.1.1   k1os
::1         localhost ip6-localhost ip6-loopback
EOF

    # /etc/shells
    cat > "${ROOTFS_DIR}/etc/shells" << 'EOF'
/bin/sh
/bin/ash
/usr/bin/fish
EOF

    # /etc/profile — base env
    cat > "${ROOTFS_DIR}/etc/profile" << 'EOF'
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export HOME="/root"
export TERM="xterm-256color"
export LANG="en_US.UTF-8"
EOF

    # /etc/issue — login banner
    cat > "${ROOTFS_DIR}/etc/issue" << 'EOF'

  ██╗  ██╗ ██╗ ██████╗ ███████╗
  ██║ ██╔╝███║██╔═══██╗██╔════╝
  █████╔╝ ╚██║██║   ██║███████╗
  ██╔═██╗  ██║██║   ██║╚════██║
  ██║  ██╗ ██║╚██████╔╝███████║
  ╚═╝  ╚═╝ ╚═╝ ╚═════╝ ╚══════╝

  Minimalist Developer OS
  Kernel: \r | \l

EOF

    # /etc/os-release
    cat > "${ROOTFS_DIR}/etc/os-release" << 'EOF'
NAME="K1OS"
VERSION="0.1.0"
ID=k1os
ID_LIKE=linux
PRETTY_NAME="K1OS 0.1.0"
HOME_URL="https://github.com/KEYTRON/K1OS"
EOF
}

create_inittab() {
    log_info "Setting up runit init..."
    # Symlink runit-init as /sbin/init
    ln -sf runit-init "${ROOTFS_DIR}/sbin/init" 2>/dev/null || true
}

build_packages() {
    log_info "Building packages..."

    log_info "  -> BusyBox..."
    bash "${PACKAGES_DIR}/busybox/build.sh" all

    log_info "  -> runit..."
    bash "${PACKAGES_DIR}/runit/build.sh" all

    log_info "  -> fish shell..."
    bash "${PACKAGES_DIR}/fish/build.sh" all
}

main() {
    log_info "Building K1OS rootfs..."
    create_base_dirs
    create_base_config
    create_inittab
    build_packages
    log_info "rootfs build complete: ${ROOTFS_DIR}"
}

main "$@"
