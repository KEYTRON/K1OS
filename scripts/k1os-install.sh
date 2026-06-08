#!/bin/sh
# K1OS Installer
# Usage: k1os-install /dev/sdX

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[installer]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[installer]${NC} $1"; }
log_error() { echo -e "${RED}[installer]${NC} $1"; exit 1; }

TARGET=$1

if [ -z "$TARGET" ]; then
    echo "Usage: k1os-install /dev/sdX"
    exit 1
fi

if [ ! -b "$TARGET" ]; then
    log_error "Target $TARGET is not a block device."
fi

log_warn "WARNING: All data on $TARGET will be destroyed!"
printf "Continue? [y/N] "
read -r confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    log_info "Aborted."
    exit 0
fi

log_info "Formatting $TARGET..."

ISO_PATH=""
if [ -f "/mnt/boot/k1os.iso" ]; then
    ISO_PATH="/mnt/boot/k1os.iso"
elif [ -b "/dev/cdrom" ]; then
    ISO_PATH="/dev/cdrom"
else
    for dev in /dev/sr*; do
        if [ -b "$dev" ]; then
            ISO_PATH="$dev"
            break
        fi
    done
fi

if [ -z "$ISO_PATH" ] || [ ! -b "$ISO_PATH" -a ! -f "$ISO_PATH" ]; then
    log_error "Could not find K1OS installation media (CD-ROM)."
fi

log_info "Copying K1OS system from $ISO_PATH to $TARGET..."
dd if="$ISO_PATH" of="$TARGET" bs=4M status=progress
sync

log_info "Creating persistent data partition (K1OS-DATA)..."
# isohybrid usually has 1 or 2 partitions. We add partition 3 for data.
echo -e "n\np\n3\n\n\nw\n" | fdisk "$TARGET" >/dev/null 2>&1 || true
sync
sleep 2

PART=""
if [ -b "${TARGET}3" ]; then
    PART="${TARGET}3"
elif [ -b "${TARGET}p3" ]; then
    PART="${TARGET}p3"
fi

if [ -n "$PART" ] && [ -b "$PART" ]; then
    log_info "Formatting $PART as ext4 K1OS-DATA..."
    mkfs.ext4 -F -L "K1OS-DATA" "$PART" >/dev/null 2>&1 || true
    log_info "Installation complete! K1OS is now installed on $TARGET with persistent storage."
    log_info "You can remove the CD-ROM and reboot."
else
    log_warn "Could not create persistent partition automatically."
    log_warn "You can create it manually using fdisk and mkfs.ext4 -L K1OS-DATA"
    log_info "Installation complete! K1OS is now installed on $TARGET."
fi
