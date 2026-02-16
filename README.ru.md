# K1OS - Linux-based Operating System

Язык: [English (основной)](README.md) | Русский

## Обзор

K1OS - это Linux-based операционная система для разработки.

Проект использует Linux kernel как надежную основу (драйверы, планировщик, память, сеть), чтобы не тратить годы на создание собственного ядра с нуля. Основная разработка K1OS сосредоточена на пользовательском пространстве, процессе загрузки, инструментах и интеграции компонентов системы.

K1OS - это не "еще один клон дистрибутива", а самостоятельная операционная система, построенная на базе Linux kernel.

## Основные компоненты

- Linux kernel (`kernel/linux-6.17.9`) как базовый системный слой.
- Минимальный `initramfs` (stage 1) для инициализации ранней загрузки и подготовки real root.
- `system.squashfs` как read-only базовый rootfs.
- `overlayfs` поверх squashfs:
  - `tmpfs` (RAM mode), или
  - `ext4` раздел с меткой `K1OS-DATA` (persistent mode).
- `runit` как init stage 2 (`/sbin/init` внутри rootfs).
- Собранный userspace: `busybox`, `fish`, `curl`, `git`, `dropbear`, `tmux`, `nano`, `python3`, `htop`.
- `warp` (пакетный менеджер K1OS на C) для установки и управления пакетами.

## Архитектура загрузки

1. GRUB загружает `vmlinuz` и `initramfs.gz`.
2. Stage 1 (`rootfs/init`) монтирует `system.squashfs`.
3. Stage 1 настраивает `overlayfs` (persistent или RAM mode).
4. `switch_root` передает управление в `/sbin/init` (stage 2).
5. Stage 2 запускает сервисы и shell-окружение K1OS.

## Структура репозитория

```text
K1OS/
├── kernel/              # Linux kernel source/config
├── rootfs/              # Базовый rootfs и init-скрипты
├── packages/            # Сборка userspace-пакетов + warp
├── scripts/             # Скрипты сборки rootfs/ISO/persist
├── docs/                # Документация проекта
├── custom/              # Опциональные расширения (модули/патчи/утилиты)
├── build/               # Промежуточные артефакты/конфиги
└── Makefile             # Основные цели сборки и запуска
```

## Быстрый старт

```bash
# 1) Ядро
make kernel

# 2) RootFS
make rootfs

# 3) ISO
make iso
```

Полная сборка:

```bash
make all-build
```

Тест в QEMU:

```bash
# RAM mode
make qemu

# persistent storage
make make-persist
make qemu-persist
```

## Дополнительная документация

- Интеграция ядра: [`docs/MIGRATION.md`](docs/MIGRATION.md) | [`docs/MIGRATION.ru.md`](docs/MIGRATION.ru.md)
- Кастомные расширения: [`custom/README.md`](custom/README.md) | [`custom/README.ru.md`](custom/README.ru.md)

## Лицензия

Apache License 2.0 - см. `LICENSE`.
