ROOTFS  ?= ../..
PC_PATH  := $(ROOTFS)/rootfs/usr/lib64/pkgconfig:$(ROOTFS)/rootfs/usr/share/pkgconfig
PROTO_DIR := build/protocol
XDG_SHELL_XML := $(ROOTFS)/rootfs/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
XDG_CLIENT_HEADER := $(PROTO_DIR)/xdg-shell-client-protocol.h
XDG_CLIENT_CODE := $(PROTO_DIR)/xdg-shell-protocol.c

CC      = gcc
CFLAGS  = -O2 -Wall -Wextra -std=c11 -D_GNU_SOURCE -DWLR_USE_UNSTABLE \
           -I$(ROOTFS)/rootfs/usr/include \
           -I$(ROOTFS)/packages/wlroots/build/build/protocol \
           -I$(PROTO_DIR)
SERVER_CFLAGS = $(shell PKG_CONFIG_PATH="$(PC_PATH)" pkg-config --cflags wayland-server wlroots xkbcommon)
SERVER_LDFLAGS = $(shell PKG_CONFIG_PATH="$(PC_PATH)" pkg-config --libs wayland-server wlroots xkbcommon) \
                  -L$(ROOTFS)/rootfs/usr/lib64 -lm
CLIENT_CFLAGS = $(shell PKG_CONFIG_PATH="$(PC_PATH)" pkg-config --cflags wayland-client)
CLIENT_LDFLAGS = $(shell PKG_CONFIG_PATH="$(PC_PATH)" pkg-config --libs wayland-client) \
                  -L$(ROOTFS)/rootfs/usr/lib64

SERVER_SRCS = src/main.c src/server.c
SERVER_OBJS = $(SERVER_SRCS:.c=.o)
CLIENT_SRCS = src/demo-app.c $(XDG_CLIENT_CODE)
CLIENT_OBJS = src/demo-app.o $(PROTO_DIR)/xdg-shell-protocol.o
TARGETS  = k1de-compositor k1de-demo-app

.PHONY: all clean install

all: $(TARGETS)

k1de-compositor: $(SERVER_OBJS)
	$(CC) $(SERVER_OBJS) -o $@ $(SERVER_LDFLAGS) -Wl,-rpath,$(ROOTFS)/rootfs/usr/lib64
	@strip $@ 2>/dev/null || true

k1de-demo-app: $(CLIENT_OBJS)
	$(CC) $(CLIENT_OBJS) -o $@ $(CLIENT_LDFLAGS) -Wl,-rpath,$(ROOTFS)/rootfs/usr/lib64
	@strip $@ 2>/dev/null || true

$(PROTO_DIR):
	mkdir -p $(PROTO_DIR)

$(XDG_CLIENT_HEADER): $(XDG_SHELL_XML) | $(PROTO_DIR)
	wayland-scanner client-header $< $@

$(XDG_CLIENT_CODE): $(XDG_SHELL_XML) | $(PROTO_DIR)
	wayland-scanner private-code $< $@

src/main.o src/server.o: CFLAGS += $(SERVER_CFLAGS)
src/main.o src/server.o: src/k1de.h

src/demo-app.o: CFLAGS += $(CLIENT_CFLAGS)
src/demo-app.o: $(XDG_CLIENT_HEADER)

$(PROTO_DIR)/xdg-shell-protocol.o: CFLAGS += $(CLIENT_CFLAGS)
$(PROTO_DIR)/xdg-shell-protocol.o: $(XDG_CLIENT_HEADER)

src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

$(PROTO_DIR)/%.o: $(PROTO_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

install: $(TARGETS)
	install -Dm755 k1de-compositor $(DESTDIR)/usr/bin/k1de-compositor
	install -Dm755 k1de-demo-app $(DESTDIR)/usr/bin/k1de-demo-app

clean:
	rm -rf $(SERVER_OBJS) $(CLIENT_OBJS) $(TARGETS) build
