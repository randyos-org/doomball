//! Headless backend: scripted input, no window. Dumps the last frame as a PPM
//! image (doomball.ppm) on shutdown. Useful for CI and as a porting template.
const std = @import("std");
const platform = @import("platform.zig");

var frame: u64 = 0;
var last: [platform.width * platform.height]u32 = undefined;
pub var max_frames: u64 = 600;

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

fn shutdown() void {
    const file = std.fs.cwd().createFile("doomball.ppm", .{}) catch return;
    defer file.close();
    var bw = std.io.bufferedWriter(file.writer());
    const w = bw.writer();
    w.print("P6\n{d} {d}\n255\n", .{ platform.width, platform.height }) catch return;
    for (last) |px| {
        w.writeAll(&.{ @truncate(px >> 16), @truncate(px >> 8), @truncate(px) }) catch return;
    }
    bw.flush() catch return;
}
