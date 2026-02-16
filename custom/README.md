# Custom Code & Extensions

Language: English (default) | [Русская версия](README.ru.md)

## Description

This directory is intended for optional K1OS extensions: modules, patches, and helper tools.

Important: K1OS is not built around heavy Linux kernel rework. The default approach is minimal kernel changes and moving product logic into user space and OS integration layers.

## Structure

### modules/
Custom kernel modules for K1OS-specific use cases (when needed).

Each module should include:
- `Makefile` - build configuration
- `*.c` - source files
- `README.md` - module documentation

### patches/
Targeted Linux kernel patches, only when the task cannot be solved through configuration or a user space approach.

Format:

```text
patch-name.patch  - unified diff format
README.md         - rationale and apply instructions
```

### tools/
Utilities for developing, validating, and integrating custom extensions.

## Development

### Create a New Module

```bash
mkdir modules/my_module
cd modules/my_module
# add source files and Makefile
```

### Apply a Patch

```bash
cd kernel
patch -p1 < ../custom/patches/patch-name.patch
```

## License

All code in this directory must be compatible with Apache License 2.0.
