# K1OS — операционная система на ядре K1K

Язык: [English (основной)](README.md) | Русский

[![K1OS on K1K](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-k1k.yml/badge.svg)](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-k1k.yml)
[![K1OS Container](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-image.yml/badge.svg)](https://github.com/KEYTRON/K1OS/actions/workflows/k1os-image.yml)
[![Release](https://img.shields.io/github/v/release/KEYTRON/K1OS?include_prereleases&label=release)](https://github.com/KEYTRON/K1OS/releases)
[![Kernel](https://img.shields.io/badge/kernel-K1K%201.0.0--alpha-blue)](https://github.com/KEYTRON/K1K)
[![WARP](https://img.shields.io/badge/packages-WARP-orange)](https://github.com/KEYTRON/WARP)

Где уже загружается (проверяет CI на каждом пуше, на нашем собственном
раннере):

| Цель | Ядро | Статус |
|------|------|--------|
| QEMU q35, BIOS (Limine) | K1K | boot-тест проходит: 4 CPU, NVMe-диск, сервисы из `/SVC` |
| QEMU q35, UEFI (OVMF) | K1K | boot-тест проходит |
| Контейнер (`ghcr.io/keytron/k1os`) | Linux хоста | smoke-тест: `fish`, `warp` |
| QEMU, GRUB ISO | Linux 7.0 (legacy-профиль) | собирается вручную, не в CI |

## Что такое K1OS

K1OS — наша собственная операционная система, и с первого поколения она
загружается на нашем собственном ядре **[K1K](https://github.com/KEYTRON/K1K)**
— гибридном capability-ядре на Rust: маленькое привилегированное ядро
(планировщик, память, IPC, капабилити), а всё остальное — драйверы, файловая
система, init — изолированные сервисы в ring 3, которые супервизор
перезапускает при падении. Драйвер NVMe, драйвер клавиатуры и файловый сервер
FAT уже работают в ring 3; в образ ядра встроены только они, остальной user
space грузится с диска.

**Linux-профиль** (`KERNEL=linux`) — предыдущее поколение: Linux 7.0,
busybox + runit + fish, `system.squashfs` с overlayfs, GRUB. Он по-прежнему
собирается, и именно его содержит контейнерный образ, потому что user space
K1K пока молод. Профили будут сходиться по мере того, как K1K обрастает
сервисами, нужными K1OS (файловый протокол, сеть, терминал), а WARP начнёт
доставлять бинарники сервисов в `/SVC`.

Пакеты приходят из **[WARP](https://github.com/KEYTRON/WARP)** — нашего
пакетного менеджера (C, подписанные архивы, P2P-зеркала). K1OS собирает его
из соседнего checkout `../WARP` или `WARP_SOURCE_DIR`.

## Сборка

Для K1K-профиля нужны: Rust nightly через `rustup` (checkout K1K пинит точный
тулчейн), `xorriso`, `mtools`, `qemu-system-x86_64`, `make`, `git` и исходники
K1K — соседний checkout `../K1K` или `K1K_SOURCE_DIR`.

```bash
make kernel      # собрать K1K (release) в build/k1k/
make iso         # Limine ISO с брендингом K1OS: build/k1k/k1os-k1k.iso
make disk        # FAT16-диск сервисов (NVMe): build/k1k/k1os-k1k-disk.img
make test        # загрузить ISO headless в QEMU и проверить лог
make qemu        # интерактивный QEMU (KVM, 4 CPU, serial в stdio)
```

Legacy Linux-профиль:

```bash
make KERNEL=linux kernel rootfs iso   # часы: компилирует весь userland
make KERNEL=linux qemu
make image                            # контейнер из собранного rootfs
```

## Архитектура загрузки (K1K-профиль)

1. Limine загружает ядро K1K (`/boot/k1k` на ISO), BIOS или UEFI.
2. Ядро поднимает память, SMP, ACPI/APIC и запускает встроенные сервисы:
   `kbd`, `blk` (NVMe), `fs`, плюс IPC-демо `ping`/`pong`.
3. `fs` монтирует FAT16-том на NVMe-диске через `blk` и через `spawn`
   поднимает каждый ELF из `/SVC` как сервис под супервизором.
4. Упавший сервис сносится и перезапускается из образа — без перезагрузки.

Legacy-профиль: GRUB → `vmlinuz` + `initramfs.gz` → `system.squashfs` +
overlayfs (`tmpfs` или ext4-раздел `K1OS-DATA`) → `switch_root` → runit.

## Структура репозитория

```text
K1OS/
├── scripts/build-k1k.sh # K1K-профиль: синк исходников ядра, сборка, ISO, диск, тест
├── ci/runner/           # self-hosted раннеры лабы (Docker) для всех репо K1
├── kernel/              # Исходники/конфиг Linux (legacy-профиль)
├── rootfs/              # Linux rootfs и init-скрипты (legacy-профиль, контейнер)
├── packages/            # Сборка userspace-пакетов + warp
├── scripts/             # Скрипты сборки rootfs/ISO/persist
├── docs/                # Документация проекта
├── custom/              # Опциональные расширения (модули/патчи/утилиты)
├── build/               # Артефакты сборки (build/k1k/ для K1K-профиля)
├── VERSION              # Версия K1OS
└── Makefile             # Основные цели сборки и запуска (KERNEL=k1k|linux)
```

## CI и релизы

Все workflow выполняются на self-hosted **раннерах лабы K1** (`ci/runner/`):
хостовые раннеры GitHub не умеют грузить нашу ОС, а каждый джоб там жжёт
минуты. У раннеров есть KVM, Docker, Rust и доступ только на чтение к
checkout'ам лабы — так K1OS собирает приватный репозиторий K1K.

- `K1OS on K1K` — собирает ядро, ISO и диск, прогоняет boot-тест, выкладывает
  носители как артефакты; на теге `v*` публикует GitHub-релиз.
- `K1OS Container` — собирает контейнер из готового rootfs и пушит
  `ghcr.io/keytron/k1os`.

## Дополнительная документация

- Интеграция ядра: [`docs/MIGRATION.md`](docs/MIGRATION.md) | [`docs/MIGRATION.ru.md`](docs/MIGRATION.ru.md)
- Кастомные расширения: [`custom/README.md`](custom/README.md) | [`custom/README.ru.md`](custom/README.ru.md)
- Раннеры лабы: [`ci/runner/README.md`](ci/runner/README.md)

## Лицензия

Apache License 2.0 — см. `LICENSE`.
