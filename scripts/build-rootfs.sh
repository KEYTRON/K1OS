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
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"
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
    # После BusyBox — иначе BusyBox перезапишет симлинк своим
    ln -sf runit-init "${ROOTFS_DIR}/sbin/init"
}

create_system_scripts() {
    log_info "Creating system scripts..."

    # login-fish: wrapper для getty — задаёт HOME, cd /root, запускает fish --login
    install -Dm755 /dev/stdin "${ROOTFS_DIR}/sbin/login-fish" << 'EOF'
#!/bin/sh
export HOME=/root
export USER=root
export LOGNAME=root
export SHELL=/usr/bin/fish
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
cd /root
exec /usr/bin/fish --login
EOF

    # reboot / halt / poweroff через runit
    # rm -f сначала — файлы могут быть BusyBox-симлинками на ../bin/busybox
    rm -f "${ROOTFS_DIR}/sbin/reboot" "${ROOTFS_DIR}/sbin/halt" "${ROOTFS_DIR}/sbin/poweroff"

    install -Dm755 /dev/stdin "${ROOTFS_DIR}/sbin/reboot" << 'EOF'
#!/bin/sh
sync
touch /etc/runit/reboot
exec /sbin/runit-init 6
EOF

    install -Dm755 /dev/stdin "${ROOTFS_DIR}/sbin/halt" << 'EOF'
#!/bin/sh
sync
exec /sbin/runit-init 0
EOF

    install -Dm755 /dev/stdin "${ROOTFS_DIR}/sbin/poweroff" << 'EOF'
#!/bin/sh
sync
exec /sbin/runit-init 0
EOF

    # sudo — уже root, просто exec
    install -Dm755 /dev/stdin "${ROOTFS_DIR}/usr/bin/sudo" << 'EOF'
#!/bin/sh
exec "$@"
EOF
}

create_services() {
    log_info "Setting up runit services..."

    # getty на tty0
    mkdir -p "${ROOTFS_DIR}/etc/sv/getty-tty0"
    install -Dm755 /dev/stdin "${ROOTFS_DIR}/etc/sv/getty-tty0/run" << 'EOF'
#!/bin/sh
exec /sbin/getty -n -l /sbin/login-fish 38400 tty0 linux
EOF

    # getty на ttyS0 (serial console)
    mkdir -p "${ROOTFS_DIR}/etc/sv/getty-ttyS0"
    install -Dm755 /dev/stdin "${ROOTFS_DIR}/etc/sv/getty-ttyS0/run" << 'EOF'
#!/bin/sh
exec /sbin/getty -n -l /sbin/login-fish 115200 ttyS0 vt100
EOF

    # Активируем сервисы
    mkdir -p "${ROOTFS_DIR}/var/service"
    ln -sf /etc/sv/getty-tty0  "${ROOTFS_DIR}/var/service/getty-tty0"  2>/dev/null || true
    ln -sf /etc/sv/getty-ttyS0 "${ROOTFS_DIR}/var/service/getty-ttyS0" 2>/dev/null || true
    ln -sf /etc/sv/sshd         "${ROOTFS_DIR}/var/service/sshd"        2>/dev/null || true
}

copy_libs() {
    log_info "Copying shared libraries..."
    mkdir -p "${ROOTFS_DIR}/lib64"

    # Собираем все .so зависимости всех бинарников
    for bin in "${ROOTFS_DIR}/usr/bin/"* "${ROOTFS_DIR}/usr/sbin/"*; do
        [ -f "$bin" ] || continue
        ldd "$bin" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v '^$' | while read lib; do
            [ -f "$lib" ] && cp -n "$lib" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
        done
    done

    # Динамический линкер — обязателен
    cp -f /lib64/ld-linux-x86-64.so.2 "${ROOTFS_DIR}/lib64/"
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
    build_packages
    create_inittab        # после BusyBox — иначе симлинк перезапишется
    create_system_scripts
    create_services
    copy_libs
    log_info "rootfs build complete: ${ROOTFS_DIR}"
}

main "$@"
