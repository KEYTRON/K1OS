#define _POSIX_C_SOURCE 200112L
#include <errno.h>
#include <fcntl.h>
#include <linux/input-event-codes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"

#define ARRAY_LENGTH(a) (sizeof(a) / sizeof((a)[0]))
#define DEMO_DEFAULT_WIDTH 760
#define DEMO_DEFAULT_HEIGHT 460
#define DEMO_MIN_WIDTH 420
#define DEMO_MIN_HEIGHT 280

struct demo_buffer {
	struct wl_buffer *buffer;
	void *data;
	size_t size;
	int width;
	int height;
	int stride;
	bool busy;
};

struct demo_app {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct xdg_wm_base *wm_base;
	struct wl_seat *seat;
	struct wl_pointer *pointer;
	struct wl_surface *surface;
	struct xdg_surface *xdg_surface;
	struct xdg_toplevel *toplevel;

	struct demo_buffer buffers[2];

	int width;
	int height;
	bool configured;
	bool running;
	bool needs_redraw;
	bool accent_alt;
	bool pointer_inside;
	bool button_hot;
	double pointer_x;
	double pointer_y;
};

static uint32_t rgb(uint8_t red, uint8_t green, uint8_t blue) {
	return 0xff000000u | ((uint32_t)red << 16) |
		((uint32_t)green << 8) | (uint32_t)blue;
}

static void fill_rect(struct demo_buffer *buffer, int x, int y,
		int width, int height, uint32_t color) {
	if (buffer == NULL || buffer->data == NULL || width <= 0 || height <= 0) {
		return;
	}

	if (x < 0) {
		width += x;
		x = 0;
	}
	if (y < 0) {
		height += y;
		y = 0;
	}
	if (x >= buffer->width || y >= buffer->height) {
		return;
	}
	if (x + width > buffer->width) {
		width = buffer->width - x;
	}
	if (y + height > buffer->height) {
		height = buffer->height - y;
	}
	if (width <= 0 || height <= 0) {
		return;
	}

	uint32_t *pixels = buffer->data;
	for (int row = 0; row < height; ++row) {
		uint32_t *line = pixels + ((y + row) * buffer->width) + x;
		for (int col = 0; col < width; ++col) {
			line[col] = color;
		}
	}
}

static void draw_demo(struct demo_app *app, struct demo_buffer *buffer) {
	uint32_t background = rgb(232, 232, 228);
	uint32_t sidebar = rgb(23, 32, 42);
	uint32_t card = rgb(249, 247, 241);
	uint32_t divider = rgb(211, 214, 214);
	uint32_t accent = app->accent_alt ? rgb(42, 174, 188) : rgb(244, 109, 41);
	uint32_t accent_dim = app->accent_alt ? rgb(28, 138, 151) : rgb(196, 81, 24);
	uint32_t accent_soft = app->accent_alt ? rgb(196, 236, 240) : rgb(252, 224, 204);
	uint32_t success = rgb(148, 191, 83);
	uint32_t warning = rgb(238, 198, 58);
	uint32_t button = app->button_hot ? accent : accent_dim;
	uint32_t button_mark = rgb(22, 26, 31);

	fill_rect(buffer, 0, 0, buffer->width, buffer->height, background);
	fill_rect(buffer, 0, 0, buffer->width, 56, accent);
	fill_rect(buffer, 0, 0, 196, buffer->height, sidebar);
	fill_rect(buffer, 214, 82, buffer->width - 248, 132, card);
	fill_rect(buffer, 214, 232, buffer->width - 248, 78, card);
	fill_rect(buffer, 214, 326, buffer->width - 248, 94, card);

	fill_rect(buffer, 196, 0, 1, buffer->height, divider);
	fill_rect(buffer, 214, 228, buffer->width - 248, 1, divider);
	fill_rect(buffer, 214, 322, buffer->width - 248, 1, divider);

	fill_rect(buffer, 28, 88, 140, 18, accent);
	fill_rect(buffer, 28, 124, 108, 14, rgb(75, 89, 103));
	fill_rect(buffer, 28, 152, 148, 14, rgb(75, 89, 103));
	fill_rect(buffer, 28, 180, 84, 14, rgb(75, 89, 103));

	fill_rect(buffer, 238, 110, buffer->width - 366, 24, accent_soft);
	fill_rect(buffer, 238, 146, 164, 18, accent);
	fill_rect(buffer, 420, 146, 112, 18, success);
	fill_rect(buffer, 238, 250, 128, 18, accent);
	fill_rect(buffer, 238, 278, 188, 12, rgb(117, 130, 145));
	fill_rect(buffer, 238, 342, 140, 18, warning);
	fill_rect(buffer, 390, 342, 188, 18, accent_soft);
	fill_rect(buffer, 238, 370, 236, 12, rgb(117, 130, 145));

	int button_x = 214;
	int button_y = buffer->height - 78;
	fill_rect(buffer, button_x, button_y, 220, 44, button);
	fill_rect(buffer, button_x + 18, button_y + 14, 28, 16, button_mark);
	fill_rect(buffer, button_x + 60, button_y + 14, 88, 16, button_mark);

	fill_rect(buffer, buffer->width - 84, 16, 16, 16, button_mark);
	fill_rect(buffer, buffer->width - 56, 16, 16, 16, button_mark);
}

static int clamp_dimension(int value, int minimum) {
	return value < minimum ? minimum : value;
}

static void destroy_buffer(struct demo_buffer *buffer) {
	if (buffer->buffer != NULL) {
		wl_buffer_destroy(buffer->buffer);
	}
	if (buffer->data != NULL) {
		munmap(buffer->data, buffer->size);
	}
	memset(buffer, 0, sizeof(*buffer));
}

static int create_shm_file(size_t size) {
	char template[] = "/tmp/k1de-demo-XXXXXX";
	int fd = mkstemp(template);
	if (fd < 0) {
		return -1;
	}
	unlink(template);
	if (ftruncate(fd, (off_t)size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static void buffer_handle_release(void *data, struct wl_buffer *wl_buffer) {
	(void)wl_buffer;
	struct demo_buffer *buffer = data;
	buffer->busy = false;
}

static const struct wl_buffer_listener buffer_listener = {
	.release = buffer_handle_release,
};

static struct demo_buffer *create_buffer(struct demo_app *app,
		struct demo_buffer *buffer, int width, int height) {
	int stride = width * 4;
	size_t size = (size_t)stride * (size_t)height;
	int fd = create_shm_file(size);
	if (fd < 0) {
		return NULL;
	}

	void *data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		close(fd);
		return NULL;
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(app->shm, fd, (int)size);
	buffer->buffer = wl_shm_pool_create_buffer(pool, 0, width, height,
		stride, WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);

	if (buffer->buffer == NULL) {
		munmap(data, size);
		memset(buffer, 0, sizeof(*buffer));
		return NULL;
	}

	buffer->data = data;
	buffer->size = size;
	buffer->width = width;
	buffer->height = height;
	buffer->stride = stride;
	buffer->busy = false;
	wl_buffer_add_listener(buffer->buffer, &buffer_listener, buffer);
	return buffer;
}

static struct demo_buffer *get_buffer(struct demo_app *app) {
	for (size_t i = 0; i < ARRAY_LENGTH(app->buffers); ++i) {
		struct demo_buffer *buffer = &app->buffers[i];
		if (buffer->buffer != NULL && !buffer->busy &&
				buffer->width == app->width && buffer->height == app->height) {
			return buffer;
		}
	}

	for (size_t i = 0; i < ARRAY_LENGTH(app->buffers); ++i) {
		struct demo_buffer *buffer = &app->buffers[i];
		if (buffer->buffer != NULL && !buffer->busy) {
			destroy_buffer(buffer);
			return create_buffer(app, buffer, app->width, app->height);
		}
	}

	for (size_t i = 0; i < ARRAY_LENGTH(app->buffers); ++i) {
		struct demo_buffer *buffer = &app->buffers[i];
		if (buffer->buffer == NULL) {
			return create_buffer(app, buffer, app->width, app->height);
		}
	}

	return NULL;
}

static bool inside_toggle_button(struct demo_app *app, double x, double y) {
	return x >= 214 && x < 434 && y >= app->height - 78 && y < app->height - 34;
}

static void update_button_hot(struct demo_app *app) {
	bool hot = app->pointer_inside &&
		inside_toggle_button(app, app->pointer_x, app->pointer_y);
	if (hot != app->button_hot) {
		app->button_hot = hot;
		app->needs_redraw = true;
	}
}

static bool redraw(struct demo_app *app) {
	struct demo_buffer *buffer = get_buffer(app);
	if (buffer == NULL) {
		return false;
	}

	draw_demo(app, buffer);
	wl_surface_attach(app->surface, buffer->buffer, 0, 0);
	wl_surface_damage_buffer(app->surface, 0, 0, app->width, app->height);
	wl_surface_commit(app->surface);
	buffer->busy = true;
	app->needs_redraw = false;
	return true;
}

static void wm_base_ping(void *data, struct xdg_wm_base *wm_base,
		uint32_t serial) {
	(void)data;
	xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
	.ping = wm_base_ping,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface,
		uint32_t serial) {
	struct demo_app *app = data;
	xdg_surface_ack_configure(xdg_surface, serial);
	app->configured = true;
	app->needs_redraw = true;
}

static const struct xdg_surface_listener xdg_surface_listener = {
	.configure = xdg_surface_configure,
};

static void toplevel_configure(void *data, struct xdg_toplevel *xdg_toplevel,
		int32_t width, int32_t height, struct wl_array *states) {
	(void)xdg_toplevel;
	(void)states;
	struct demo_app *app = data;

	if (width > 0) {
		app->width = clamp_dimension(width, DEMO_MIN_WIDTH);
	}
	if (height > 0) {
		app->height = clamp_dimension(height, DEMO_MIN_HEIGHT);
	}
}

static void toplevel_close(void *data, struct xdg_toplevel *xdg_toplevel) {
	(void)xdg_toplevel;
	struct demo_app *app = data;
	app->running = false;
}

static const struct xdg_toplevel_listener toplevel_listener = {
	.configure = toplevel_configure,
	.close = toplevel_close,
};

static void pointer_enter(void *data, struct wl_pointer *pointer,
		uint32_t serial, struct wl_surface *surface,
		wl_fixed_t surface_x, wl_fixed_t surface_y) {
	(void)pointer;
	(void)serial;
	(void)surface;
	struct demo_app *app = data;
	app->pointer_inside = true;
	app->pointer_x = wl_fixed_to_double(surface_x);
	app->pointer_y = wl_fixed_to_double(surface_y);
	update_button_hot(app);
}

static void pointer_leave(void *data, struct wl_pointer *pointer,
		uint32_t serial, struct wl_surface *surface) {
	(void)pointer;
	(void)serial;
	(void)surface;
	struct demo_app *app = data;
	app->pointer_inside = false;
	update_button_hot(app);
}

static void pointer_motion(void *data, struct wl_pointer *pointer,
		uint32_t time, wl_fixed_t surface_x, wl_fixed_t surface_y) {
	(void)pointer;
	(void)time;
	struct demo_app *app = data;
	app->pointer_x = wl_fixed_to_double(surface_x);
	app->pointer_y = wl_fixed_to_double(surface_y);
	update_button_hot(app);
}

static void pointer_button(void *data, struct wl_pointer *pointer,
		uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
	(void)pointer;
	(void)serial;
	(void)time;
	struct demo_app *app = data;
	if (button == BTN_LEFT && state == WL_POINTER_BUTTON_STATE_PRESSED &&
			inside_toggle_button(app, app->pointer_x, app->pointer_y)) {
		app->accent_alt = !app->accent_alt;
		app->needs_redraw = true;
	}
}

static void pointer_axis(void *data, struct wl_pointer *pointer,
		uint32_t time, uint32_t axis, wl_fixed_t value) {
	(void)data;
	(void)pointer;
	(void)time;
	(void)axis;
	(void)value;
}

static void pointer_frame(void *data, struct wl_pointer *pointer) {
	(void)data;
	(void)pointer;
}

static void pointer_axis_source(void *data, struct wl_pointer *pointer,
		uint32_t axis_source) {
	(void)data;
	(void)pointer;
	(void)axis_source;
}

static void pointer_axis_stop(void *data, struct wl_pointer *pointer,
		uint32_t time, uint32_t axis) {
	(void)data;
	(void)pointer;
	(void)time;
	(void)axis;
}

static void pointer_axis_discrete(void *data, struct wl_pointer *pointer,
		uint32_t axis, int32_t discrete) {
	(void)data;
	(void)pointer;
	(void)axis;
	(void)discrete;
}

static void pointer_axis_value120(void *data, struct wl_pointer *pointer,
		uint32_t axis, int32_t value120) {
	(void)data;
	(void)pointer;
	(void)axis;
	(void)value120;
}

static void pointer_axis_relative_direction(void *data,
		struct wl_pointer *pointer, uint32_t axis, uint32_t direction) {
	(void)data;
	(void)pointer;
	(void)axis;
	(void)direction;
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
	.frame = pointer_frame,
	.axis_source = pointer_axis_source,
	.axis_stop = pointer_axis_stop,
	.axis_discrete = pointer_axis_discrete,
	.axis_value120 = pointer_axis_value120,
	.axis_relative_direction = pointer_axis_relative_direction,
};

static void seat_capabilities(void *data, struct wl_seat *seat,
		uint32_t capabilities) {
	struct demo_app *app = data;
	bool has_pointer = (capabilities & WL_SEAT_CAPABILITY_POINTER) != 0;

	if (has_pointer && app->pointer == NULL) {
		app->pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(app->pointer, &pointer_listener, app);
	} else if (!has_pointer && app->pointer != NULL) {
		wl_pointer_destroy(app->pointer);
		app->pointer = NULL;
	}
}

static void seat_name(void *data, struct wl_seat *seat, const char *name) {
	(void)data;
	(void)seat;
	(void)name;
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_capabilities,
	.name = seat_name,
};

static void registry_global(void *data, struct wl_registry *registry,
		uint32_t name, const char *interface, uint32_t version) {
	struct demo_app *app = data;

	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		uint32_t bind_version = version < 4 ? version : 4;
		app->compositor = wl_registry_bind(registry, name,
			&wl_compositor_interface, bind_version);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		app->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
		app->wm_base = wl_registry_bind(registry, name,
			&xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(app->wm_base, &wm_base_listener, app);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		uint32_t bind_version = version < 5 ? version : 5;
		app->seat = wl_registry_bind(registry, name, &wl_seat_interface,
			bind_version);
		wl_seat_add_listener(app->seat, &seat_listener, app);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry,
		uint32_t name) {
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

static void cleanup(struct demo_app *app) {
	for (size_t i = 0; i < ARRAY_LENGTH(app->buffers); ++i) {
		destroy_buffer(&app->buffers[i]);
	}
	if (app->pointer != NULL) {
		wl_pointer_destroy(app->pointer);
	}
	if (app->seat != NULL) {
		wl_seat_destroy(app->seat);
	}
	if (app->toplevel != NULL) {
		xdg_toplevel_destroy(app->toplevel);
	}
	if (app->xdg_surface != NULL) {
		xdg_surface_destroy(app->xdg_surface);
	}
	if (app->surface != NULL) {
		wl_surface_destroy(app->surface);
	}
	if (app->wm_base != NULL) {
		xdg_wm_base_destroy(app->wm_base);
	}
	if (app->shm != NULL) {
		wl_shm_destroy(app->shm);
	}
	if (app->compositor != NULL) {
		wl_compositor_destroy(app->compositor);
	}
	if (app->registry != NULL) {
		wl_registry_destroy(app->registry);
	}
	if (app->display != NULL) {
		wl_display_disconnect(app->display);
	}
}

int main(void) {
	struct demo_app app = {
		.width = DEMO_DEFAULT_WIDTH,
		.height = DEMO_DEFAULT_HEIGHT,
		.running = true,
		.needs_redraw = true,
	};

	app.display = wl_display_connect(NULL);
	if (app.display == NULL) {
		fprintf(stderr, "k1de-demo-app: failed to connect to Wayland display\n");
		return 1;
	}

	app.registry = wl_display_get_registry(app.display);
	wl_registry_add_listener(app.registry, &registry_listener, &app);
	wl_display_roundtrip(app.display);
	wl_display_roundtrip(app.display);

	if (app.compositor == NULL || app.shm == NULL || app.wm_base == NULL) {
		fprintf(stderr, "k1de-demo-app: missing required Wayland globals\n");
		cleanup(&app);
		return 1;
	}

	app.surface = wl_compositor_create_surface(app.compositor);
	app.xdg_surface = xdg_wm_base_get_xdg_surface(app.wm_base, app.surface);
	xdg_surface_add_listener(app.xdg_surface, &xdg_surface_listener, &app);

	app.toplevel = xdg_surface_get_toplevel(app.xdg_surface);
	xdg_toplevel_add_listener(app.toplevel, &toplevel_listener, &app);
	xdg_toplevel_set_title(app.toplevel, "Demo");
	xdg_toplevel_set_app_id(app.toplevel, "k1de-demo");
	wl_surface_commit(app.surface);

	while (app.running) {
		if (app.configured && app.needs_redraw && redraw(&app)) {
			continue;
		}
		if (wl_display_dispatch(app.display) == -1) {
			if (errno != EPIPE) {
				fprintf(stderr, "k1de-demo-app: dispatch failed\n");
			}
			break;
		}
	}

	cleanup(&app);
	return 0;
}
