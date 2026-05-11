#ifndef K1DE_H
#define K1DE_H

#include <stdbool.h>
#include <stdlib.h>
#include <time.h>
#include <wayland-server-core.h>
#include <wlr/backend.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_data_device.h>
#include <wlr/types/wlr_input_device.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_matrix.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_pointer.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/log.h>
#include <xkbcommon/xkbcommon.h>

enum k1de_cursor_mode {
	K1DE_CURSOR_PASSTHROUGH,
	K1DE_CURSOR_MOVE,
	K1DE_CURSOR_RESIZE,
};

enum k1de_shell_overlay {
	K1DE_SHELL_OVERLAY_NONE,
	K1DE_SHELL_OVERLAY_MENU,
	K1DE_SHELL_OVERLAY_POWER,
	K1DE_SHELL_OVERLAY_APPS,
	K1DE_SHELL_OVERLAY_CALENDAR,
	K1DE_SHELL_OVERLAY_VOLUME,
	K1DE_SHELL_OVERLAY_LOCK,
};

#define NUM_WORKSPACES 4

struct k1de_server {
	struct wl_display *wl_display;
	struct wlr_backend *backend;
	struct wlr_renderer *renderer;

	struct wlr_xdg_shell *xdg_shell;
	struct wl_listener new_xdg_surface;
	struct wl_list views;

	struct wlr_cursor *cursor;
	struct wlr_xcursor_manager *cursor_mgr;
	struct wl_listener cursor_motion;
	struct wl_listener cursor_motion_absolute;
	struct wl_listener cursor_button;
	struct wl_listener cursor_axis;
	struct wl_listener cursor_frame;

	struct wlr_seat *seat;
	struct wl_listener new_input;
	struct wl_listener request_cursor;
	struct wl_listener request_set_selection;
	struct wl_list keyboards;
	enum k1de_cursor_mode cursor_mode;
	struct k1de_view *grabbed_view;
	double grab_x, grab_y;
	struct wlr_box grab_geobox;
	uint32_t resize_edges;

	struct wlr_output_layout *output_layout;
	struct wl_list outputs;
	struct wl_listener new_output;
	enum k1de_shell_overlay shell_overlay;
	size_t next_window_slot;

	int current_workspace;
	struct k1de_view *workspace_views[NUM_WORKSPACES];
	size_t next_workspace_slot[NUM_WORKSPACES];
	time_t last_time;
	int vol_level;
	int bright_level;
	bool locked;
};

struct k1de_output {
	struct wl_list link;
	struct k1de_server *server;
	struct wlr_output *wlr_output;
	struct wl_listener frame;
};

struct k1de_view {
	struct wl_list link;
	struct k1de_server *server;
	struct wlr_xdg_surface *xdg_surface;
	struct wl_listener map;
	struct wl_listener unmap;
	struct wl_listener destroy;
	struct wl_listener request_move;
	struct wl_listener request_resize;
	bool mapped;
	int x, y;
};

struct k1de_keyboard {
	struct wl_list link;
	struct k1de_server *server;
	struct wlr_input_device *device;
	struct wl_listener modifiers;
	struct wl_listener key;
};

void server_init(struct k1de_server *server, const char *startup_cmd);
void server_run(struct k1de_server *server);
void server_finish(struct k1de_server *server);

#endif
