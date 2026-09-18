//! Spawns the login shell behind a real pty (not a bare pipe), so job
//! control, line editing and SIGWINCH-driven resize all work the way they
//! would under any other Linux terminal.

use std::ffi::CString;
use std::fs::File;
use std::io;
use std::os::fd::{AsRawFd, FromRawFd, RawFd};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command};

extern "C" {
    fn posix_openpt(flags: i32) -> i32;
    fn grantpt(fd: i32) -> i32;
    fn unlockpt(fd: i32) -> i32;
    fn ptsname_r(fd: i32, buf: *mut u8, buflen: usize) -> i32;
    fn ioctl(fd: i32, request: u64, ...) -> i32;
}

const O_RDWR: i32 = 0o2;
const O_NOCTTY: i32 = 0o400;
const TIOCSWINSZ: u64 = 0x5414;

#[repr(C)]
struct Winsize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

pub struct Pty {
    pub master: File,
    #[allow(dead_code)]
    slave_path: String,
    child: Child,
}

impl Pty {
    /// Opens a fresh pty pair and forks `shell` (falling back to `/bin/sh`
    /// if it isn't there) attached to the slave side as its controlling
    /// terminal.
    pub fn spawn(shell: &str, cols: u16, rows: u16) -> io::Result<Pty> {
        let master_fd = unsafe { posix_openpt(O_RDWR | O_NOCTTY) };
        if master_fd < 0 {
            return Err(io::Error::last_os_error());
        }
        if unsafe { grantpt(master_fd) } < 0 || unsafe { unlockpt(master_fd) } < 0 {
            let e = io::Error::last_os_error();
            unsafe { libc_close(master_fd) };
            return Err(e);
        }
        let mut buf = vec![0u8; 256];
        if unsafe { ptsname_r(master_fd, buf.as_mut_ptr(), buf.len()) } != 0 {
            let e = io::Error::last_os_error();
            unsafe { libc_close(master_fd) };
            return Err(e);
        }
        let len = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
        let slave_path = String::from_utf8_lossy(&buf[..len]).into_owned();

        let master = unsafe { File::from_raw_fd(master_fd) };
        let slave_path_for_child = slave_path.clone();

        let program = if std::path::Path::new(shell).exists() {
            shell
        } else {
            "/bin/sh"
        };

        // Deliberately leave stdio untouched here: pre_exec below dup2()s the
        // pty slave onto 0/1/2 itself, and letting `Command` also fiddle
        // with stdio risks a fight over ordering between the two.
        let mut cmd = Command::new(program);
        cmd.current_dir("/root")
            .env("TERM", "linux")
            .env("HOME", "/root")
            .env(
                "PATH",
                "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            );

        unsafe {
            cmd.pre_exec(move || {
                open_and_become_controlling_tty(&slave_path_for_child)
            });
        }

        let child = cmd.spawn()?;
        let pty = Pty {
            master,
            slave_path,
            child,
        };
        pty.resize(cols, rows);
        Ok(pty)
    }

    pub fn fd(&self) -> RawFd {
        self.master.as_raw_fd()
    }

    pub fn resize(&self, cols: u16, rows: u16) {
        let mut ws = Winsize {
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        unsafe { ioctl(self.fd(), TIOCSWINSZ, &mut ws as *mut Winsize) };
    }

    /// `Some(())` once the shell has exited (caller should respawn).
    pub fn try_wait_exited(&mut self) -> bool {
        matches!(self.child.try_wait(), Ok(Some(_)))
    }
}

extern "C" {
    #[link_name = "close"]
    fn libc_close(fd: i32) -> i32;
}

/// Runs in the forked child before exec: detach from k1de's session, open
/// the pty slave, make it the controlling terminal, and wire it to
/// stdin/stdout/stderr.
fn open_and_become_controlling_tty(slave_path: &str) -> io::Result<()> {
    extern "C" {
        fn setsid() -> i32;
        fn ioctl(fd: i32, request: u64, ...) -> i32;
    }
    const TIOCSCTTY: u64 = 0x540E;

    if unsafe { setsid() } < 0 {
        return Err(io::Error::last_os_error());
    }
    let path = CString::new(slave_path).unwrap();
    let slave_fd = unsafe { libc_open(path.as_ptr(), O_RDWR) };
    if slave_fd < 0 {
        return Err(io::Error::last_os_error());
    }
    if unsafe { ioctl(slave_fd, TIOCSCTTY, 0i32) } < 0 {
        // Not fatal on every driver; keep going.
    }
    unsafe {
        dup2_or_die(slave_fd, 0)?;
        dup2_or_die(slave_fd, 1)?;
        dup2_or_die(slave_fd, 2)?;
        if slave_fd > 2 {
            libc_close(slave_fd);
        }
    }
    Ok(())
}

extern "C" {
    #[link_name = "open"]
    fn libc_open(path: *const i8, flags: i32) -> i32;
    #[link_name = "dup2"]
    fn libc_dup2(oldfd: i32, newfd: i32) -> i32;
}

unsafe fn dup2_or_die(oldfd: i32, newfd: i32) -> io::Result<()> {
    if libc_dup2(oldfd, newfd) < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}
