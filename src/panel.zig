//! The status panel right of the table view (#10 makes it a real one).
const std = @import("std");
const platform = @import("platform.zig");
const layout = @import("layout.zig");
const render = @import("render.zig");
const Game = @import("game.zig").Game;

pub fn draw(g: *const Game, pixels: []u32) void {
    const cv = render.Canvas{ .pixels = pixels, .w = platform.width, .h = platform.height };
    cv.rect(layout.panel.x, 0, layout.panel.w, layout.panel.h, 0x202020);
    var buf: [32]u8 = undefined;
    const px = layout.panel.x + 16;
    cv.text("DOOMBALL", px, 20, 3, 0xb01010);
    cv.text(std.mem.print(&buf, "SCORE {d}", .{g.score}) catch "", px, 60, 2, 0xe8c030);
    cv.text(std.mem.print(&buf, "BALLS {d}", .{g.balls_left}) catch "", px, 80, 2, 0xe8c030);
    if (g.phase == .game_over) {
        cv.text("GAME OVER", px, 120, 2, 0xb01010);
        cv.text("PRESS ENTER", px, 140, 2, 0xe8c030);
    }
}
