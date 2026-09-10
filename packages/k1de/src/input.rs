//! Keyboard input: scans `/dev/input/event*` for keyboard-capable devices
//! (hot-plugged devices are picked up by re-scanning on a timer, so plugging
//! a keyboard in after boot works without a restart), decodes raw evdev
//! events and turns them into bytes for the pty — a US layout, plus the
//! handful of escape sequences a shell's line editor expects for arrows/home
//! /end/delete.

use std::fs::{self, File, OpenOptions};
use std::io::Read;
use std::os::fd::{AsRawFd, RawFd};

extern "C" {
    fn ioctl(fd: i32, request: u64, ...) -> i32;
}

const EVIOCGBIT_EV_KEY: u64 = {
    // _IOC(_IOC_READ, 'E', 0x20 + EV_KEY, len); len is part of the request
    // only for the *size* field, but the actual read is bounded by what we
    // pass as the buffer — len encoded here must match the buffer we use.
    const EV_KEY: u64 = 1;
    const LEN: u64 = 96;
    (2u64 << 30) | (0x45 << 8) | (0x20 + EV_KEY) | (LEN << 16)
};

const EV_KEY: u16 = 1;
const KEY_A: usize = 30;

#[repr(C)]
struct InputEvent {
    tv_sec: i64,
    tv_usec: i64,
    ev_type: u16,
    code: u16,
    value: i32,
}

pub struct Keyboard {
    pub path: String,
    file: File,
}

impl Keyboard {
    pub fn fd(&self) -> RawFd {
        self.file.as_raw_fd()
    }
}

/// Scans `/dev/input` for evdev nodes that report `EV_KEY` support and have
/// the `KEY_A` bit set (a cheap way to skip pure pointer devices).
pub fn scan_keyboards() -> Vec<Keyboard> {
    let mut out = Vec::new();
    let entries = match fs::read_dir("/dev/input") {
        Ok(e) => e,
        Err(_) => return out,
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !name.starts_with("event") {
            continue;
        }
        let path = entry.path();
        let file = match OpenOptions::new().read(true).write(false).open(&path) {
            Ok(f) => f,
            Err(_) => continue,
        };
        let mut bits = [0u8; 96];
        let ret = unsafe { ioctl(file.as_raw_fd(), EVIOCGBIT_EV_KEY, bits.as_mut_ptr()) };
        if ret < 0 {
            continue;
        }
        let has_key_a = (bits[KEY_A / 8] >> (KEY_A % 8)) & 1 != 0;
        if !has_key_a {
            continue;
        }
        out.push(Keyboard {
            path: path.to_string_lossy().into_owned(),
            file,
        });
    }
    out
}

/// Decoded keyboard state: modifier keys plus a scancode->bytes table.
pub struct Decoder {
    shift: bool,
    ctrl: bool,
}

fn base_char(code: u16) -> Option<(u8, u8)> {
    // (unshifted, shifted)
    Some(match code {
        2 => (b'1', b'!'),
        3 => (b'2', b'@'),
        4 => (b'3', b'#'),
        5 => (b'4', b'$'),
        6 => (b'5', b'%'),
        7 => (b'6', b'^'),
        8 => (b'7', b'&'),
        9 => (b'8', b'*'),
        10 => (b'9', b'('),
        11 => (b'0', b')'),
        12 => (b'-', b'_'),
        13 => (b'=', b'+'),
        15 => (b'\t', b'\t'),
        16 => (b'q', b'Q'),
        17 => (b'w', b'W'),
        18 => (b'e', b'E'),
        19 => (b'r', b'R'),
        20 => (b't', b'T'),
        21 => (b'y', b'Y'),
        22 => (b'u', b'U'),
        23 => (b'i', b'I'),
        24 => (b'o', b'O'),
        25 => (b'p', b'P'),
        26 => (b'[', b'{'),
        27 => (b']', b'}'),
        28 => (b'\n', b'\n'),
        30 => (b'a', b'A'),
        31 => (b's', b'S'),
        32 => (b'd', b'D'),
        33 => (b'f', b'F'),
        34 => (b'g', b'G'),
        35 => (b'h', b'H'),
        36 => (b'j', b'J'),
        37 => (b'k', b'K'),
        38 => (b'l', b'L'),
        39 => (b';', b':'),
        40 => (b'\'', b'"'),
        41 => (b'`', b'~'),
        43 => (b'\\', b'|'),
        44 => (b'z', b'Z'),
        45 => (b'x', b'X'),
        46 => (b'c', b'C'),
        47 => (b'v', b'V'),
        48 => (b'b', b'B'),
        49 => (b'n', b'N'),
        50 => (b'm', b'M'),
        51 => (b',', b'<'),
        52 => (b'.', b'>'),
        53 => (b'/', b'?'),
        57 => (b' ', b' '),
        96 => (b'\n', b'\n'), // KPENTER
        14 => (0x7f, 0x7f),   // BACKSPACE (DEL)
        _ => return None,
    })
}

impl Decoder {
    pub fn new() -> Decoder {
        Decoder {
            shift: false,
            ctrl: false,
        }
    }

    /// Reads one evdev event off `fd`, returning bytes to forward to the pty
    /// (empty if the event didn't produce output — e.g. a key release, or a
    /// modifier press).
    pub fn read_event(&mut self, kb: &mut Keyboard) -> Option<Vec<u8>> {
        let mut raw = [0u8; std::mem::size_of::<InputEvent>()];
        if kb.file.read_exact(&mut raw).is_err() {
            return None;
        }
        let ev: InputEvent = unsafe { std::mem::transmute(raw) };
        if ev.ev_type != EV_KEY {
            return Some(Vec::new());
        }
        let code = ev.code;
        let down = ev.value != 0; // 1 = press, 2 = repeat, 0 = release

        match code as usize {
            42 | 54 => {
                // LEFTSHIFT | RIGHTSHIFT
                self.shift = down;
                return Some(Vec::new());
            }
            29 | 97 => {
                // LEFTCTRL | RIGHTCTRL
                self.ctrl = down;
                return Some(Vec::new());
            }
            _ => {}
        }

        if !down {
            return Some(Vec::new());
        }

        // Arrow keys / navigation -> ANSI escape sequences, same as any
        // other Linux terminal, so readline-based shells handle them.
        let seq: &[u8] = match code {
            103 => b"\x1b[A", // UP
            108 => b"\x1b[B", // DOWN
            106 => b"\x1b[C", // RIGHT
            105 => b"\x1b[D", // LEFT
            102 => b"\x1b[H", // HOME
            107 => b"\x1b[F", // END
            111 => b"\x1b[3~", // DELETE
            _ => b"",
        };
        if !seq.is_empty() {
            return Some(seq.to_vec());
        }

        if let Some((lo, hi)) = base_char(code) {
            let ch = if self.shift { hi } else { lo };
            if self.ctrl && ch.is_ascii_alphabetic() {
                return Some(vec![ch.to_ascii_uppercase() - b'A' + 1]);
            }
            return Some(vec![ch]);
        }
        Some(Vec::new())
    }
}
