//! Windows backend using plain Win32 + GDI (no third-party dependencies).
const std = @import("std");
const platform = @import("platform.zig");

const WINAPI: std.lang.CallingConvention = .winapi;
const HWND = *anyopaque;
const HINSTANCE = *anyopaque;
const HDC = *anyopaque;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;

const WNDPROC = *const fn (HWND, u32, WPARAM, LPARAM) callconv(WINAPI) LRESULT;
const POINT = extern struct { x: i32, y: i32 };
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const MSG = extern struct { hwnd: ?HWND, message: u32, wParam: WPARAM, lParam: LPARAM, time: u32, pt: POINT };
const WNDCLASSEXW = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXW),
    style: u32 = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hInstance: ?HINSTANCE,
    hIcon: ?*anyopaque = null,
    hCursor: ?*anyopaque = null,
    hbrBackground: ?*anyopaque = null,
    lpszMenuName: ?[*:0]const u16 = null,
    lpszClassName: [*:0]const u16,
    hIconSm: ?*anyopaque = null,
};
const BITMAPINFOHEADER = extern struct {
    biSize: u32 = @sizeOf(BITMAPINFOHEADER),
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16 = 1,
    biBitCount: u16 = 32,
    biCompression: u32 = 0,
    biSizeImage: u32 = 0,
    biXPelsPerMeter: i32 = 0,
    biYPelsPerMeter: i32 = 0,
    biClrUsed: u32 = 0,
    biClrImportant: u32 = 0,
};

extern "kernel32" fn GetModuleHandleW(?[*:0]const u16) callconv(WINAPI) ?HINSTANCE;
extern "user32" fn RegisterClassExW(*const WNDCLASSEXW) callconv(WINAPI) u16;
extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?HWND, ?*anyopaque, ?HINSTANCE, ?*anyopaque) callconv(WINAPI) ?HWND;
extern "user32" fn DefWindowProcW(HWND, u32, WPARAM, LPARAM) callconv(WINAPI) LRESULT;
extern "user32" fn DestroyWindow(HWND) callconv(WINAPI) i32;
extern "user32" fn PostQuitMessage(i32) callconv(WINAPI) void;
extern "user32" fn PeekMessageW(*MSG, ?HWND, u32, u32, u32) callconv(WINAPI) i32;
extern "user32" fn TranslateMessage(*const MSG) callconv(WINAPI) i32;
extern "user32" fn DispatchMessageW(*const MSG) callconv(WINAPI) LRESULT;
extern "user32" fn ShowWindow(HWND, i32) callconv(WINAPI) i32;
extern "user32" fn AdjustWindowRect(*RECT, u32, i32) callconv(WINAPI) i32;
extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(WINAPI) ?*anyopaque;
extern "user32" fn GetDC(HWND) callconv(WINAPI) ?HDC;
extern "user32" fn ReleaseDC(HWND, HDC) callconv(WINAPI) i32;
extern "gdi32" fn StretchDIBits(HDC, i32, i32, i32, i32, i32, i32, i32, i32, *const anyopaque, *const BITMAPINFOHEADER, u32, u32) callconv(WINAPI) i32;
extern "kernel32" fn GetTickCount64() callconv(WINAPI) u64;
extern "kernel32" fn Sleep(u32) callconv(WINAPI) void;
extern "winmm" fn timeBeginPeriod(u32) callconv(WINAPI) u32;
extern "winmm" fn timeEndPeriod(u32) callconv(WINAPI) u32;
extern "winmm" fn waveOutOpen(*?*anyopaque, u32, *const WAVEFORMATEX, usize, usize, u32) callconv(WINAPI) u32;
extern "winmm" fn waveOutPrepareHeader(*anyopaque, *WAVEHDR, u32) callconv(WINAPI) u32;
extern "winmm" fn waveOutUnprepareHeader(*anyopaque, *WAVEHDR, u32) callconv(WINAPI) u32;
extern "winmm" fn waveOutWrite(*anyopaque, *WAVEHDR, u32) callconv(WINAPI) u32;
extern "winmm" fn waveOutReset(*anyopaque) callconv(WINAPI) u32;
extern "winmm" fn waveOutClose(*anyopaque) callconv(WINAPI) u32;

const WAVEFORMATEX = extern struct {
    wFormatTag: u16 = 1,
    nChannels: u16 = 1,
    nSamplesPerSec: u32 = platform.audio_rate,
    nAvgBytesPerSec: u32 = platform.audio_rate * 2,
    nBlockAlign: u16 = 2,
    wBitsPerSample: u16 = 16,
    cbSize: u16 = 0,
};
const WAVEHDR = extern struct {
    lpData: [*]u8,
    dwBufferLength: u32,
    dwBytesRecorded: u32 = 0,
    dwUser: usize = 0,
    dwFlags: u32 = 0,
    dwLoops: u32 = 0,
    lpNext: ?*WAVEHDR = null,
    reserved: usize = 0,
};
const WAVE_MAPPER: u32 = 0xFFFFFFFF;
const WHDR_DONE = 1;

const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_SYSKEYDOWN = 0x0104;
const WM_SYSKEYUP = 0x0105;
const PM_REMOVE = 1;
const WS_STYLE: u32 = 0x00C00000 | 0x00080000 | 0x00020000 | 0x10000000; // caption|sysmenu|minimize|visible
const VK_SHIFT = 0x10;
const VK_RETURN = 0x0D;
const VK_ESCAPE = 0x1B;
const VK_SPACE = 0x20;
const VK_LEFT = 0x25;
const VK_RIGHT = 0x27;
const VK_Z = 0x5A;
const VK_SLASH = 0xBF;
const VK_LSHIFT = 0xA0;
const VK_RSHIFT = 0xA1;

var hwnd: ?HWND = null;

// sound: a ring of buffers handed to waveOut, refilled once played
const audio_buffers = 8;
const audio_cap = 2048;
var wave: ?*anyopaque = null;
var buffers: [audio_buffers][audio_cap]i16 = undefined;
var headers: [audio_buffers]WAVEHDR = undefined;
var queued: [audio_buffers]bool = @splat(false);
var keys: [256]bool = @splat(false);
var quit = false;

pub const impl = platform.Platform{
    .init = init,
    .shutdown = shutdown,
    .ticksMs = ticksMs,
    .sleepMs = sleepMs,
    .pollInput = pollInput,
    .present = present,
    .queueAudio = queueAudio,
};

fn wndProc(h: HWND, msg: u32, wp: WPARAM, lp: LPARAM) callconv(WINAPI) LRESULT {
    switch (msg) {
        WM_KEYDOWN, WM_SYSKEYDOWN => {
            setKey(wp, lp, true);
            return 0;
        },
        WM_KEYUP, WM_SYSKEYUP => {
            setKey(wp, lp, false);
            return 0;
        },
        WM_CLOSE => {
            quit = true;
            _ = DestroyWindow(h);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcW(h, msg, wp, lp),
    }
}

/// Both Shift keys arrive as VK_SHIFT; the scan code tells them apart.
fn setKey(wp: WPARAM, lp: LPARAM, down: bool) void {
    const scan_rshift = 0x36;
    const vk: WPARAM = if (wp == VK_SHIFT)
        (if ((lp >> 16) & 0xFF == scan_rshift) VK_RSHIFT else VK_LSHIFT)
    else
        wp;
    if (vk < keys.len) keys[vk] = down;
}

fn init() anyerror!void {
    const inst = GetModuleHandleW(null);
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("DoomballWindow");
    const wc = WNDCLASSEXW{
        .lpfnWndProc = wndProc,
        .hInstance = inst,
        .hCursor = LoadCursorW(null, 32512),
        .lpszClassName = class_name,
    };
    if (RegisterClassExW(&wc) == 0) return error.RegisterClassFailed;

    var r = RECT{ .left = 0, .top = 0, .right = platform.width, .bottom = platform.height };
    _ = AdjustWindowRect(&r, WS_STYLE, 0);
    hwnd = CreateWindowExW(0, class_name, std.unicode.utf8ToUtf16LeStringLiteral("Doomball"), WS_STYLE, 100, 50, r.right - r.left, r.bottom - r.top, null, null, inst, null);
    if (hwnd == null) return error.CreateWindowFailed;
    _ = ShowWindow(hwnd.?, 5);
    _ = timeBeginPeriod(1);
    openAudio();
}

fn shutdown() void {
    if (wave) |w| {
        _ = waveOutReset(w);
        for (&headers, &queued) |*hd, *q| if (q.*) {
            _ = waveOutUnprepareHeader(w, hd, @sizeOf(WAVEHDR));
            q.* = false;
        };
        _ = waveOutClose(w);
        wave = null;
    }
    _ = timeEndPeriod(1);
}

/// No sound device leaves the game silent.
fn openAudio() void {
    const fmt = WAVEFORMATEX{};
    if (waveOutOpen(&wave, WAVE_MAPPER, &fmt, 0, 0, 0) != 0) {
        wave = null;
        return;
    }
    // a little silence ahead, so a late frame does not starve the device
    const silence: [512]i16 = @splat(0);
    queueAudio(&silence);
    queueAudio(&silence);
}

fn queueAudio(samples: []const i16) void {
    const w = wave orelse return;
    var free: ?usize = null;
    for (&headers, &queued, 0..) |*hd, *q, i| {
        if (q.* and hd.dwFlags & WHDR_DONE != 0) {
            _ = waveOutUnprepareHeader(w, hd, @sizeOf(WAVEHDR));
            q.* = false;
        }
        if (!q.* and free == null) free = i;
    }
    const i = free orelse return;
    const n = @min(samples.len, audio_cap);
    @memcpy(buffers[i][0..n], samples[0..n]);
    headers[i] = .{ .lpData = @ptrCast(&buffers[i]), .dwBufferLength = @intCast(n * 2) };
    if (waveOutPrepareHeader(w, &headers[i], @sizeOf(WAVEHDR)) != 0) return;
    if (waveOutWrite(w, &headers[i], @sizeOf(WAVEHDR)) != 0) {
        _ = waveOutUnprepareHeader(w, &headers[i], @sizeOf(WAVEHDR));
        return;
    }
    queued[i] = true;
}

fn ticksMs() u64 {
    return GetTickCount64();
}

fn sleepMs(ms: u32) void {
    Sleep(ms);
}

fn pollInput() platform.Input {
    var msg: MSG = undefined;
    while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }
    return .{
        .left = keys[VK_LEFT] or keys[VK_Z] or keys[VK_LSHIFT],
        .right = keys[VK_RIGHT] or keys[VK_SLASH] or keys[VK_RSHIFT],
        .plunger = keys[VK_SPACE],
        .start = keys[VK_RETURN],
        .quit = quit or keys[VK_ESCAPE],
    };
}

fn present(pixels: []const u32) void {
    const h = hwnd orelse return;
    const dc = GetDC(h) orelse return;
    defer _ = ReleaseDC(h, dc);
    const bmi = BITMAPINFOHEADER{ .biWidth = platform.width, .biHeight = -platform.height };
    _ = StretchDIBits(dc, 0, 0, platform.width, platform.height, 0, 0, platform.width, platform.height, pixels.ptr, &bmi, 0, 0x00CC0020);
}
