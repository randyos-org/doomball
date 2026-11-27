const std = @import("std");
const build_options = @import("build_options");
const platform = @import("platform.zig");
const game = @import("game.zig");
const frame = @import("frame.zig");

const backend = switch (build_options.backend) {
    .win32 => @import("platform_win32.zig"),
    .headless => @import("platform_headless.zig"),
};

const frame_ms: u64 = 1000 / 60;

// 1.2 MB: too big for the main thread's stack
var fb: [platform.width * platform.height]u32 = undefined;

pub fn main(init: std.process.Init) !void {
    const p = backend.impl;
    if (build_options.backend == .headless) {
        backend.io = init.io;
        const args = try init.minimal.args.toSlice(init.arena.allocator());
        if (args.len > 1) backend.max_frames = std.fmt.parseInt(u64, args[1], 10) catch backend.max_frames;
    }

    // the table is rendered before the window opens, which would not answer meanwhile
    var renderer = try frame.Renderer.init(init.gpa);
    defer renderer.deinit(init.gpa);

    try p.init();
    defer p.shutdown();

    var g = game.Game.init();
    var next = p.ticksMs();
    while (true) {
        const in = p.pollInput();
        if (in.quit) break;
        g.update(in, 1.0 / 60.0);
        renderer.draw(&g, &fb);
        p.present(&fb);

        next += frame_ms;
        const now = p.ticksMs();
        if (next > now) p.sleepMs(@intCast(next - now)) else next = now;
    }
}
