//! K1DE — K1OS's display server / console.
//!
//! Rewritten from scratch (the previous implementation's source was lost —
//! only the compiled binary and this history survived) to fix the one thing
//! that mattered most: K1OS used to scan out whatever resolution the
//! virtio-gpu connector reported *at boot* and never looked again, so
//! resizing the QEMU window did nothing. A normal Linux desktop re-probes
//! the connector on every hotplug/resize uevent instead of trusting a
//! cached mode; `drm::Drm::refresh` does the equivalent by re-running the
//! GETCONNECTOR probe on a timer and re-scanning out whenever the reported
//! mode changes, so K1DE now follows the host window like any other guest.

mod drm;
mod font;
mod input;
mod pty;

use font::Font;
use std::time::{Duration, Instant};

extern "C" {
    fn poll(fds: *mut PollFd, nfds: u64, timeout_ms: i32) -> i32;
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}
const POLLIN: i16 = 0x0001;

const IDLE_TIMEOUT: Duration = Duration::from_secs(600);
const DRM_REFRESH_INTERVAL: Duration = Duration::from_millis(500);
const KEYBOARD_RESCAN_INTERVAL: Duration = Duration::from_secs(2);

const FG: u32 = 0x00C0C0C0; // default light grey text, XRGB8888
const BG: u32 = 0x00101014; // default near-black background

/// The classic 16-color Linux console (`TERM=linux`) palette — this is what
/// fish, htop, ls --color, etc. actually target, so matching it (rather than
/// picking arbitrary colors) makes their output look the way it's supposed
/// to instead of merely "colored".
const PALETTE: [u32; 16] = [
    0x00000000, // 0 black
    0x00AA0000, // 1 red
    0x0000AA00, // 2 green
    0x00AA5500, // 3 brown/yellow
    0x000000AA, // 4 blue
    0x00AA00AA, // 5 magenta
    0x0000AAAA, // 6 cyan
    0x00AAAAAA, // 7 light grey
    0x00555555, // 8 bright black (dark grey)
    0x00FF5555, // 9 bright red
    0x0055FF55, // 10 bright green
    0x00FFFF55, // 11 bright yellow
    0x005555FF, // 12 bright blue
    0x00FF55FF, // 13 bright magenta
    0x0055FFFF, // 14 bright cyan
    0x00FFFFFF, // 15 white
];

#[derive(Clone, Copy)]
struct Cell {
    ch: u8,
    fg: Option<u8>,
    bg: Option<u8>,
}

const BLANK: Cell = Cell {
    ch: b' ',
    fg: None,
    bg: None,
};

/// A dumb full-screen text grid: no scrollback, but does track 16-color SGR
/// state and enough VT behaviour (CR/LF/TAB/BS, cursor motion, erase, and
/// swallowing the escape sequences it doesn't act on instead of printing
/// their raw bytes) for a real shell prompt and curses-style TUIs to be
/// usable.
struct Terminal {
    cols: usize,
    rows: usize,
    cells: Vec<Cell>,
    cursor_row: usize,
    cursor_col: usize,
    esc: EscState,
    dirty: bool,
    csi_params: Vec<u32>,
    csi_cur: Option<u32>,
    cur_fg: Option<u8>,
    cur_bg: Option<u8>,
    bold: bool,
}

#[derive(PartialEq)]
enum EscState {
    None,
    Esc,
    Csi,
    /// OSC (`ESC ]`), e.g. fish's shell-integration markers and title/cwd
    /// updates — swallowed until BEL or ST (`ESC \`), same idea as CSI.
    Osc,
    OscEsc,
    /// DCS (`ESC P`), e.g. fish's XTGETTCAP terminfo queries — also
    /// terminated by ST (`ESC \`).
    Dcs,
    DcsEsc,
    /// VT100 charset designation (`ESC ( B`, `ESC ) 0`, ...) — a fixed
    /// 2-byte sequence, so swallow exactly one more byte.
    Charset,
}

impl Terminal {
    fn new(cols: usize, rows: usize) -> Terminal {
        Terminal {
            cols,
            rows,
            cells: vec![BLANK; cols * rows],
            cursor_row: 0,
            cursor_col: 0,
            esc: EscState::None,
            dirty: true,
            csi_params: Vec::new(),
            csi_cur: None,
            cur_fg: None,
            cur_bg: None,
            bold: false,
        }
    }

    /// A CSI parameter by index, or `default` if it wasn't given (absent or
    /// explicitly `0`, per the usual ECMA-48 convention).
    fn csi_param(&self, i: usize, default: u32) -> u32 {
        match self.csi_params.get(i) {
            Some(&0) | None => default,
            Some(&v) => v,
        }
    }

    fn resize(&mut self, cols: usize, rows: usize) {
        if cols == self.cols && rows == self.rows {
            return;
        }
        self.cols = cols.max(1);
        self.rows = rows.max(1);
        self.cells = vec![BLANK; self.cols * self.rows];
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.dirty = true;
    }

    fn newline(&mut self) {
        self.cursor_col = 0;
        if self.cursor_row + 1 >= self.rows {
            // Scroll up one line.
            self.cells.copy_within(self.cols.., 0);
            let last = self.cells.len() - self.cols;
            self.cells[last..].fill(BLANK);
        } else {
            self.cursor_row += 1;
        }
    }

    /// Handles the CSI final bytes that matter for a shell prompt and
    /// curses-style TUIs (htop, less, ...) to look right: cursor motion,
    /// erase-in-line/display, and SGR (color/bold). Everything else (mode
    /// toggles, DECSET/DECRST, scroll regions, ...) is intentionally a
    /// no-op.
    fn apply_csi(&mut self, final_byte: u8) {
        let row_start = self.cursor_row * self.cols;
        match final_byte {
            b'K' => match self.csi_param(0, 0) {
                0 => self.cells[row_start + self.cursor_col..row_start + self.cols].fill(BLANK),
                1 => self.cells[row_start..=row_start + self.cursor_col.min(self.cols - 1)].fill(BLANK),
                2 => self.cells[row_start..row_start + self.cols].fill(BLANK),
                _ => {}
            },
            b'J' => match self.csi_param(0, 0) {
                0 => {
                    let start = row_start + self.cursor_col;
                    self.cells[start..].fill(BLANK);
                }
                1 => {
                    let end = (row_start + self.cursor_col).min(self.cells.len() - 1);
                    self.cells[..=end].fill(BLANK);
                }
                2 | 3 => {
                    self.cells.fill(BLANK);
                    self.cursor_row = 0;
                    self.cursor_col = 0;
                }
                _ => {}
            },
            b'C' => {
                let n = self.csi_param(0, 1) as usize;
                self.cursor_col = (self.cursor_col + n).min(self.cols.saturating_sub(1));
            }
            b'D' => {
                let n = self.csi_param(0, 1) as usize;
                self.cursor_col = self.cursor_col.saturating_sub(n);
            }
            b'G' => {
                let n = self.csi_param(0, 1) as usize;
                self.cursor_col = n.saturating_sub(1).min(self.cols.saturating_sub(1));
            }
            b'H' | b'f' => {
                let row = self.csi_param(0, 1) as usize;
                let col = self.csi_param(1, 1) as usize;
                self.cursor_row = row.saturating_sub(1).min(self.rows.saturating_sub(1));
                self.cursor_col = col.saturating_sub(1).min(self.cols.saturating_sub(1));
            }
            b'm' => self.apply_sgr(),
            _ => {}
        }
    }

    /// SGR (`CSI ... m`): the color/bold state ls, fish and htop actually
    /// rely on. Handles the basic 8/16-color codes plus 256-color/truecolor
    /// `38;5;N` / `38;2;R;G;B` by mapping them down onto the 16-color
    /// palette (we only ever scan out one bit depth of "is this a terminal
    /// color", there's no point carrying real 24-bit color through).
    fn apply_sgr(&mut self) {
        if self.csi_params.is_empty() {
            self.cur_fg = None;
            self.cur_bg = None;
            self.bold = false;
            return;
        }
        let mut i = 0;
        while i < self.csi_params.len() {
            let p = self.csi_params[i];
            match p {
                0 => {
                    self.cur_fg = None;
                    self.cur_bg = None;
                    self.bold = false;
                }
                1 => self.bold = true,
                22 => self.bold = false,
                30..=37 => self.cur_fg = Some((p - 30) as u8),
                39 => self.cur_fg = None,
                40..=47 => self.cur_bg = Some((p - 40) as u8),
                49 => self.cur_bg = None,
                90..=97 => self.cur_fg = Some((p - 90) as u8 + 8),
                100..=107 => self.cur_bg = Some((p - 100) as u8 + 8),
                38 | 48 => {
                    // Extended color: `38;5;N` (256-color) or `38;2;R;G;B`
                    // (truecolor). Map both down to the nearest of our 16.
                    let target_fg = p == 38;
                    match self.csi_params.get(i + 1) {
                        Some(5) => {
                            if let Some(&idx) = self.csi_params.get(i + 2) {
                                let c = Some(nearest_16(ansi256_to_rgb(idx as u8)));
                                if target_fg {
                                    self.cur_fg = c;
                                } else {
                                    self.cur_bg = c;
                                }
                            }
                            i += 2;
                        }
                        Some(2) => {
                            let r = *self.csi_params.get(i + 2).unwrap_or(&0) as u8;
                            let g = *self.csi_params.get(i + 3).unwrap_or(&0) as u8;
                            let b = *self.csi_params.get(i + 4).unwrap_or(&0) as u8;
                            let c = Some(nearest_16(rgb(r, g, b)));
                            if target_fg {
                                self.cur_fg = c;
                            } else {
                                self.cur_bg = c;
                            }
                            i += 4;
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
            i += 1;
        }
    }

    fn put(&mut self, ch: u8) {
        if self.cursor_col >= self.cols {
            self.newline();
        }
        let fg = self.cur_fg.map(|c| if self.bold { c | 0x8 } else { c });
        let idx = self.cursor_row * self.cols + self.cursor_col;
        self.cells[idx] = Cell {
            ch,
            fg,
            bg: self.cur_bg,
        };
        self.cursor_col += 1;
    }

    fn process_byte(&mut self, b: u8) {
        self.dirty = true;
        match self.esc {
            EscState::None => match b {
                b'\n' => self.newline(),
                b'\r' => self.cursor_col = 0,
                b'\t' => {
                    let next = (self.cursor_col / 8 + 1) * 8;
                    while self.cursor_col < next && self.cursor_col < self.cols {
                        self.put(b' ');
                    }
                }
                0x08 | 0x7f => {
                    if self.cursor_col > 0 {
                        self.cursor_col -= 1;
                    }
                }
                0x1b => self.esc = EscState::Esc,
                0x20..=0x7e => self.put(b),
                _ => {}
            },
            EscState::Esc => {
                self.esc = match b {
                    b'[' => {
                        self.csi_params.clear();
                        self.csi_cur = None;
                        EscState::Csi
                    }
                    b']' => EscState::Osc,
                    b'P' => EscState::Dcs,
                    b'(' | b')' | b'*' | b'+' => EscState::Charset,
                    _ => EscState::None,
                };
            }
            EscState::Csi => {
                match b {
                    b'0'..=b'9' => {
                        self.csi_cur = Some(self.csi_cur.unwrap_or(0) * 10 + (b - b'0') as u32);
                    }
                    b';' => self.csi_params.push(self.csi_cur.take().unwrap_or(0)),
                    0x40..=0x7e => {
                        if let Some(v) = self.csi_cur.take() {
                            self.csi_params.push(v);
                        }
                        self.apply_csi(b);
                        self.esc = EscState::None;
                    }
                    // Intermediate/private-marker bytes (e.g. '?', ' ') we
                    // don't care about — keep collecting the sequence.
                    _ => {}
                }
            }
            EscState::Osc => {
                // Terminated by BEL, or by ST (ESC \).
                if b == 0x07 {
                    self.esc = EscState::None;
                } else if b == 0x1b {
                    self.esc = EscState::OscEsc;
                }
            }
            EscState::OscEsc => {
                self.esc = if b == b'\\' {
                    EscState::None
                } else {
                    EscState::Osc
                };
            }
            EscState::Dcs => {
                if b == 0x1b {
                    self.esc = EscState::DcsEsc;
                }
            }
            EscState::DcsEsc => {
                self.esc = if b == b'\\' {
                    EscState::None
                } else {
                    EscState::Dcs
                };
            }
            EscState::Charset => {
                self.esc = EscState::None;
            }
        }
    }

    fn render(&mut self, drm: &mut drm::Drm, font: &Font) {
        let Some((buf, pitch, width, height)) = drm.framebuffer() else {
            return;
        };
        let pitch = pitch as usize;
        let row_bytes = width as usize * 4;
        for row in buf.chunks_mut(pitch) {
            let len = row_bytes.min(row.len());
            for px in row[..len].chunks_exact_mut(4) {
                px.copy_from_slice(&BG.to_le_bytes());
            }
        }
        for r in 0..self.rows {
            for c in 0..self.cols {
                let cell = self.cells[r * self.cols + c];
                let ox = c * font.width;
                let oy = r * font.height;
                if let Some(bg) = cell.bg {
                    fill_cell(buf, pitch, PALETTE[bg as usize], ox, oy, font.width, font.height);
                }
                if cell.ch != b' ' {
                    let fg = cell.fg.map_or(FG, |i| PALETTE[i as usize]);
                    blit_glyph(buf, pitch, font, cell.ch, fg, ox, oy);
                }
            }
        }
        let _ = height;
        drm.flush();
        self.dirty = false;
    }
}

fn rgb(r: u8, g: u8, b: u8) -> u32 {
    (r as u32) << 16 | (g as u32) << 8 | b as u32
}

/// The 16 standard + 6x6x6 cube + 24-step greyscale xterm-256 palette,
/// reduced to just the RGB value we need to then snap to our 16 colors.
fn ansi256_to_rgb(idx: u8) -> u32 {
    match idx {
        0..=15 => PALETTE[idx as usize],
        16..=231 => {
            let i = idx - 16;
            let levels = [0u8, 95, 135, 175, 215, 255];
            let r = levels[(i / 36) as usize % 6];
            let g = levels[(i / 6) as usize % 6];
            let b = levels[i as usize % 6];
            rgb(r, g, b)
        }
        232..=255 => {
            let v = 8 + (idx - 232) * 10;
            rgb(v, v, v)
        }
    }
}

/// Nearest of our 16 palette colors to an arbitrary RGB, by squared
/// distance — good enough for "256-color app running on a 16-color scanout".
fn nearest_16(color: u32) -> u8 {
    let (r, g, b) = (
        ((color >> 16) & 0xff) as i32,
        ((color >> 8) & 0xff) as i32,
        (color & 0xff) as i32,
    );
    let mut best = 0u8;
    let mut best_dist = i32::MAX;
    for (i, &p) in PALETTE.iter().enumerate() {
        let (pr, pg, pb) = (
            ((p >> 16) & 0xff) as i32,
            ((p >> 8) & 0xff) as i32,
            (p & 0xff) as i32,
        );
        let dist = (r - pr).pow(2) + (g - pg).pow(2) + (b - pb).pow(2);
        if dist < best_dist {
            best_dist = dist;
            best = i as u8;
        }
    }
    best
}

fn fill_cell(buf: &mut [u8], pitch: usize, color: u32, ox: usize, oy: usize, w: usize, h: usize) {
    let bytes = color.to_le_bytes();
    for y in 0..h {
        let row_off = (oy + y) * pitch;
        if row_off + w * 4 > buf.len() {
            break;
        }
        for x in 0..w {
            let off = row_off + (ox + x) * 4;
            buf[off..off + 4].copy_from_slice(&bytes);
        }
    }
}

fn blit_glyph(buf: &mut [u8], pitch: usize, font: &Font, ch: u8, color: u32, ox: usize, oy: usize) {
    let bytes = color.to_le_bytes();
    for y in 0..font.height {
        let row_off = (oy + y) * pitch;
        if row_off + 4 > buf.len() {
            break;
        }
        for x in 0..font.width {
            if font.pixel(ch, x, y) {
                let off = row_off + (ox + x) * 4;
                if off + 4 <= buf.len() {
                    buf[off..off + 4].copy_from_slice(&bytes);
                }
            }
        }
    }
}

fn draw_string(buf: &mut [u8], pitch: usize, font: &Font, s: &str, ox: usize, oy: usize) {
    for (i, ch) in s.bytes().enumerate() {
        blit_glyph(buf, pitch, font, ch, FG, ox + i * font.width, oy);
    }
}

fn render_screensaver(drm: &mut drm::Drm, font: &Font) {
    let Some((buf, pitch, width, height)) = drm.framebuffer() else {
        return;
    };
    let pitch = pitch as usize;
    let row_bytes = width as usize * 4;
    for row in buf.chunks_mut(pitch) {
        let len = row_bytes.min(row.len());
        for px in row[..len].chunks_exact_mut(4) {
            px.copy_from_slice(&0u32.to_le_bytes());
        }
    }
    let logo = "K1OS";
    let hint = "Screensaver active. Press any key to resume...";
    let lx = (width as usize / 2).saturating_sub(logo.len() * font.width * 2 / 2);
    let ly = height as usize / 2 - font.height * 2;
    draw_string(buf, pitch, font, logo, lx, ly);
    let hx = (width as usize / 2).saturating_sub(hint.len() * font.width / 2);
    let hy = height as usize / 2 + font.height;
    draw_string(buf, pitch, font, hint, hx, hy);
    drm.flush();
}

fn main() {
    let mut drm = match drm::Drm::open("/dev/dri/card0") {
        Ok(d) => d,
        Err(e) => {
            eprintln!("k1de: DRM/KMS initialization failed: {e}");
            std::process::exit(1);
        }
    };
    let font = Font::load();
    eprintln!(
        "k1de: K1OS Display Engine (K1DE Core) — font {}x{}",
        font.width, font.height
    );

    let mut mode = None;
    let mut term: Option<Terminal> = None;
    let mut pty: Option<pty::Pty> = None;
    let mut decoder = input::Decoder::new();
    let mut keyboards = input::scan_keyboards();
    if keyboards.is_empty() {
        eprintln!("k1de:  ! No input devices found under /dev/input/event*");
    }

    let mut last_drm_refresh = Instant::now() - DRM_REFRESH_INTERVAL;
    let mut last_kb_scan = Instant::now();
    let mut idle_since = Instant::now();
    let mut screensaving = false;

    loop {
        let now = Instant::now();

        if now.duration_since(last_drm_refresh) >= DRM_REFRESH_INTERVAL {
            last_drm_refresh = now;
            match drm.refresh() {
                Ok(Some(new_mode)) => {
                    if mode != Some(new_mode) {
                        eprintln!(
                            "k1de: DRM/KMS Mode Selected: {}x{}",
                            new_mode.width, new_mode.height
                        );
                        mode = Some(new_mode);
                        let cols = (new_mode.width as usize / font.width).max(1);
                        let rows = (new_mode.height as usize / font.height).max(1);
                        match &mut term {
                            Some(t) => t.resize(cols, rows),
                            None => term = Some(Terminal::new(cols, rows)),
                        }
                        match &pty {
                            Some(p) => p.resize(cols as u16, rows as u16),
                            None => {
                                pty = pty::Pty::spawn("/usr/bin/fish", cols as u16, rows as u16)
                                    .map_err(|e| eprintln!("k1de: failed to spawn shell: {e}"))
                                    .ok();
                            }
                        }
                        if let Some(t) = &mut term {
                            t.dirty = true;
                        }
                    }
                }
                Ok(None) => {
                    if mode.is_some() {
                        eprintln!("k1de:  ! No active connected display found");
                    }
                    mode = None;
                }
                Err(e) => eprintln!("k1de:  ! DRM refresh failed: {e}"),
            }
        }

        if now.duration_since(last_kb_scan) >= KEYBOARD_RESCAN_INTERVAL {
            last_kb_scan = now;
            let fresh = input::scan_keyboards();
            for kb in fresh {
                if !keyboards.iter().any(|k| k.path == kb.path) {
                    eprintln!("k1de: Keyboard detected via hot-plug.");
                    keyboards.push(kb);
                }
            }
        }

        if let Some(p) = &mut pty {
            if p.try_wait_exited() {
                eprintln!("k1de: shell exited, respawning");
                pty = None;
            }
        }

        // Poll the pty master plus every keyboard fd, short timeout so the
        // DRM refresh / keyboard rescan / idle checks above keep running.
        let mut pollfds: Vec<PollFd> = Vec::with_capacity(keyboards.len() + 1);
        if let Some(p) = &pty {
            pollfds.push(PollFd {
                fd: p.fd(),
                events: POLLIN,
                revents: 0,
            });
        }
        let kb_start = pollfds.len();
        for kb in &keyboards {
            pollfds.push(PollFd {
                fd: kb.fd(),
                events: POLLIN,
                revents: 0,
            });
        }

        let n = unsafe { poll(pollfds.as_mut_ptr(), pollfds.len() as u64, 200) };
        if n > 0 {
            if let Some(p) = &mut pty {
                if !pollfds.is_empty() && pollfds[0].revents & POLLIN != 0 {
                    let mut buf = [0u8; 4096];
                    use std::io::Read;
                    if let Ok(count) = p.master.read(&mut buf) {
                        if count > 0 {
                            if std::env::var_os("K1DE_DEBUG_PTY").is_some() {
                                eprint!("k1de: pty>");
                                for &b in &buf[..count] {
                                    eprint!(" {b:02x}");
                                }
                                eprintln!();
                            }
                            if let Some(t) = &mut term {
                                for &b in &buf[..count] {
                                    t.process_byte(b);
                                }
                            }
                        }
                    }
                }
            }
            for (i, kb) in keyboards.iter_mut().enumerate() {
                let slot = kb_start + i;
                if pollfds[slot].revents & POLLIN == 0 {
                    continue;
                }
                if let Some(bytes) = decoder.read_event(kb) {
                    if bytes.is_empty() {
                        continue;
                    }
                    idle_since = Instant::now();
                    if screensaving {
                        screensaving = false;
                        if let Some(t) = &mut term {
                            t.dirty = true;
                        }
                    } else if let Some(p) = &pty {
                        use std::io::Write;
                        let _ = (&p.master).write_all(&bytes);
                    }
                }
            }
        }

        if !screensaving && Instant::now().duration_since(idle_since) >= IDLE_TIMEOUT {
            screensaving = true;
            eprintln!("k1de: Screensaver active. Press any key to resume...");
        }

        if screensaving {
            render_screensaver(&mut drm, &font);
        } else if let Some(t) = &mut term {
            if t.dirty {
                t.render(&mut drm, &font);
            }
        }
    }
}
