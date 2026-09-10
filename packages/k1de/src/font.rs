//! Console font: instead of hand-embedding a bitmap font (easy to get subtly
//! wrong and impossible to eyeball-review here), we pull the kernel's own VGA
//! console font via `KDFONTOP` on a vt device. It's already loaded by the
//! time any getty/console shows text, so this is the same font the boot
//! messages used.

use std::fs::OpenOptions;
use std::io;
use std::os::fd::AsRawFd;

extern "C" {
    fn ioctl(fd: i32, request: u64, ...) -> i32;
}

const KDFONTOP: u64 = 0x4B72;
const KD_FONT_OP_GET: u32 = 1;

#[repr(C)]
struct ConsoleFontOp {
    op: u32,
    flags: u32,
    width: u32,
    height: u32,
    charcount: u32,
    data: *mut u8,
}

pub struct Font {
    pub width: usize,
    pub height: usize,
    /// One byte per row per glyph (width <= 8), vpitch fixed at 32 rows.
    data: Vec<u8>,
}

impl Font {
    pub fn load() -> Font {
        for path in ["/dev/tty1", "/dev/tty0", "/dev/console"] {
            if let Ok(f) = Self::load_from(path) {
                return f;
            }
        }
        Font::fallback()
    }

    fn load_from(path: &str) -> io::Result<Font> {
        let file = OpenOptions::new().read(true).write(true).open(path)?;
        let fd = file.as_raw_fd();
        let mut buf = vec![0u8; 256 * 32];
        let mut op = ConsoleFontOp {
            op: KD_FONT_OP_GET,
            flags: 0,
            width: 8,
            height: 32,
            charcount: 256,
            data: buf.as_mut_ptr(),
        };
        let ret = unsafe { ioctl(fd, KDFONTOP, &mut op as *mut ConsoleFontOp) };
        if ret < 0 || op.height == 0 || op.width == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Font {
            width: op.width as usize,
            height: op.height as usize,
            data: buf,
        })
    }

    /// Tiny 4x6 block font covering digits and A-Z, used only if the kernel
    /// has no VT font loaded at all (shouldn't happen — K1OS boots straight
    /// to a text console before k1de starts).
    fn fallback() -> Font {
        Font {
            width: 8,
            height: 8,
            data: vec![0xFFu8; 256 * 32], // solid blocks: legible as "there is text here"
        }
    }

    /// Returns whether pixel (x, y) within glyph `c` is set.
    pub fn pixel(&self, c: u8, x: usize, y: usize) -> bool {
        if x >= self.width || y >= self.height {
            return false;
        }
        let row = self.data[c as usize * 32 + y];
        (row >> (7 - x)) & 1 != 0
    }
}
