//! Platform abstraction, in the spirit of doomgeneric: the game core only
//! produces a 32-bit framebuffer and consumes a small Input snapshot. A port
//! to a new OS only needs to implement the functions in `Platform`.

pub const width = 640;
pub const height = 480;

pub const Input = struct {
    left: bool = false,
    right: bool = false,
    plunger: bool = false,
    start: bool = false,
    quit: bool = false,
};

pub const Platform = struct {
    /// Open a window / device that can show a `width` x `height` framebuffer.
    init: *const fn () anyerror!void,
    shutdown: *const fn () void,
    /// Monotonic milliseconds.
    ticksMs: *const fn () u64,
    sleepMs: *const fn (ms: u32) void,
    /// Pump OS events and return the current input state.
    pollInput: *const fn () Input,
    /// Show a frame of 0x00RRGGBB pixels, row-major, `width * height` entries.
    present: *const fn (pixels: []const u32) void,
};
