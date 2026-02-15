# K1OS fish configuration
set -gx PATH /usr/local/bin /usr/bin /bin /usr/local/sbin /usr/sbin /sbin
set -gx HOME /root
set -gx TERM xterm-256color
set -gx LANG en_US.UTF-8
set -gx SHELL /usr/bin/fish

# Создаём нужные директории если их нет
if not test -d ~/.config/fish
    command mkdir -p ~/.config/fish/completions ~/.config/fish/conf.d ~/.config/fish/functions
end
