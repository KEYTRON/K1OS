//! Minimal raw DRM/KMS bindings — just enough to scan an output, follow it
//! across hotplug/resize events, and scan out a dumb buffer.
//!
//! No `drm-rs`, no libdrm: every ioctl here is hand-encoded from
//! `include/uapi/drm/{drm,drm_mode}.h` in the K1OS kernel tree, following the
//! same `_IOC(dir, type, nr, size)` formula the kernel headers use.

use std::fs::{File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;

extern "C" {
    fn ioctl(fd: i32, request: u64, ...) -> i32;
    fn mmap(
        addr: *mut std::ffi::c_void,
        len: usize,
        prot: i32,
        flags: i32,
        fd: i32,
        offset: i64,
    ) -> *mut std::ffi::c_void;
    fn munmap(addr: *mut std::ffi::c_void, len: usize) -> i32;
}

const PROT_READ: i32 = 0x1;
const PROT_WRITE: i32 = 0x2;
const MAP_SHARED: i32 = 0x1;
const MAP_FAILED: *mut std::ffi::c_void = !0 as *mut std::ffi::c_void;

const DRM_IOCTL_BASE: u64 = 0x64; // 'd'
const IOC_READ: u64 = 2;
const IOC_WRITE: u64 = 1;

const fn ioc(dir: u64, ty: u64, nr: u64, size: u64) -> u64 {
    (dir << 30) | (ty << 8) | nr | (size << 16)
}

const fn iowr(nr: u64, size: usize) -> u64 {
    ioc(IOC_READ | IOC_WRITE, DRM_IOCTL_BASE, nr, size as u64)
}

const fn io_(nr: u64) -> u64 {
    ioc(0, DRM_IOCTL_BASE, nr, 0)
}

const DRM_IOCTL_SET_MASTER: u64 = io_(0x1e);
const DRM_IOCTL_DROP_MASTER: u64 = io_(0x1f);

pub const DRM_MODE_TYPE_PREFERRED: u32 = 1 << 3;
pub const DRM_MODE_CONNECTED: u32 = 1;

#[repr(C)]
#[derive(Default, Clone, Copy)]
pub struct ModeInfo {
    pub clock: u32,
    pub hdisplay: u16,
    pub hsync_start: u16,
    pub hsync_end: u16,
    pub htotal: u16,
    pub hskew: u16,
    pub vdisplay: u16,
    pub vsync_start: u16,
    pub vsync_end: u16,
    pub vtotal: u16,
    pub vscan: u16,
    pub vrefresh: u32,
    pub flags: u32,
    pub mode_type: u32,
    pub name: [u8; 32],
}

#[repr(C)]
#[derive(Default)]
struct CardRes {
    fb_id_ptr: u64,
    crtc_id_ptr: u64,
    connector_id_ptr: u64,
    encoder_id_ptr: u64,
    count_fbs: u32,
    count_crtcs: u32,
    count_connectors: u32,
    count_encoders: u32,
    min_width: u32,
    max_width: u32,
    min_height: u32,
    max_height: u32,
}
const DRM_IOCTL_MODE_GETRESOURCES: u64 = iowr(0xA0, std::mem::size_of::<CardRes>());

#[repr(C)]
#[derive(Default)]
struct GetEncoder {
    encoder_id: u32,
    encoder_type: u32,
    crtc_id: u32,
    possible_crtcs: u32,
    possible_clones: u32,
}
const DRM_IOCTL_MODE_GETENCODER: u64 = iowr(0xA6, std::mem::size_of::<GetEncoder>());

#[repr(C)]
#[derive(Default)]
struct GetConnector {
    encoders_ptr: u64,
    modes_ptr: u64,
    props_ptr: u64,
    prop_values_ptr: u64,
    count_modes: u32,
    count_props: u32,
    count_encoders: u32,
    encoder_id: u32,
    connector_id: u32,
    connector_type: u32,
    connector_type_id: u32,
    connection: u32,
    mm_width: u32,
    mm_height: u32,
    subpixel: u32,
    pad: u32,
}
const DRM_IOCTL_MODE_GETCONNECTOR: u64 = iowr(0xA7, std::mem::size_of::<GetConnector>());

#[repr(C)]
#[derive(Default)]
struct Crtc {
    set_connectors_ptr: u64,
    count_connectors: u32,
    crtc_id: u32,
    fb_id: u32,
    x: u32,
    y: u32,
    gamma_size: u32,
    mode_valid: u32,
    mode: ModeInfo,
}
const DRM_IOCTL_MODE_SETCRTC: u64 = iowr(0xA2, std::mem::size_of::<Crtc>());

#[repr(C)]
#[derive(Default)]
struct FbCmd {
    fb_id: u32,
    width: u32,
    height: u32,
    pitch: u32,
    bpp: u32,
    depth: u32,
    handle: u32,
}
const DRM_IOCTL_MODE_ADDFB: u64 = iowr(0xAE, std::mem::size_of::<FbCmd>());
const DRM_IOCTL_MODE_RMFB: u64 = iowr(0xAF, std::mem::size_of::<u32>());

#[repr(C)]
#[derive(Default)]
struct FbDirtyCmd {
    fb_id: u32,
    flags: u32,
    color: u32,
    num_clips: u32,
    clips_ptr: u64,
}
const DRM_IOCTL_MODE_DIRTYFB: u64 = iowr(0xB1, std::mem::size_of::<FbDirtyCmd>());

#[repr(C)]
#[derive(Default)]
struct CreateDumb {
    height: u32,
    width: u32,
    bpp: u32,
    flags: u32,
    handle: u32,
    pitch: u32,
    size: u64,
}
const DRM_IOCTL_MODE_CREATE_DUMB: u64 = iowr(0xB2, std::mem::size_of::<CreateDumb>());

#[repr(C)]
#[derive(Default)]
struct MapDumb {
    handle: u32,
    pad: u32,
    offset: u64,
}
const DRM_IOCTL_MODE_MAP_DUMB: u64 = iowr(0xB3, std::mem::size_of::<MapDumb>());

#[repr(C)]
#[derive(Default)]
struct DestroyDumb {
    handle: u32,
}
const DRM_IOCTL_MODE_DESTROY_DUMB: u64 = iowr(0xB4, std::mem::size_of::<DestroyDumb>());

fn ioctl_call<T>(fd: i32, req: u64, arg: &mut T) -> io::Result<()> {
    let ret = unsafe { ioctl(fd, req, arg as *mut T) };
    if ret < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

/// A connector's current display mode, resolved after a fresh probe.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Mode {
    pub width: u32,
    pub height: u32,
}

struct ScanOut {
    fb_id: u32,
    dumb_handle: u32,
    map: *mut u8,
    map_len: usize,
    pitch: u32,
    width: u32,
    height: u32,
}

pub struct Drm {
    file: File,
    connector_id: u32,
    crtc_id: u32,
    scanout: Option<ScanOut>,
}

impl Drm {
    /// Opens the card and finds the first connected connector, without
    /// scanning it out yet — call `refresh` to (re)probe modes.
    pub fn open(path: &str) -> io::Result<Drm> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(0) // O_CLOEXEC left to std default
            .open(path)?;
        let fd = file.as_raw_fd();
        // Best effort: we're normally the only DRM client in K1OS.
        unsafe { ioctl(fd, DRM_IOCTL_SET_MASTER) };

        let mut drm = Drm {
            file,
            connector_id: 0,
            crtc_id: 0,
            scanout: None,
        };
        drm.connector_id = drm.find_connector()?;
        Ok(drm)
    }

    fn fd(&self) -> i32 {
        self.file.as_raw_fd()
    }

    /// Enumerates connectors and returns the id of the first one that is
    /// (or, if none are connected yet, would be) usable.
    fn find_connector(&self) -> io::Result<u32> {
        let mut res = CardRes::default();
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETRESOURCES, &mut res)?;
        let count = res.count_connectors as usize;
        if count == 0 {
            return Err(io::Error::new(io::ErrorKind::NotFound, "no connectors"));
        }
        let mut ids = vec![0u32; count];
        let mut res2 = CardRes {
            connector_id_ptr: ids.as_mut_ptr() as u64,
            count_connectors: count as u32,
            ..CardRes::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETRESOURCES, &mut res2)?;

        // Prefer an already-connected connector; otherwise take the first one
        // and let `refresh` force-probe it once we start polling.
        let mut fallback = ids[0];
        for &id in &ids {
            if let Ok((connected, _)) = self.probe_connector(id) {
                if connected {
                    return Ok(id);
                }
            }
            fallback = id;
        }
        Ok(fallback)
    }

    /// Force-probes a connector (a from-scratch GETCONNECTOR call always
    /// makes the kernel re-check EDID/hotplug state, exactly like a normal
    /// DRM client such as an Xorg/Wayland compositor would) and returns
    /// whether it's connected plus its current mode list.
    fn probe_connector(&self, connector_id: u32) -> io::Result<(bool, Vec<ModeInfo>)> {
        let mut gc = GetConnector {
            connector_id,
            ..GetConnector::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETCONNECTOR, &mut gc)?;
        let connected = gc.connection == DRM_MODE_CONNECTED;
        let n_modes = gc.count_modes as usize;
        if n_modes == 0 {
            return Ok((connected, Vec::new()));
        }
        let mut modes = vec![ModeInfo::default(); n_modes];
        let mut encoders = vec![0u32; gc.count_encoders as usize];
        let mut gc2 = GetConnector {
            connector_id,
            modes_ptr: modes.as_mut_ptr() as u64,
            count_modes: n_modes as u32,
            encoders_ptr: if encoders.is_empty() {
                0
            } else {
                encoders.as_mut_ptr() as u64
            },
            count_encoders: encoders.len() as u32,
            ..GetConnector::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETCONNECTOR, &mut gc2)?;
        Ok((gc2.connection == DRM_MODE_CONNECTED, modes))
    }

    fn resolve_crtc(&self, connector_id: u32) -> io::Result<u32> {
        let mut gc = GetConnector {
            connector_id,
            ..GetConnector::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETCONNECTOR, &mut gc)?;
        let mut encoders = vec![0u32; gc.count_encoders as usize];
        let mut gc2 = GetConnector {
            connector_id,
            encoders_ptr: if encoders.is_empty() {
                0
            } else {
                encoders.as_mut_ptr() as u64
            },
            count_encoders: encoders.len() as u32,
            ..GetConnector::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETCONNECTOR, &mut gc2)?;

        let mut res = CardRes::default();
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETRESOURCES, &mut res)?;
        let mut crtc_ids = vec![0u32; res.count_crtcs as usize];
        let mut res2 = CardRes {
            crtc_id_ptr: crtc_ids.as_mut_ptr() as u64,
            count_crtcs: crtc_ids.len() as u32,
            ..CardRes::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_GETRESOURCES, &mut res2)?;

        // Prefer the encoder's already-bound crtc; if there is none, or the
        // connector reports none, fall back to the first crtc the encoder
        // says it can drive.
        for &enc_id in encoders.iter().chain(std::iter::once(&gc2.encoder_id)) {
            if enc_id == 0 {
                continue;
            }
            let mut ge = GetEncoder {
                encoder_id: enc_id,
                ..GetEncoder::default()
            };
            if ioctl_call(self.fd(), DRM_IOCTL_MODE_GETENCODER, &mut ge).is_err() {
                continue;
            }
            if ge.crtc_id != 0 {
                return Ok(ge.crtc_id);
            }
            for (i, &crtc_id) in crtc_ids.iter().enumerate() {
                if ge.possible_crtcs & (1 << i) != 0 {
                    return Ok(crtc_id);
                }
            }
        }
        Err(io::Error::new(io::ErrorKind::NotFound, "no usable crtc"))
    }

    fn pick_mode(modes: &[ModeInfo]) -> Option<ModeInfo> {
        modes
            .iter()
            .find(|m| m.mode_type & DRM_MODE_TYPE_PREFERRED != 0)
            .or_else(|| {
                modes
                    .iter()
                    .max_by_key(|m| m.hdisplay as u32 * m.vdisplay as u32)
            })
            .copied()
    }

    /// Re-probes the connector and, if the display's current mode differs
    /// from what's scanned out (or nothing is scanned out yet), tears down
    /// the old framebuffer and scans out a fresh dumb buffer at the new
    /// size. Returns the active mode, or `None` if nothing is connected.
    ///
    /// This is the whole fix for "K1OS ignores the QEMU window size": a real
    /// desktop re-probes on every hotplug uevent instead of trusting the
    /// mode it found at boot, and this does the same thing on a timer.
    pub fn refresh(&mut self) -> io::Result<Option<Mode>> {
        let (connected, modes) = self.probe_connector(self.connector_id)?;
        if !connected || modes.is_empty() {
            self.teardown_scanout();
            return Ok(None);
        }
        let mode = Self::pick_mode(&modes).expect("non-empty mode list");
        let (w, h) = (mode.hdisplay as u32, mode.vdisplay as u32);

        if let Some(so) = &self.scanout {
            if so.width == w && so.height == h {
                return Ok(Some(Mode {
                    width: w,
                    height: h,
                }));
            }
        }

        self.crtc_id = self.resolve_crtc(self.connector_id)?;
        self.teardown_scanout();
        self.scanout_mode(&mode)?;
        Ok(Some(Mode {
            width: w,
            height: h,
        }))
    }

    fn scanout_mode(&mut self, mode: &ModeInfo) -> io::Result<()> {
        let (w, h) = (mode.hdisplay as u32, mode.vdisplay as u32);

        let mut cd = CreateDumb {
            width: w,
            height: h,
            bpp: 32,
            ..CreateDumb::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_CREATE_DUMB, &mut cd)?;

        let mut fb = FbCmd {
            width: w,
            height: h,
            pitch: cd.pitch,
            bpp: 32,
            depth: 24,
            handle: cd.handle,
            ..FbCmd::default()
        };
        if let Err(e) = ioctl_call(self.fd(), DRM_IOCTL_MODE_ADDFB, &mut fb) {
            let mut dd = DestroyDumb { handle: cd.handle };
            let _ = ioctl_call(self.fd(), DRM_IOCTL_MODE_DESTROY_DUMB, &mut dd);
            return Err(e);
        }

        let mut md = MapDumb {
            handle: cd.handle,
            ..MapDumb::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_MAP_DUMB, &mut md)?;

        let map_len = cd.size as usize;
        let map = unsafe {
            mmap(
                std::ptr::null_mut(),
                map_len,
                PROT_READ | PROT_WRITE,
                MAP_SHARED,
                self.fd(),
                md.offset as i64,
            )
        };
        if map == MAP_FAILED {
            let e = io::Error::last_os_error();
            let mut dd = DestroyDumb { handle: cd.handle };
            let _ = ioctl_call(self.fd(), DRM_IOCTL_MODE_DESTROY_DUMB, &mut dd);
            return Err(e);
        }
        unsafe { std::ptr::write_bytes(map as *mut u8, 0, map_len) };

        // Connector id array must outlive the ioctl call below.
        let conn_ids = [self.connector_id];
        let mut crtc = Crtc {
            crtc_id: self.crtc_id,
            fb_id: fb.fb_id,
            set_connectors_ptr: conn_ids.as_ptr() as u64,
            count_connectors: 1,
            mode_valid: 1,
            mode: *mode,
            ..Crtc::default()
        };
        ioctl_call(self.fd(), DRM_IOCTL_MODE_SETCRTC, &mut crtc)?;

        self.scanout = Some(ScanOut {
            fb_id: fb.fb_id,
            dumb_handle: cd.handle,
            map: map as *mut u8,
            map_len,
            pitch: cd.pitch,
            width: w,
            height: h,
        });
        Ok(())
    }

    fn teardown_scanout(&mut self) {
        if let Some(so) = self.scanout.take() {
            unsafe { munmap(so.map as *mut std::ffi::c_void, so.map_len) };
            let mut fb_id = so.fb_id;
            unsafe { ioctl(self.fd(), DRM_IOCTL_MODE_RMFB, &mut fb_id as *mut u32) };
            let mut dd = DestroyDumb {
                handle: so.dumb_handle,
            };
            unsafe { ioctl(self.fd(), DRM_IOCTL_MODE_DESTROY_DUMB, &mut dd) };
        }
    }

    /// Raw framebuffer as `(pixels_bgrx8888, pitch_bytes, width, height)`.
    pub fn framebuffer(&mut self) -> Option<(&mut [u8], u32, u32, u32)> {
        let so = self.scanout.as_ref()?;
        let slice = unsafe { std::slice::from_raw_parts_mut(so.map, so.map_len) };
        Some((slice, so.pitch, so.width, so.height))
    }

    /// Tells the kernel/host (virtio-gpu forwards this to the QEMU window)
    /// that the whole framebuffer changed.
    pub fn flush(&self) {
        if let Some(so) = &self.scanout {
            let mut dirty = FbDirtyCmd {
                fb_id: so.fb_id,
                ..FbDirtyCmd::default()
            };
            unsafe { ioctl(self.fd(), DRM_IOCTL_MODE_DIRTYFB, &mut dirty as *mut FbDirtyCmd) };
        }
    }
}

impl Drop for Drm {
    fn drop(&mut self) {
        self.teardown_scanout();
        unsafe { ioctl(self.fd(), DRM_IOCTL_DROP_MASTER) };
    }
}
