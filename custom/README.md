# Custom Code & Extensions

## Описание

Этот каталог содержит собственный код, расширения и модификации для Linux kernel.

## Структура

### modules/
Собственные kernel modules, разрабатываемые для проекта K1OS.

Каждый модуль должен содержать:
- `Makefile` - конфигурация сборки
- `*.c` - исходные коды
- `README.md` - документация модуля

### patches/
Патчи, применяемые к Linux kernel для интеграции с собственным кодом.

Формат:
```
patch-name.patch  - unified diff формат
README.md         - описание и инструкции применения
```

### tools/
Утилиты и инструменты для управления и тестирования kernel.

## Разработка

### Создание нового модуля

```bash
mkdir modules/my_module
cd modules/my_module
# Добавить исходные коды и Makefile
```

### Применение патча

```bash
cd kernel
patch -p1 < ../custom/patches/patch-name.patch
```

## Лицензирование

Весь код в этом каталоге должен быть совместим с Apache License 2.0.
