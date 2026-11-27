const std = @import("std");
const build_options = @import("build_options");
const platform = @import("platform.zig");
const game = @import("game.zig");

const backend = switch (build_options.backend) {
    .win32 => @import("platform_win32.zig"),
    .headless => @import("platform_headless.zig"),
};

const frame_ms: u64 = 1000 / 60;

pub fn main() !void {
    const p = backend.impl;
    if (build_options.backend == .headless) {
        var args = std.process.args();
        _ = args.skip();
        if (args.next()) |a| backend.max_frames = std.fmt.parseInt(u64, a, 10) catch backend.max_frames;
    }

    try p.init();
    defer p.shutdown();

    var g = game.Game{};
    var fb: [platform.width * platform.height]u32 = undefined;
    var next = p.ticksMs();
    while (true) {
        const in = p.pollInput();
        if (in.quit) break;
        g.update(in, 1.0 / 60.0);
        g.render(&fb);
        p.present(&fb);

        next += frame_ms;
        const now = p.ticksMs();
        if (next > now) p.sleepMs(@intCast(next - now)) else next = now;
    }
}
