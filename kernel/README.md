# Linux Kernel Integration

## Описание

Этот каталог содержит Linux kernel, который является основой проекта K1OS.

## Содержимое

- **kernel/** - исходные коды Linux kernel
- **config** - конфигурационные файлы для сборки
- **patches/** - локальные патчи к kernel (если применяются)

## Конфигурация

Kernel конфигурируется для поддержки:
- Базовой функциональности ядра
- Драйверов, необходимых для целевой платформы
- Интеграции с custom code из каталога `custom/`

## Сборка

```bash
# Подготовка конфигурации
make menuconfig

# Компиляция kernel
make -j$(nproc)

# Установка
make install
```

## Версия

Текущая версия kernel: [версия будет указана при добавлении]

## Дополнительные ресурсы

- [Linux Kernel Documentation](https://www.kernel.org/doc/)
- [Kernel Build Guide](https://www.kernel.org/doc/html/latest/kbuild/index.html)
