#define _POSIX_C_SOURCE 200112L
#include "k1de.h"
#include <linux/input-event-codes.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

/* ── Layout ─────────────────────────────────────────────────────────────────*/
#define PANEL_H      32
#define TITLEBAR_H   24
#define BORDER_W      1
#define CLOSE_W      22
#define DOCK_H       56
#define DOCK_ITEM_W  64
#define MAX_DOCK_WIN  5
#define RESIZE_GRIP  16
#define DOCK_RADIUS  10
#define APP_CMD      "k1de-demo-app"
#define SHUTDOWN_CMD "poweroff"
#define REBOOT_CMD   "reboot"

/* ── 5×7 bitmap font, ASCII 32‥90 ──────────────────────────────────────────
   Row encoding: bit4 = left col, bit0 = right col.
   Lowercase a‥z is mapped to A‥Z at render time.              */
#define FW  5
#define FH  7
#define FS  2   /* scale: 1 font px → FS×FS screen px */
static const uint8_t FONT[59][FH] = {
/*32 ' '*/{0x00,0x00,0x00,0x00,0x00,0x00,0x00},
/*33 '!'*/{0x04,0x04,0x04,0x04,0x04,0x00,0x04},
/*34 '"'*/{0x0A,0x0A,0x00,0x00,0x00,0x00,0x00},
/*35 '#'*/{0x0A,0x1F,0x0A,0x0A,0x1F,0x0A,0x00},
/*36 '$'*/{0x04,0x0F,0x14,0x0E,0x05,0x1E,0x04},
/*37 '%'*/{0x18,0x19,0x02,0x04,0x13,0x03,0x00},
/*38 '&'*/{0x0C,0x12,0x14,0x08,0x15,0x12,0x0D},
/*39 '\''*/{0x04,0x04,0x00,0x00,0x00,0x00,0x00},
/*40 '('*/{0x02,0x04,0x08,0x08,0x08,0x04,0x02},
/*41 ')'*/{0x08,0x04,0x02,0x02,0x02,0x04,0x08},
/*42 '*'*/{0x00,0x04,0x15,0x0E,0x15,0x04,0x00},
/*43 '+'*/{0x00,0x04,0x04,0x1F,0x04,0x04,0x00},
/*44 ','*/{0x00,0x00,0x00,0x00,0x06,0x06,0x04},
/*45 '-'*/{0x00,0x00,0x00,0x1F,0x00,0x00,0x00},
/*46 '.'*/{0x00,0x00,0x00,0x00,0x00,0x06,0x00},
/*47 '/'*/{0x01,0x01,0x02,0x04,0x08,0x10,0x10},
/*48 '0'*/{0x0E,0x11,0x13,0x15,0x19,0x11,0x0E},
/*49 '1'*/{0x04,0x0C,0x04,0x04,0x04,0x04,0x0E},
/*50 '2'*/{0x0E,0x11,0x01,0x06,0x08,0x10,0x1F},
/*51 '3'*/{0x0E,0x11,0x01,0x07,0x01,0x11,0x0E},
/*52 '4'*/{0x02,0x06,0x0A,0x12,0x1F,0x02,0x02},
/*53 '5'*/{0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E},
/*54 '6'*/{0x07,0x08,0x10,0x1E,0x11,0x11,0x0E},
/*55 '7'*/{0x1F,0x01,0x02,0x04,0x08,0x08,0x08},
/*56 '8'*/{0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E},
/*57 '9'*/{0x0E,0x11,0x11,0x0F,0x01,0x11,0x0E},
/*58 ':'*/{0x00,0x06,0x06,0x00,0x06,0x06,0x00},
/*59 ';'*/{0x00,0x06,0x06,0x00,0x06,0x04,0x08},
/*60 '<'*/{0x02,0x04,0x08,0x10,0x08,0x04,0x02},
/*61 '='*/{0x00,0x1F,0x00,0x1F,0x00,0x00,0x00},
/*62 '>'*/{0x08,0x04,0x02,0x01,0x02,0x04,0x08},
/*63 '?'*/{0x0E,0x11,0x01,0x06,0x04,0x00,0x04},
/*64 '@'*/{0x0E,0x11,0x17,0x15,0x17,0x10,0x0E},
/*65 'A'*/{0x0E,0x11,0x11,0x1F,0x11,0x11,0x11},
/*66 'B'*/{0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E},
/*67 'C'*/{0x0E,0x11,0x10,0x10,0x10,0x11,0x0E},
/*68 'D'*/{0x1C,0x12,0x11,0x11,0x11,0x12,0x1C},
/*69 'E'*/{0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F},
/*70 'F'*/{0x1F,0x10,0x10,0x1E,0x10,0x10,0x10},
/*71 'G'*/{0x0E,0x11,0x10,0x17,0x11,0x11,0x0F},
/*72 'H'*/{0x11,0x11,0x11,0x1F,0x11,0x11,0x11},
/*73 'I'*/{0x0E,0x04,0x04,0x04,0x04,0x04,0x0E},
/*74 'J'*/{0x07,0x02,0x02,0x02,0x02,0x12,0x0C},
/*75 'K'*/{0x11,0x12,0x14,0x18,0x14,0x12,0x11},
/*76 'L'*/{0x10,0x10,0x10,0x10,0x10,0x10,0x1F},
/*77 'M'*/{0x11,0x1B,0x15,0x15,0x11,0x11,0x11},
/*78 'N'*/{0x11,0x19,0x15,0x13,0x11,0x11,0x11},
/*79 'O'*/{0x0E,0x11,0x11,0x11,0x11,0x11,0x0E},
/*80 'P'*/{0x1E,0x11,0x11,0x1E,0x10,0x10,0x10},
/*81 'Q'*/{0x0E,0x11,0x11,0x11,0x15,0x12,0x0D},
/*82 'R'*/{0x1E,0x11,0x11,0x1E,0x14,0x12,0x11},
/*83 'S'*/{0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E},
/*84 'T'*/{0x1F,0x04,0x04,0x04,0x04,0x04,0x04},
/*85 'U'*/{0x11,0x11,0x11,0x11,0x11,0x11,0x0E},
/*86 'V'*/{0x11,0x11,0x11,0x11,0x11,0x0A,0x04},
/*87 'W'*/{0x11,0x11,0x11,0x15,0x15,0x1B,0x11},
/*88 'X'*/{0x11,0x11,0x0A,0x04,0x0A,0x11,0x11},
/*89 'Y'*/{0x11,0x11,0x0A,0x04,0x04,0x04,0x04},
/*90 'Z'*/{0x1F,0x01,0x02,0x04,0x08,0x10,0x1F},
};

/* ── Render primitives ───────────────────────────────────────────────────────*/
static void render_box(struct k1de_output *out, struct wlr_renderer *r,
		int x, int y, int w, int h, const float c[4]) {
	if (w <= 0 || h <= 0) return;
	struct wlr_box box = {.x=x,.y=y,.width=w,.height=h};
	wlr_render_rect(r, &box, c, out->wlr_output->transform_matrix);
}

static void render_char(struct k1de_output *out, struct wlr_renderer *r,
		int x, int y, char ch, const float col[4]) {
	if (ch >= 'a' && ch <= 'z') ch -= 32;
	if (ch < 32 || ch > 90) return;
	const uint8_t *g = FONT[(int)(ch - 32)];
	for (int row = 0; row < FH; row++) {
		uint8_t bits = g[row];
		for (int ci = 0; ci < FW; ci++) {
			if (bits & (0x10u >> ci))
				render_box(out, r, x + ci*FS, y + row*FS, FS, FS, col);
		}
	}
}

static void render_text(struct k1de_output *out, struct wlr_renderer *r,
		int x, int y, const char *text, const float col[4]) {
	if (!text) return;
	for (const char *p = text; *p; p++, x += (FW+1)*FS)
		render_char(out, r, x, y, *p, col);
}

/* pixel width of n characters */
static int tw(int n) { return n * (FW+1)*FS - FS; }
#define FH_PX  (FH * FS)   /* 14 screen px tall */

/* ── Color palette ──────────────────────────────────────────────────────────*/
static const float C_BG1[]      = {0.180f,0.200f,0.260f,1.00f};
static const float C_BG2[]      = {0.110f,0.120f,0.160f,1.00f};
static const float C_PANEL[]    = {0.120f,0.130f,0.170f,0.95f};
static const float C_PANEL_LN[] = {0.200f,0.200f,0.240f,0.40f};
static const float C_TEAL[]     = {0.180f,0.520f,0.620f,1.00f};
static const float C_TEAL_DIM[] = {0.110f,0.320f,0.380f,1.00f};
static const float C_ORANGE[]   = {0.940f,0.390f,0.150f,1.00f};
static const float C_RED[]      = {0.780f,0.150f,0.150f,1.00f};
static const float C_RED_DIM[]  = {0.550f,0.100f,0.100f,1.00f};
static const float C_DOCK[]     = {0.150f,0.160f,0.200f,0.90f};
static const float C_DOCK_LN[]  = {0.200f,0.210f,0.260f,0.60f};
static const float C_WIN_BAR[]  = {0.140f,0.150f,0.190f,1.00f};
static const float C_WIN_BARF[] = {0.170f,0.180f,0.220f,1.00f};
static const float C_WIN_ACC[]  = {0.180f,0.520f,0.620f,1.00f};
static const float C_WIN_ACCD[] = {0.100f,0.200f,0.240f,1.00f};
static const float C_WIN_BDR[]  = {0.180f,0.190f,0.240f,1.00f};
static const float C_SHADOW[]   = {0.000f,0.000f,0.000f,0.30f};
static const float C_TEXT[]     = {0.950f,0.950f,0.940f,1.00f};
static const float C_TEXT_DIM[] = {0.600f,0.620f,0.680f,1.00f};
static const float C_OVL[]      = {0.080f,0.090f,0.120f,0.92f};
static const float C_CARD[]     = {0.160f,0.170f,0.210f,1.00f};
static const float C_ITEM[]     = {0.200f,0.210f,0.260f,1.00f};

/* ── Shell state ─────────────────────────────────────────────────────────────*/
enum shell_action {
	SA_NONE,
	SA_TOGGLE_MENU,
	SA_TOGGLE_POWER,
	SA_LAUNCH_APP,
	SA_DOCK_FOCUS,
	SA_POWER_OFF,
	SA_REBOOT,
	SA_LOCK,
};

/* forward declarations */
static void begin_interactive(struct k1de_view *view,
		enum k1de_cursor_mode mode, uint32_t edges);

/* ── Geometry helpers ────────────────────────────────────────────────────────*/
static bool pt_in(double px, double py, int x, int y, int w, int h) {
	return px >= x && px < x+w && py >= y && py < y+h;
}

/* launcher button: left side of panel */
static void launcher_geo(int *x, int *y, int *w, int *h) {
	*x=8; *y=6; *w=44; *h=28;
}
/* power button: right side of panel */
static void power_geo(int sw, int *x, int *y, int *w, int *h) {
	*x=sw-52; *y=6; *w=44; *h=28;
}
/* dock strip */
static void dock_geo(int sw, int sh, int *x, int *y, int *w, int *h) {
	int nitems = MAX_DOCK_WIN + 1; /* +1 for the launch "+" slot */
	*w = nitems * DOCK_ITEM_W + 16;
	*x = (sw - *w) / 2;
	*y = sh - DOCK_H;
	*h = DOCK_H;
}
/* individual dock slot (0 = launcher, 1..5 = window slots) */
static void dock_item_geo(int sw, int sh, int idx,
		int *x, int *y, int *w, int *h) {
	int dx, dy, dw, dh;
	dock_geo(sw, sh, &dx, &dy, &dw, &dh);
	*x = dx + 8 + idx * DOCK_ITEM_W;
	*y = dy + 8;
	*w = DOCK_ITEM_W - 8;
	*h = DOCK_H - 16;
}
/* menu panel (left side) */
static void menu_geo(int sh, int *x, int *y, int *w, int *h) {
	*x=0; *y=PANEL_H; *w=224; *h=sh-PANEL_H;
}
static void menu_item_geo(int idx, int *x, int *y, int *w, int *h) {
	*x=12; *y=PANEL_H+16+idx*52; *w=200; *h=44;
}
/* power popup */
static void pow_menu_geo(int sw, int *x, int *y, int *w, int *h) {
	*w=192; *h=144;
	*x=sw-*w-8; *y=PANEL_H+8;
}
static void pow_item_geo(int sw, int idx, int *x, int *y, int *w, int *h) {
	int px, py, pw, ph;
	pow_menu_geo(sw, &px, &py, &pw, &ph);
	*x=px+12; *y=py+12+idx*52; *w=pw-24; *h=40;
}

/* tray icon area: right of power button */
static void tray_geo(int sw, int *x, int *y, int *w, int *h) {
	*w = 160;
	*x = sw - *w - 8;
	*y = 6;
	*h = 28;
}

/* clock in tray */
static void clock_geo(int sw, int *x, int *y, int *w, int *h) {
	int tx, ty, tw, th;
	tray_geo(sw, &tx, &ty, &tw, &th);
	*w = 90;
	*x = tx;
	*y = ty;
	*h = th;
}

/* volume slider in tray */
static void vol_geo(int sw, int *x, int *y, int *w, int *h) {
	int vx, vy, vw, vh;
	tray_geo(sw, &vx, &vy, &vw, &vh);
	*w = 50;
	*x = vx + 95;
	*y = vy + 10;
	*h = 8;
}

/* workspace switcher: above dock */
static void ws_geo(int sw, int sh, int *x, int *y, int *w, int *h) {
	*w = NUM_WORKSPACES * 44 + 8;
	*x = (sw - *w) / 2;
	*y = sh - DOCK_H - 44;
	*h = 36;
}

/* clock click area */
static void trayclock_geo(int sw, int *x, int *y, int *w, int *h) {
	clock_geo(sw, x, y, w, h);
	(*w) += 4;
}

/* volume click area */
static void trayvol_geo(int sw, int *x, int *y, int *w, int *h) {
	vol_geo(sw, x, y, w, h);
	*y -= 2;
	*h += 12;
	*w = 50;
}

/* workspace button */
static void ws_btn_geo(int sw, int sh, int idx, int *x, int *y, int *w, int *h) {
	int wsx, wsy, wsw, wsh;
	ws_geo(sw, sh, &wsx, &wsy, &wsw, &wsh);
	*x = wsx + 4 + idx * 44;
	*y = wsy + 2;
	*w = 40;
	*h = 32;
}

/* lock overlay */
static void lock_overlay_geo(int sw, int sh, int *x, int *y, int *w, int *h) {
	*w=sw; *h=sh;
	*x=0; *y=0;
}

/* ── Shell action hit-testing ────────────────────────────────────────────────*/
static enum shell_action shell_hit(struct k1de_server *server,
		double lx, double ly, int *dock_idx) {
	struct wlr_output *wo =
		wlr_output_layout_output_at(server->output_layout, lx, ly);
	if (!wo) return SA_NONE;
	double ox=0, oy=0;
	wlr_output_layout_output_coords(server->output_layout, wo, &ox, &oy);
	double x = lx-ox, y = ly-oy;
	int sw=0, sh=0;
	wlr_output_effective_resolution(wo, &sw, &sh);

	/* power overlay */
	if (server->shell_overlay == K1DE_SHELL_OVERLAY_POWER) {
		int px, py, pw, ph;
		pow_item_geo(sw, 0, &px, &py, &pw, &ph);
		if (pt_in(x,y,px,py,pw,ph)) return SA_POWER_OFF;
		pow_item_geo(sw, 1, &px, &py, &pw, &ph);
		if (pt_in(x,y,px,py,pw,ph)) return SA_REBOOT;
		pow_item_geo(sw, 2, &px, &py, &pw, &ph);
		if (pt_in(x,y,px,py,pw,ph)) return SA_LOCK;
	}
	/* menu overlay */
	if (server->shell_overlay == K1DE_SHELL_OVERLAY_MENU) {
		int ix, iy, iw, ih;
		menu_item_geo(0, &ix, &iy, &iw, &ih);
		if (pt_in(x,y,ix,iy,iw,ih)) return SA_LAUNCH_APP;
		menu_item_geo(1, &ix, &iy, &iw, &ih);
		if (pt_in(x,y,ix,iy,iw,ih)) return SA_TOGGLE_POWER;
	}

	/* panel launcher */
	int bx, by, bw, bh;
	launcher_geo(&bx, &by, &bw, &bh);
	if (pt_in(x,y,bx,by,bw,bh)) return SA_TOGGLE_MENU;

	/* panel power */
	power_geo(sw, &bx, &by, &bw, &bh);
	if (pt_in(x,y,bx,by,bw,bh)) return SA_TOGGLE_POWER;

	/* dock */
	int n = 0;
	struct k1de_view *view;
	wl_list_for_each(view, &server->views, link) {
		if (!view->mapped) continue;
		if (n >= MAX_DOCK_WIN) break;
		dock_item_geo(sw, sh, n+1, &bx, &by, &bw, &bh);
		if (pt_in(x,y,bx,by,bw,bh)) {
			if (dock_idx) *dock_idx = n;
			return SA_DOCK_FOCUS;
		}
		n++;
	}
	/* dock launcher slot */
	dock_item_geo(sw, sh, 0, &bx, &by, &bw, &bh);
	if (pt_in(x,y,bx,by,bw,bh)) return SA_LAUNCH_APP;

	return SA_NONE;
}

/* ── Shell action handler ────────────────────────────────────────────────────*/
static void spawn_cmd(const char *cmd) {
	if (!cmd || !cmd[0]) return;
	pid_t pid = fork();
	if (pid == 0) { execl("/bin/sh","/bin/sh","-c",cmd,(void*)NULL); _exit(127); }
}

static void focus_view(struct k1de_view *view, struct wlr_surface *surface);

static bool shell_act(struct k1de_server *server, enum shell_action a, int idx) {
	switch (a) {
	case SA_TOGGLE_MENU:
		server->shell_overlay = server->shell_overlay == K1DE_SHELL_OVERLAY_MENU
			? K1DE_SHELL_OVERLAY_NONE : K1DE_SHELL_OVERLAY_MENU;
		return true;
	case SA_TOGGLE_POWER:
		server->shell_overlay = server->shell_overlay == K1DE_SHELL_OVERLAY_POWER
			? K1DE_SHELL_OVERLAY_NONE : K1DE_SHELL_OVERLAY_POWER;
		return true;
	case SA_LAUNCH_APP:
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		spawn_cmd(APP_CMD);
		return true;
	case SA_DOCK_FOCUS: {
		int n = 0;
		struct k1de_view *v;
		wl_list_for_each(v, &server->views, link) {
			if (!v->mapped) continue;
			if (n == idx) {
				server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
				focus_view(v, v->xdg_surface->surface);
				return true;
			}
			n++;
		}
		return true;
	}
	case SA_POWER_OFF:
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		spawn_cmd(SHUTDOWN_CMD);
		return true;
	case SA_REBOOT:
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		spawn_cmd(REBOOT_CMD);
		return true;
	case SA_LOCK:
		server->shell_overlay = K1DE_SHELL_OVERLAY_LOCK;
		return true;
	default: return false;
	}
}

/* ── Rendering ───────────────────────────────────────────────────────────────*/

/* render label centered in a box */
static void render_label(struct k1de_output *out, struct wlr_renderer *r,
		int bx, int by, int bw, int bh,
		const char *text, const float col[4]) {
	int len = (int)strlen(text);
	int tx = bx + (bw - tw(len)) / 2;
	int ty = by + (bh - FH_PX) / 2;
	render_text(out, r, tx, ty, text, col);
}

static void render_shell_bg(struct k1de_output *out, struct wlr_renderer *r,
		int w, int h) {
	/* nice gradient background - dark blue at top, darker at bottom */
	static const float top[] = {0.110f,0.130f,0.180f,1.00f};
	static const float bottom[] = {0.060f,0.070f,0.100f,1.00f};
	render_box(out, r, 0, 0, w, h/2, top);
	render_box(out, r, 0, h/2, w, h/2, bottom);
}

static void render_panel(struct k1de_output *out, struct wlr_renderer *r,
		int w) {
	/* background */
	render_box(out, r, 0, 0, w, PANEL_H, C_PANEL);
	/* bottom separator */
	render_box(out, r, 0, PANEL_H-1, w, 1, C_PANEL_LN);

	/* launcher button */
	int lx, ly, lw, lh;
	launcher_geo(&lx, &ly, &lw, &lh);
	render_box(out, r, lx, ly, lw, lh, C_ORANGE);
	render_label(out, r, lx, ly, lw, lh, "K1", C_BG2);

	/* power button */
	int px, py, pw, ph;
	power_geo(w, &px, &py, &pw, &ph);
	render_box(out, r, px, py, pw, ph, C_RED);
	render_label(out, r, px, py, pw, ph, "PWR", C_TEXT);

	/* clock in panel center */
	int cx, cy, cw, ch;
	clock_geo(w, &cx, &cy, &cw, &ch);
	time_t now = time(NULL);
	struct tm *tm = localtime(&now);
	char time_str[16];
	strftime(time_str, sizeof(time_str), "%H:%M", tm);
	render_text(out, r, cx + (cw - tw(5))/2, cy, time_str, C_TEXT);
}

static void render_dock(struct k1de_output *out, struct wlr_renderer *r,
		int w, int h) {
	int dx, dy, dw, dh;
	dock_geo(w, h, &dx, &dy, &dw, &dh);

	/* dock background with subtle border */
	render_box(out, r, dx, dy, dw, dh, C_DOCK);
	render_box(out, r, dx, dy, dw, 2, C_DOCK_LN);

	/* launcher slot */
	int ix, iy, iw, ih;
	dock_item_geo(w, h, 0, &ix, &iy, &iw, &ih);
	render_box(out, r, ix, iy, iw, ih, C_ITEM);
	render_label(out, r, ix, iy, iw, ih, "+", C_TEXT);

	/* window slots - circular icons */
	int n = 0;
	static const float win_cols[][4] = {
		{0.180f,0.520f,0.620f,1.0f},
		{0.940f,0.390f,0.150f,1.0f},
		{0.275f,0.647f,0.255f,1.0f},
		{0.698f,0.376f,0.749f,1.0f},
		{0.878f,0.769f,0.235f,1.0f},
	};
	struct k1de_view *view;
	wl_list_for_each(view, &out->server->views, link) {
		if (!view->mapped || n >= MAX_DOCK_WIN) break;
		dock_item_geo(w, h, n+1, &ix, &iy, &iw, &ih);

		bool focused = (out->server->views.next == &view->link);
		render_box(out, r, ix, iy, iw, ih,
			focused ? win_cols[n%5] : C_ITEM);

		const char *title = view->xdg_surface->toplevel->title;
		if (!title || !title[0]) title = "App";
		char lbl[5];
		int li = 0;
		for (; title[li] && li < 4; li++) lbl[li] = title[li];
		lbl[li] = '\0';
		render_label(out, r, ix, iy, iw, ih, lbl, C_TEXT);
		n++;
	}
}

static void render_menu_overlay(struct k1de_output *out, struct wlr_renderer *r,
		int w, int h) {
	int mx, my, mw, mh;
	menu_geo(h, &mx, &my, &mw, &mh);
	render_box(out, r, mx, my, mw, mh, C_OVL);
	render_box(out, r, mw, my, 1, mh, C_PANEL_LN);

	/* header */
	render_box(out, r, mx, my, mw, 36, C_CARD);
	render_text(out, r, mx+12, my+11, "APPS", C_TEAL);

	/* categories: System, Graphics, Network, Accessories */
	const char *categories[] = {"SYS", "GFX", "NET", "ACC"};
	const float cat_colors[][4] = {
		{C_TEAL[0], C_TEAL[1], C_TEAL[2], C_TEAL[3]},
		{C_ORANGE[0], C_ORANGE[1], C_ORANGE[2], C_ORANGE[3]},
		{C_WIN_ACC[0], C_WIN_ACC[1], C_WIN_ACC[2], C_WIN_ACC[3]},
		{C_TEXT[0], C_TEXT[1], C_TEXT[2], C_TEXT[3]},
	};
	const char *app_names[] = {"DEMO APP", "DEMO APP", "DEMO APP", "DEMO APP"};

	for (int i = 0; i < 4; i++) {
		int ix, iy, iw, ih;
		menu_item_geo(i, &ix, &iy, &iw, &ih);
		render_box(out, r, ix, iy, iw, ih, C_ITEM);
		render_box(out, r, ix, iy, 3, ih, cat_colors[i]);
		render_text(out, r, ix+12, iy+(ih-FH_PX)/2 - 6, categories[i], cat_colors[i]);
		render_text(out, r, ix+12, iy+(ih-FH_PX)/2 + 8, app_names[i], C_TEXT_DIM);
	}

	(void)w;
}

static void render_power_overlay(struct k1de_output *out, struct wlr_renderer *r,
		int w, int h) {
	int px, py, pw, ph;
	pow_menu_geo(w, &px, &py, &pw, &ph);
	render_box(out, r, px, py, pw, ph, C_OVL);
	render_box(out, r, px, py, pw, 1, C_PANEL_LN);
	render_box(out, r, px, py+ph-1, pw, 1, C_PANEL_LN);

	/* header */
	render_text(out, r, px+12, py+10, "POWER", C_TEXT_DIM);

	/* shutdown */
	int ix, iy, iw, ih;
	pow_item_geo(w, 0, &ix, &iy, &iw, &ih);
	render_box(out, r, ix, iy, iw, ih, C_RED_DIM);
	render_label(out, r, ix, iy, iw, ih, "SHUT DOWN", C_TEXT);

	/* reboot */
	pow_item_geo(w, 1, &ix, &iy, &iw, &ih);
	render_box(out, r, ix, iy, iw, ih, C_ITEM);
	render_label(out, r, ix, iy, iw, ih, "REBOOT", C_TEXT);

	/* lock */
	pow_item_geo(w, 2, &ix, &iy, &iw, &ih);
	render_box(out, r, ix, iy, iw, ih, C_ITEM);
	render_label(out, r, ix, iy, iw, ih, "LOCK", C_TEXT);

	(void)h;
}

static void render_view_frame(struct k1de_output *out, struct wlr_renderer *r,
		struct k1de_view *view) {
	struct wlr_box geo;
	wlr_xdg_surface_get_geometry(view->xdg_surface, &geo);
	if (geo.width <= 0 || geo.height <= 0) return;

	int fx = view->x + geo.x;
	int fy = view->y + geo.y;
	int fw = geo.width;
	int fh = geo.height;

	bool focused = (out->server->views.next == &view->link);

	/* shadow */
	render_box(out, r, fx-8, fy-TITLEBAR_H-8, fw+16, fh+TITLEBAR_H+16, C_SHADOW);

	/* border sides/bottom */
	render_box(out, r, fx-BORDER_W, fy, BORDER_W, fh, C_WIN_BDR);
	render_box(out, r, fx+fw, fy, BORDER_W, fh, C_WIN_BDR);
	render_box(out, r, fx-BORDER_W, fy+fh, fw+2*BORDER_W, BORDER_W, C_WIN_BDR);

	/* titlebar */
	render_box(out, r, fx-BORDER_W, fy-TITLEBAR_H,
		fw+2*BORDER_W, TITLEBAR_H,
		focused ? C_WIN_BARF : C_WIN_BAR);

	/* top accent strip (3px) */
	render_box(out, r, fx-BORDER_W, fy-TITLEBAR_H,
		fw+2*BORDER_W, 3,
		focused ? C_WIN_ACC : C_WIN_ACCD);

	/* title text */
	const char *title = view->xdg_surface->toplevel->title;
	if (!title || !title[0]) title = "Window";
	char buf[13];
	int n = 0;
	for (; title[n] && n < 12; n++) buf[n] = title[n];
	if (n == 12 && title[12]) { buf[9]='.'; buf[10]='.'; buf[11]='.'; n=12; }
	buf[n] = '\0';
	int ty = fy - TITLEBAR_H + (TITLEBAR_H - FH_PX) / 2;
	render_text(out, r, fx+8, ty, buf,
		focused ? C_TEXT : C_TEXT_DIM);

	/* close button */
	int cx = fx + fw - CLOSE_W + BORDER_W;
	int cy = fy - TITLEBAR_H;
	render_box(out, r, cx, cy, CLOSE_W-BORDER_W, TITLEBAR_H, C_RED_DIM);
	/* X glyph */
	render_char(out, r, cx + (CLOSE_W - FW*FS)/2 - 2,
		cy + (TITLEBAR_H - FH_PX)/2, 'X', C_TEXT);

	/* resize grip indicator (3 dots in corner) */
	static const float grip[] = {0.250f,0.270f,0.330f,0.70f};
	for (int i = 0; i < 3; i++)
		render_box(out, r, fx+fw-4-i*5, fy+fh-3, 3, 2, grip);
}

/* ── Surface rendering callback ──────────────────────────────────────────────*/
struct render_data {
	struct wlr_output *output;
	struct wlr_renderer *renderer;
	struct k1de_view *view;
	struct timespec *when;
};

static void render_surface(struct wlr_surface *surface,
		int sx, int sy, void *data) {
	struct render_data *rd = data;
	struct wlr_texture *tex = wlr_surface_get_texture(surface);
	if (!tex) return;

	double ox=0, oy=0;
	wlr_output_layout_output_coords(rd->view->server->output_layout,
		rd->output, &ox, &oy);
	ox += rd->view->x + sx;
	oy += rd->view->y + sy;

	struct wlr_box box = {
		.x = (int)(ox * rd->output->scale),
		.y = (int)(oy * rd->output->scale),
		.width  = (int)(surface->current.width  * rd->output->scale),
		.height = (int)(surface->current.height * rd->output->scale),
	};
	float mat[9];
	enum wl_output_transform tr =
		wlr_output_transform_invert(surface->current.transform);
	wlr_matrix_project_box(mat, &box, tr, 0, rd->output->transform_matrix);
	wlr_render_texture_with_matrix(rd->renderer, tex, mat, 1);
	wlr_surface_send_frame_done(surface, rd->when);
}

/* ── Output frame ────────────────────────────────────────────────────────────*/
static void output_frame(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_output *out = wl_container_of(listener, out, frame);
	struct wlr_renderer *r = out->server->renderer;
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);

	if (!wlr_output_attach_render(out->wlr_output, NULL)) return;
	int w, h;
	wlr_output_effective_resolution(out->wlr_output, &w, &h);
	wlr_renderer_begin(r, w, h);

	render_shell_bg(out, r, w, h);

	/* windows (back to front) */
	struct k1de_view *view;
	wl_list_for_each_reverse(view, &out->server->views, link) {
		if (!view->mapped) continue;
		render_view_frame(out, r, view);
		struct render_data rd = {
			.output=out->wlr_output, .renderer=r,
			.view=view, .when=&now,
		};
		wlr_xdg_surface_for_each_surface(view->xdg_surface, render_surface, &rd);
	}

	render_panel(out, r, w);
	render_dock(out, r, w, h);

	if (out->server->shell_overlay == K1DE_SHELL_OVERLAY_MENU)
		render_menu_overlay(out, r, w, h);
	if (out->server->shell_overlay == K1DE_SHELL_OVERLAY_POWER)
		render_power_overlay(out, r, w, h);

	wlr_output_render_software_cursors(out->wlr_output, NULL);
	wlr_renderer_end(r);
	wlr_output_commit(out->wlr_output);
}

/* ── Output management ───────────────────────────────────────────────────────*/
static void server_new_output(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, new_output);
	struct wlr_output *wo = data;

	if (!wl_list_empty(&wo->modes)) {
		struct wlr_output_mode *mode = wlr_output_preferred_mode(wo);
		wlr_output_set_mode(wo, mode);
		wlr_output_enable(wo, true);
		if (!wlr_output_commit(wo)) return;
	}

	struct k1de_output *output = calloc(1, sizeof(*output));
	output->wlr_output = wo;
	output->server = server;
	output->frame.notify = output_frame;
	wl_signal_add(&wo->events.frame, &output->frame);
	wl_list_insert(&server->outputs, &output->link);
	wlr_output_layout_add_auto(server->output_layout, wo);
}

/* ── Focus ───────────────────────────────────────────────────────────────────*/
static void focus_view(struct k1de_view *view, struct wlr_surface *surface) {
	if (!view) return;
	struct k1de_server *server = view->server;
	struct wlr_seat *seat = server->seat;
	struct wlr_surface *prev = seat->keyboard_state.focused_surface;
	if (prev == surface) return;
	if (prev) {
		struct wlr_xdg_surface *px =
			wlr_xdg_surface_from_wlr_surface(prev);
		wlr_xdg_toplevel_set_activated(px, false);
	}
	struct wlr_keyboard *kb = wlr_seat_get_keyboard(seat);
	wl_list_remove(&view->link);
	wl_list_insert(&server->views, &view->link);
	wlr_xdg_toplevel_set_activated(view->xdg_surface, true);
	if (kb)
		wlr_seat_keyboard_notify_enter(seat, view->xdg_surface->surface,
			kb->keycodes, kb->num_keycodes, &kb->modifiers);
}

/* ── Window helpers ──────────────────────────────────────────────────────────*/
static struct k1de_view *top_view(struct k1de_server *server) {
	struct k1de_view *v;
	wl_list_for_each(v, &server->views, link)
		if (v->mapped) return v;
	return NULL;
}

static void cycle_views(struct k1de_server *server) {
	struct k1de_view *cur = top_view(server);
	if (!cur) return;
	struct k1de_view *next = NULL;
	bool found = false;
	struct k1de_view *v;
	wl_list_for_each(v, &server->views, link) {
		if (!v->mapped) continue;
		if (found) { next = v; break; }
		if (v == cur) found = true;
	}
	if (!next) {
		wl_list_for_each(v, &server->views, link) {
			if (v->mapped && v != cur) { next = v; break; }
		}
	}
	if (!next || next == cur) return;
	focus_view(next, next->xdg_surface->surface);
	wl_list_remove(&cur->link);
	wl_list_insert(server->views.prev, &cur->link);
}

static void close_top(struct k1de_server *server) {
	struct k1de_view *v = top_view(server);
	if (v) wlr_xdg_toplevel_send_close(v->xdg_surface);
}

/* ── Titlebar hit-testing ────────────────────────────────────────────────────*/
static struct k1de_view *titlebar_view_at(struct k1de_server *server,
		double lx, double ly, bool *in_close) {
	struct k1de_view *v;
	wl_list_for_each(v, &server->views, link) {
		if (!v->mapped) continue;
		struct wlr_box geo;
		wlr_xdg_surface_get_geometry(v->xdg_surface, &geo);
		int fx = v->x + geo.x;
		int fy = v->y + geo.y;
		int fw = geo.width;
		if (lx >= fx-BORDER_W && lx < fx+fw+BORDER_W &&
				ly >= fy-TITLEBAR_H && ly < fy) {
			if (in_close)
				*in_close = (lx >= fx+fw-CLOSE_W+BORDER_W);
			return v;
		}
	}
	return NULL;
}

/* ── Cursor + surface hit ────────────────────────────────────────────────────*/
static bool view_at(struct k1de_view *view,
		double lx, double ly,
		struct wlr_surface **surface, double *sx, double *sy) {
	struct wlr_surface *s =
		wlr_xdg_surface_surface_at(view->xdg_surface,
			lx - view->x, ly - view->y, sx, sy);
	if (s) { *surface = s; return true; }
	return false;
}

static struct k1de_view *desktop_view_at(struct k1de_server *server,
		double lx, double ly,
		struct wlr_surface **surface, double *sx, double *sy) {
	struct k1de_view *v;
	wl_list_for_each(v, &server->views, link)
		if (view_at(v, lx, ly, surface, sx, sy)) return v;
	return NULL;
}

/* ── Cursor movement ─────────────────────────────────────────────────────────*/
static void process_cursor_move(struct k1de_server *server) {
	server->grabbed_view->x = (int)(server->cursor->x - server->grab_x);
	server->grabbed_view->y = (int)(server->cursor->y - server->grab_y);
}

static void process_cursor_resize(struct k1de_server *server) {
	struct k1de_view *view = server->grabbed_view;
	double bx = server->cursor->x - server->grab_x;
	double by = server->cursor->y - server->grab_y;
	int nl = server->grab_geobox.x, nr = nl + server->grab_geobox.width;
	int nt = server->grab_geobox.y, nb = nt + server->grab_geobox.height;

	if (server->resize_edges & WLR_EDGE_TOP)
		nt = (int)by < nb-1 ? (int)by : nb-1;
	else if (server->resize_edges & WLR_EDGE_BOTTOM)
		nb = (int)by > nt+1 ? (int)by : nt+1;
	if (server->resize_edges & WLR_EDGE_LEFT)
		nl = (int)bx < nr-1 ? (int)bx : nr-1;
	else if (server->resize_edges & WLR_EDGE_RIGHT)
		nr = (int)bx > nl+1 ? (int)bx : nl+1;

	struct wlr_box geo;
	wlr_xdg_surface_get_geometry(view->xdg_surface, &geo);
	view->x = nl - geo.x;
	view->y = nt - geo.y;
	wlr_xdg_toplevel_set_size(view->xdg_surface, nr-nl, nb-nt);
}

static void process_cursor_motion(struct k1de_server *server, uint32_t time) {
	if (server->cursor_mode == K1DE_CURSOR_MOVE) {
		process_cursor_move(server); return;
	}
	if (server->cursor_mode == K1DE_CURSOR_RESIZE) {
		process_cursor_resize(server); return;
	}
	double sx, sy;
	struct wlr_surface *surface = NULL;
	struct k1de_view *view = desktop_view_at(server,
		server->cursor->x, server->cursor->y, &surface, &sx, &sy);

	/* cursor shape */
	bool on_titlebar = titlebar_view_at(server,
		server->cursor->x, server->cursor->y, NULL) != NULL;
	enum shell_action act = SA_NONE;
	if (!view && !on_titlebar)
		act = shell_hit(server, server->cursor->x, server->cursor->y, NULL);

	const char *cursor_name = "left_ptr";
	if (on_titlebar) cursor_name = "fleur";
	else if (act != SA_NONE) cursor_name = "hand1";

	wlr_xcursor_manager_set_cursor_image(server->cursor_mgr,
		cursor_name, server->cursor);

	if (surface) {
		wlr_seat_pointer_notify_enter(server->seat, surface, sx, sy);
		if (server->seat->pointer_state.focused_surface == surface)
			wlr_seat_pointer_notify_motion(server->seat, time, sx, sy);
	} else {
		wlr_seat_pointer_clear_focus(server->seat);
	}
}

static void server_cursor_motion(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, cursor_motion);
	struct wlr_event_pointer_motion *ev = data;
	wlr_cursor_move(server->cursor, ev->device, ev->delta_x, ev->delta_y);
	process_cursor_motion(server, ev->time_msec);
}

static void server_cursor_motion_absolute(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, cursor_motion_absolute);
	struct wlr_event_pointer_motion_absolute *ev = data;
	wlr_cursor_warp_absolute(server->cursor, ev->device, ev->x, ev->y);
	process_cursor_motion(server, ev->time_msec);
}

static void server_cursor_button(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, cursor_button);
	struct wlr_event_pointer_button *ev = data;

	if (ev->state == WLR_BUTTON_RELEASED) {
		if (server->cursor_mode != K1DE_CURSOR_PASSTHROUGH)
			server->cursor_mode = K1DE_CURSOR_PASSTHROUGH;
		else
			wlr_seat_pointer_notify_button(server->seat,
				ev->time_msec, ev->button, ev->state);
		return;
	}

	if (ev->button != BTN_LEFT) {
		wlr_seat_pointer_notify_button(server->seat,
			ev->time_msec, ev->button, ev->state);
		return;
	}

	double sx, sy;
	struct wlr_surface *surface = NULL;
	struct k1de_view *view = desktop_view_at(server,
		server->cursor->x, server->cursor->y, &surface, &sx, &sy);

	/* 1. check compositor titlebar/close */
	bool in_close = false;
	struct k1de_view *fview = titlebar_view_at(server,
		server->cursor->x, server->cursor->y, &in_close);
	if (fview) {
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		focus_view(fview, fview->xdg_surface->surface);
		if (in_close) {
			wlr_xdg_toplevel_send_close(fview->xdg_surface);
		} else {
			begin_interactive(fview, K1DE_CURSOR_MOVE, 0);
		}
		return;
	}

	/* 2. client surface click */
	if (view) {
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		focus_view(view, surface);

		/* resize grip: bottom-right corner */
		struct wlr_box geo;
		wlr_xdg_surface_get_geometry(view->xdg_surface, &geo);
		if (sx >= geo.width - RESIZE_GRIP && sy >= geo.height - RESIZE_GRIP) {
			begin_interactive(view, K1DE_CURSOR_RESIZE,
				WLR_EDGE_BOTTOM | WLR_EDGE_RIGHT);
			return;
		}
		wlr_seat_pointer_notify_button(server->seat,
			ev->time_msec, ev->button, ev->state);
		return;
	}

	/* 3. shell hit */
	int dock_idx = 0;
	enum shell_action act = shell_hit(server,
		server->cursor->x, server->cursor->y, &dock_idx);
	if (!shell_act(server, act, dock_idx))
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
	wlr_seat_pointer_clear_focus(server->seat);
}

static void server_cursor_axis(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, cursor_axis);
	struct wlr_event_pointer_axis *ev = data;
	wlr_seat_pointer_notify_axis(server->seat, ev->time_msec,
		ev->orientation, ev->delta, ev->delta_discrete, ev->source);
}

static void server_cursor_frame(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_server *server = wl_container_of(listener, server, cursor_frame);
	wlr_seat_pointer_notify_frame(server->seat);
}

/* ── Keyboard ────────────────────────────────────────────────────────────────*/
static void keyboard_handle_modifiers(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_keyboard *kb = wl_container_of(listener, kb, modifiers);
	wlr_seat_set_keyboard(kb->server->seat, kb->device);
	wlr_seat_keyboard_notify_modifiers(kb->server->seat,
		&kb->device->keyboard->modifiers);
}

static bool handle_keybinding(struct k1de_server *server, xkb_keysym_t sym) {
	switch (sym) {
	case XKB_KEY_Escape:
		if (server->shell_overlay != K1DE_SHELL_OVERLAY_NONE) {
			server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		} else {
			wl_display_terminate(server->wl_display);
		}
		return true;
	case XKB_KEY_Return: case XKB_KEY_KP_Enter:
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		spawn_cmd(APP_CMD);
		return true;
	case XKB_KEY_space:
	case XKB_KEY_F10:
		server->shell_overlay = server->shell_overlay == K1DE_SHELL_OVERLAY_MENU
			? K1DE_SHELL_OVERLAY_NONE : K1DE_SHELL_OVERLAY_MENU;
		return true;
	case XKB_KEY_Tab: case XKB_KEY_F1:
		server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
		cycle_views(server);
		return true;
	case XKB_KEY_F4: case XKB_KEY_q:
		close_top(server);
		return true;
	case XKB_KEY_F11:
		server->shell_overlay = server->shell_overlay == K1DE_SHELL_OVERLAY_POWER
			? K1DE_SHELL_OVERLAY_NONE : K1DE_SHELL_OVERLAY_POWER;
		return true;
	default: return false;
	}
}

static void keyboard_handle_key(struct wl_listener *listener, void *data) {
	struct k1de_keyboard *kb = wl_container_of(listener, kb, key);
	struct k1de_server *server = kb->server;
	struct wlr_event_keyboard_key *ev = data;

	uint32_t keycode = ev->keycode + 8;
	const xkb_keysym_t *syms;
	int nsyms = xkb_state_key_get_syms(
		kb->device->keyboard->xkb_state, keycode, &syms);

	/* Always handle certain keys without needing modifiers */
	if (ev->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		for (int i = 0; i < nsyms; i++) {
			xkb_keysym_t sym = syms[i];
			/* Super/Meta key alone opens menu */
			if (sym == XKB_KEY_Super_L || sym == XKB_KEY_Super_R ||
				sym == XKB_KEY_Meta_L || sym == XKB_KEY_Meta_R ||
				sym == XKB_KEY_Menu) {
				server->shell_overlay = K1DE_SHELL_OVERLAY_MENU;
				return;
			}
		}
	}

	bool handled = false;
	uint32_t mods = wlr_keyboard_get_modifiers(kb->device->keyboard);
	if ((mods & WLR_MODIFIER_LOGO) &&
			ev->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		for (int i = 0; i < nsyms; i++)
			handled |= handle_keybinding(server, syms[i]);
	}
	if ((mods & WLR_MODIFIER_ALT) &&
			ev->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		for (int i = 0; i < nsyms; i++)
			handled |= handle_keybinding(server, syms[i]);
	}

	if (!handled && ev->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
		wlr_seat_set_keyboard(server->seat, kb->device);
		wlr_seat_keyboard_notify_key(server->seat,
			ev->time_msec, ev->keycode, ev->state);
	}
}

/* ── Input device management ─────────────────────────────────────────────────*/
static void server_new_keyboard(struct k1de_server *server,
		struct wlr_input_device *device) {
	struct k1de_keyboard *kb = calloc(1, sizeof(*kb));
	kb->server = server;
	kb->device = device;

	struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	struct xkb_keymap *km = xkb_keymap_new_from_names(ctx, NULL,
		XKB_KEYMAP_COMPILE_NO_FLAGS);
	wlr_keyboard_set_keymap(device->keyboard, km);
	xkb_keymap_unref(km);
	xkb_context_unref(ctx);
	wlr_keyboard_set_repeat_info(device->keyboard, 25, 600);

	kb->modifiers.notify = keyboard_handle_modifiers;
	wl_signal_add(&device->keyboard->events.modifiers, &kb->modifiers);
	kb->key.notify = keyboard_handle_key;
	wl_signal_add(&device->keyboard->events.key, &kb->key);

	wlr_seat_set_keyboard(server->seat, device);
	wl_list_insert(&server->keyboards, &kb->link);
}

static void server_new_input(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, new_input);
	struct wlr_input_device *device = data;
	if (device->type == WLR_INPUT_DEVICE_KEYBOARD)
		server_new_keyboard(server, device);
	else if (device->type == WLR_INPUT_DEVICE_POINTER)
		wlr_cursor_attach_input_device(server->cursor, device);

	uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
	if (!wl_list_empty(&server->keyboards))
		caps |= WL_SEAT_CAPABILITY_KEYBOARD;
	wlr_seat_set_capabilities(server->seat, caps);
}

static void seat_request_cursor(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, request_cursor);
	struct wlr_seat_pointer_request_set_cursor_event *ev = data;
	if (server->seat->pointer_state.focused_client == ev->seat_client)
		wlr_cursor_set_surface(server->cursor, ev->surface,
			ev->hotspot_x, ev->hotspot_y);
}

static void seat_request_set_selection(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, request_set_selection);
	struct wlr_seat_request_set_selection_event *ev = data;
	wlr_seat_set_selection(server->seat, ev->source, ev->serial);
}

/* ── XDG shell ───────────────────────────────────────────────────────────────*/
static void xdg_surface_map(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_view *view = wl_container_of(listener, view, map);
	view->mapped = true;
	focus_view(view, view->xdg_surface->surface);
}

static void xdg_surface_unmap(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_view *view = wl_container_of(listener, view, unmap);
	view->mapped = false;
}

static void xdg_surface_destroy(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_view *view = wl_container_of(listener, view, destroy);
	wl_list_remove(&view->link);
	free(view);
}

static void xdg_toplevel_request_move(struct wl_listener *listener, void *data) {
	(void)data;
	struct k1de_view *view = wl_container_of(listener, view, request_move);
	begin_interactive(view, K1DE_CURSOR_MOVE, 0);
}

static void xdg_toplevel_request_resize(struct wl_listener *listener, void *data) {
	struct wlr_xdg_toplevel_resize_event *ev = data;
	struct k1de_view *view = wl_container_of(listener, view, request_resize);
	begin_interactive(view, K1DE_CURSOR_RESIZE, ev->edges);
}

static void server_new_xdg_surface(struct wl_listener *listener, void *data) {
	struct k1de_server *server = wl_container_of(listener, server, new_xdg_surface);
	struct wlr_xdg_surface *xdg = data;
	if (xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) return;

	struct k1de_view *view = calloc(1, sizeof(*view));
	view->server = server;
	view->xdg_surface = xdg;

	/* tile windows in a cascade below the panel, accounting for titlebar */
	size_t slot = server->next_window_slot++ % 6;
	view->x = 80 + (int)(slot * 32);
	view->y = PANEL_H + TITLEBAR_H + 12 + (int)(slot * 22);

	view->map.notify = xdg_surface_map;
	wl_signal_add(&xdg->events.map, &view->map);
	view->unmap.notify = xdg_surface_unmap;
	wl_signal_add(&xdg->events.unmap, &view->unmap);
	view->destroy.notify = xdg_surface_destroy;
	wl_signal_add(&xdg->events.destroy, &view->destroy);
	view->request_move.notify = xdg_toplevel_request_move;
	wl_signal_add(&xdg->toplevel->events.request_move, &view->request_move);
	view->request_resize.notify = xdg_toplevel_request_resize;
	wl_signal_add(&xdg->toplevel->events.request_resize, &view->request_resize);

	wl_list_insert(&server->views, &view->link);
}

/* ── Interactive move/resize ─────────────────────────────────────────────────*/
static void begin_interactive(struct k1de_view *view,
		enum k1de_cursor_mode mode, uint32_t edges) {
	struct k1de_server *server = view->server;
	server->grabbed_view = view;
	server->cursor_mode = mode;

	if (mode == K1DE_CURSOR_MOVE) {
		server->grab_x = server->cursor->x - view->x;
		server->grab_y = server->cursor->y - view->y;
	} else {
		struct wlr_box geo;
		wlr_xdg_surface_get_geometry(view->xdg_surface, &geo);
		double bx = (view->x + geo.x) + ((edges & WLR_EDGE_RIGHT)  ? geo.width  : 0);
		double by = (view->y + geo.y) + ((edges & WLR_EDGE_BOTTOM) ? geo.height : 0);
		server->grab_x = server->cursor->x - bx;
		server->grab_y = server->cursor->y - by;
		server->grab_geobox = geo;
		server->grab_geobox.x += view->x;
		server->grab_geobox.y += view->y;
		server->resize_edges = edges;
	}
}

/* ── Server lifecycle ────────────────────────────────────────────────────────*/
void server_init(struct k1de_server *server, const char *startup_cmd) {
	signal(SIGCHLD, SIG_IGN);
	server->wl_display = wl_display_create();

	if (!getenv("WLR_BACKENDS"))    setenv("WLR_BACKENDS",    "drm", 0);
	if (!getenv("WLR_DRM_DEVICES")) setenv("WLR_DRM_DEVICES", "/dev/dri/card0", 0);

	server->backend = wlr_backend_autocreate(server->wl_display);
	if (!server->backend) {
		wlr_log(WLR_ERROR, "failed to create backend");
		wl_display_destroy(server->wl_display);
		exit(1);
	}

	server->renderer = wlr_backend_get_renderer(server->backend);
	if (!server->renderer) {
		wlr_log(WLR_ERROR, "failed to get renderer");
		wlr_backend_destroy(server->backend);
		wl_display_destroy(server->wl_display);
		exit(1);
	}
	wlr_renderer_init_wl_display(server->renderer, server->wl_display);
	wlr_compositor_create(server->wl_display, server->renderer);
	wlr_data_device_manager_create(server->wl_display);

	server->output_layout = wlr_output_layout_create();
	wl_list_init(&server->outputs);
	server->new_output.notify = server_new_output;
	wl_signal_add(&server->backend->events.new_output, &server->new_output);

	wl_list_init(&server->views);
	server->xdg_shell = wlr_xdg_shell_create(server->wl_display);
	server->new_xdg_surface.notify = server_new_xdg_surface;
	wl_signal_add(&server->xdg_shell->events.new_surface,
		&server->new_xdg_surface);

	server->cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(server->cursor, server->output_layout);
	server->cursor_mgr = wlr_xcursor_manager_create(NULL, 24);
	wlr_xcursor_manager_load(server->cursor_mgr, 1);

	server->cursor_motion.notify = server_cursor_motion;
	wl_signal_add(&server->cursor->events.motion, &server->cursor_motion);
	server->cursor_motion_absolute.notify = server_cursor_motion_absolute;
	wl_signal_add(&server->cursor->events.motion_absolute,
		&server->cursor_motion_absolute);
	server->cursor_button.notify = server_cursor_button;
	wl_signal_add(&server->cursor->events.button, &server->cursor_button);
	server->cursor_axis.notify = server_cursor_axis;
	wl_signal_add(&server->cursor->events.axis, &server->cursor_axis);
	server->cursor_frame.notify = server_cursor_frame;
	wl_signal_add(&server->cursor->events.frame, &server->cursor_frame);

	wl_list_init(&server->keyboards);
	server->new_input.notify = server_new_input;
	wl_signal_add(&server->backend->events.new_input, &server->new_input);
	server->seat = wlr_seat_create(server->wl_display, "seat0");
	server->request_cursor.notify = seat_request_cursor;
	wl_signal_add(&server->seat->events.request_set_cursor,
		&server->request_cursor);
	server->request_set_selection.notify = seat_request_set_selection;
	wl_signal_add(&server->seat->events.request_set_selection,
		&server->request_set_selection);

	const char *socket = wl_display_add_socket_auto(server->wl_display);
	if (!socket) {
		wlr_log(WLR_ERROR, "failed to create wayland socket");
		wlr_backend_destroy(server->backend);
		wl_display_destroy(server->wl_display);
		exit(1);
	}
	setenv("WAYLAND_DISPLAY", socket, 1);
	server->shell_overlay = K1DE_SHELL_OVERLAY_NONE;
	server->next_window_slot = 0;
	server->current_workspace = 0;
	server->vol_level = 50;
	server->bright_level = 80;
	server->locked = false;
	server->last_time = time(NULL);
	for (int i = 0; i < NUM_WORKSPACES; i++)
		server->next_workspace_slot[i] = 0;

	if (startup_cmd) spawn_cmd(startup_cmd);
	wlr_log(WLR_INFO, "K1DE running on %s", socket);
}

void server_run(struct k1de_server *server) {
	if (!wlr_backend_start(server->backend)) {
		wlr_log(WLR_ERROR, "failed to start backend");
		wlr_backend_destroy(server->backend);
		wl_display_destroy(server->wl_display);
		return;
	}
	wl_display_run(server->wl_display);
}

void server_finish(struct k1de_server *server) {
	wl_display_destroy_clients(server->wl_display);
	wl_display_destroy(server->wl_display);
}
