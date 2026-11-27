//! Headless backend: scripted input, no window. Dumps the last frame as a PPM
//! image (doomball.ppm) on shutdown. Useful for CI and as a porting template.
const std = @import("std");
const platform = @import("platform.zig");

var frame: u64 = 0;
var last: [platform.width * platform.height]u32 = undefined;
pub var max_frames: u64 = 600;
pub var io: std.Io = undefined;

pub const impl = platform.Platform{
    .init = init,
    .shutdown = shutdown,
    .ticksMs = ticksMs,
    .sleepMs = sleepMs,
    .pollInput = pollInput,
    .present = present,
};

fn init() anyerror!void {}

fn ticksMs() u64 {
    return frame * 1000 / 60;
}

fn sleepMs(_: u32) void {}

fn pollInput() platform.Input {
    const f = frame % 180;
    return .{
        .plunger = f < 70,
        .left = (frame / 15) % 2 == 0,
        .right = (frame / 15) % 2 == 1,
        .quit = frame >= max_frames,
    };
}

fn present(pixels: []const u32) void {
    frame += 1;
    @memcpy(&last, pixels);
}

var ppm: [header_max + platform.width * platform.height * 3]u8 = undefined;
const header_max = 32;

fn shutdown() void {
    const header = std.mem.print(&ppm, "P6\n{d} {d}\n255\n", .{ platform.width, platform.height }) catch return;
    var n = header.len;
    for (last) |px| {
        ppm[n] = @truncate(px >> 16);
        ppm[n + 1] = @truncate(px >> 8);
        ppm[n + 2] = @truncate(px);
        n += 3;
    }
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "doomball.ppm", .data = ppm[0..n] }) catch return;
}
