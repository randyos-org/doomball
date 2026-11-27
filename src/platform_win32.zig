//! Windows backend using plain Win32 + GDI (no third-party dependencies).
const std = @import("std");
const win = std.os.windows;
const platform = @import("platform.zig");

const WINAPI = win.WINAPI;
const HWND = win.HWND;
const HINSTANCE = win.HINSTANCE;

const scale = 3;

const WNDPROC = *const fn (HWND, u32, win.WPARAM, win.LPARAM) callconv(WINAPI) win.LRESULT;
const POINT = extern struct { x: i32, y: i32 };
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const MSG = extern struct { hwnd: ?HWND, message: u32, wParam: win.WPARAM, lParam: win.LPARAM, time: u32, pt: POINT };
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
extern "user32" fn DefWindowProcW(HWND, u32, win.WPARAM, win.LPARAM) callconv(WINAPI) win.LRESULT;
extern "user32" fn DestroyWindow(HWND) callconv(WINAPI) i32;
extern "user32" fn PostQuitMessage(i32) callconv(WINAPI) void;
extern "user32" fn PeekMessageW(*MSG, ?HWND, u32, u32, u32) callconv(WINAPI) i32;
extern "user32" fn TranslateMessage(*const MSG) callconv(WINAPI) i32;
extern "user32" fn DispatchMessageW(*const MSG) callconv(WINAPI) win.LRESULT;
extern "user32" fn ShowWindow(HWND, i32) callconv(WINAPI) i32;
extern "user32" fn AdjustWindowRect(*RECT, u32, i32) callconv(WINAPI) i32;
extern "user32" fn LoadCursorW(?HINSTANCE, usize) callconv(WINAPI) ?*anyopaque;
extern "user32" fn GetDC(HWND) callconv(WINAPI) ?win.HDC;
extern "user32" fn ReleaseDC(HWND, win.HDC) callconv(WINAPI) i32;
extern "gdi32" fn StretchDIBits(win.HDC, i32, i32, i32, i32, i32, i32, i32, i32, *const anyopaque, *const BITMAPINFOHEADER, u32, u32) callconv(WINAPI) i32;
extern "winmm" fn timeBeginPeriod(u32) callconv(WINAPI) u32;
extern "winmm" fn timeEndPeriod(u32) callconv(WINAPI) u32;

const WM_DESTROY = 0x0002;
const WM_CLOSE = 0x0010;
const WM_KEYDOWN = 0x0100;
const WM_KEYUP = 0x0101;
const WM_SYSKEYDOWN = 0x0104;
const WM_SYSKEYUP = 0x0105;
const PM_REMOVE = 1;
const WS_STYLE: u32 = 0x00C00000 | 0x00080000 | 0x00020000 | 0x10000000; // caption|sysmenu|minimize|visible
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
var keys = [_]bool{false} ** 256;
var quit = false;

pub const impl = platform.Platform{
    .init = init,
    .shutdown = shutdown,
    .ticksMs = ticksMs,
    .sleepMs = sleepMs,
    .pollInput = pollInput,
    .present = present,
};

fn wndProc(h: HWND, msg: u32, wp: win.WPARAM, lp: win.LPARAM) callconv(WINAPI) win.LRESULT {
    switch (msg) {
        WM_KEYDOWN, WM_SYSKEYDOWN => {
            if (wp < keys.len) keys[wp] = true;
            return 0;
        },
        WM_KEYUP, WM_SYSKEYUP => {
            if (wp < keys.len) keys[wp] = false;
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

    var r = RECT{ .left = 0, .top = 0, .right = platform.width * scale, .bottom = platform.height * scale };
    _ = AdjustWindowRect(&r, WS_STYLE, 0);
    hwnd = CreateWindowExW(0, class_name, std.unicode.utf8ToUtf16LeStringLiteral("Doomball"), WS_STYLE, 100, 50, r.right - r.left, r.bottom - r.top, null, null, inst, null);
    if (hwnd == null) return error.CreateWindowFailed;
    _ = ShowWindow(hwnd.?, 5);
    _ = timeBeginPeriod(1);
}

fn shutdown() void {
    _ = timeEndPeriod(1);
}

fn ticksMs() u64 {
    return @intCast(std.time.milliTimestamp());
}

fn sleepMs(ms: u32) void {
    std.time.sleep(@as(u64, ms) * std.time.ns_per_ms);
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
    _ = StretchDIBits(dc, 0, 0, platform.width * scale, platform.height * scale, 0, 0, platform.width, platform.height, pixels.ptr, &bmi, 0, 0x00CC0020);
}
