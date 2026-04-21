#!/bin/bash
# K1OS make-persist — подготовить диск/образ для персистентного хранилища
#
# Использование:
#   make-persist.sh /dev/sdX        — разметить реальный диск (ОПАСНО!)
#   make-persist.sh persist.qcow2   — создать/разметить qcow2-образ для QEMU
#   make-persist.sh --help

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[persist]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[persist]${NC} $1"; }
log_error() { echo -e "${RED}[persist]${NC} $1"; exit 1; }

usage() {
    echo ""
    echo "K1OS make-persist — создать раздел для персистентного хранилища"
    echo ""
    echo "Использование:"
    echo "  $0 /dev/sdX [size_mb]     — разметить реальный диск"
    echo "  $0 image.qcow2 [size_mb]  — создать qcow2-образ для QEMU (по умолчанию 2048 МБ)"
    echo ""
    echo "Метка раздела: K1OS-DATA (ищется автоматически при загрузке)"
    echo ""
    echo "Пример для QEMU:"
    echo "  $0 persist.qcow2 2048"
    echo "  qemu-system-x86_64 -m 512M -cdrom k1os.iso -hda persist.qcow2 -enable-kvm"
    echo ""
}

if [ "$1" = "--help" ] || [ -z "$1" ]; then
    usage
    exit 0
fi

TARGET="$1"
SIZE_MB="${2:-2048}"

# Проверяем зависимости
for dep in mkfs.ext4 e2label; do
    command -v "$dep" &>/dev/null || log_error "Missing: $dep (install: sudo dnf install e2fsprogs)"
done

setup_qcow2() {
    local img="$1"
    log_info "Создаём qcow2-образ: ${img} (${SIZE_MB} МБ)..."

    command -v qemu-img &>/dev/null || log_error "qemu-img не найден (sudo dnf install qemu-img)"

    # Создаём образ если не существует
    if [ ! -f "$img" ]; then
        qemu-img create -f qcow2 "$img" "${SIZE_MB}M"
    else
        log_warn "Образ уже существует: $img — будет переформатирован"
    fi

    # Конвертируем в raw для форматирования
    local raw_tmp
    raw_tmp="$(mktemp /tmp/k1os-persist-XXXXXX.raw)"
    trap 'rm -f "$raw_tmp"' EXIT

    log_info "Конвертируем в raw для форматирования..."
    qemu-img convert -f qcow2 -O raw "$img" "$raw_tmp"

    log_info "Форматируем ext4 с меткой K1OS-DATA..."
    mkfs.ext4 -F -L "K1OS-DATA" "$raw_tmp"

    log_info "Конвертируем обратно в qcow2..."
    qemu-img convert -f raw -O qcow2 "$raw_tmp" "$img"

    rm -f "$raw_tmp"
    trap - EXIT
    log_info "Готово: $img"
    log_info "Запуск QEMU:"
    echo ""
    echo "  qemu-system-x86_64 -m 512M \\"
    echo "    -cdrom k1os.iso \\"
    echo "    -hda $img \\"
    echo "    -vga virtio -enable-kvm"
    echo ""
}

setup_block_device() {
    local dev="$1"
    [ -b "$dev" ] || log_error "Не блочное устройство: $dev"

    echo ""
    log_warn "ВНИМАНИЕ: Все данные на $dev будут УНИЧТОЖЕНЫ!"
    printf "Продолжить? [y/N] "
    read -r confirm
    [ "$confirm" = "y" ] || [ "$confirm" = "Y" ] || { log_info "Отменено."; exit 0; }

    log_info "Форматируем $dev как ext4 с меткой K1OS-DATA..."
    mkfs.ext4 -F -L "K1OS-DATA" "$dev"
    log_info "Готово: $dev помечен как K1OS-DATA"
    log_info "K1OS автоматически найдёт его при загрузке."
}

# Определяем что делать
if [[ "$TARGET" == *.qcow2 ]] || [[ "$TARGET" == *.img ]]; then
    setup_qcow2 "$TARGET"
elif [ -b "$TARGET" ]; then
    setup_block_device "$TARGET"
elif [[ "$TARGET" == /dev/* ]]; then
    log_error "Устройство не найдено: $TARGET"
else
    # Считаем что это имя нового qcow2 файла
    [[ "$TARGET" != *.qcow2 ]] && TARGET="${TARGET}.qcow2"
    setup_qcow2 "$TARGET"
fi
