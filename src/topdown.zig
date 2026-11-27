//! A flat top-down drawing of the table, until the 2.5D renderer (#8).
const std = @import("std");
const platform = @import("platform.zig");
const layout = @import("layout.zig");
const table = @import("table.zig");
const render = @import("render.zig");
const Game = @import("game.zig").Game;

const scale: f32 = @as(f32, layout.view.h) / (table.drain_y - 0);
const ox: f32 = @as(f32, @floatFromInt(layout.view.x)) + (@as(f32, @floatFromInt(layout.view.w)) - table.width * scale) / 2;

fn sx(x: f32) f32 {
    return ox + x * scale;
}

fn sy(y: f32) f32 {
    return y * scale;
}

pub fn draw(g: *const Game, pixels: []u32) void {
    @memset(pixels, 0x140a06);
    const cv = render.Canvas{ .pixels = pixels, .w = platform.width, .h = platform.height };
    const pit = table.pit;
    cv.rect(@intFromFloat(sx(pit.x0)), @intFromFloat(sy(pit.y0)), @intFromFloat((pit.x1 - pit.x0) * scale), @intFromFloat((pit.y1 - pit.y0) * scale), 0x3a1004);

    for (table.walls) |w| {
        const c: u32 = switch (w.kind) {
            .wall => 0x8a8a8a,
            .rubber => 0xb0b0b0,
            .sling => 0xff8a1a,
            .oneway => 0x606060,
        };
        cv.line(sx(w.a.x), sy(w.a.y), sx(w.b.x), sy(w.b.y), w.r * scale, c);
    }
    if (g.world.gate_closed) cv.line(sx(table.gate.a.x), sy(table.gate.a.y), sx(table.gate.b.x), sy(table.gate.b.y), table.gate.r * scale, 0x606060);
    cv.disc(sx(table.lock_c.x), sy(table.lock_c.y), table.lock_r * scale, 0x202020);
    for (table.rollovers, g.lanes_lit) |ro, lit| cv.disc(sx(ro.c.x), sy(ro.c.y), 4, if (lit) 0xffe040 else 0x504010);
    for (table.targets, g.target_flash) |t, f| {
        const c: u32 = switch (t.kind) {
            .key_red => 0xd02020,
            .key_blue => 0x3050e0,
            .key_yellow => 0xe0c020,
            .mission => 0x30d040,
        };
        cv.line(sx(t.a.x), sy(t.a.y), sx(t.b.x), sy(t.b.y), t.r * scale + if (f > 0) @as(f32, 1) else 0, c);
    }
    for (table.bumpers, g.bumper_flash) |b, f| {
        cv.disc(sx(b.c.x), sy(b.c.y), b.r * scale, if (f > 0) 0xffb040 else 0xa01010);
        cv.disc(sx(b.c.x), sy(b.c.y), b.r * scale * 0.6, 0x500808);
    }
    for (g.world.flippers) |f| {
        const t = f.tip();
        cv.line(sx(f.spec.pivot.x), sy(f.spec.pivot.y), sx(t.x), sy(t.y), table.flipper_r1 * scale, 0x4a8a3a);
    }
    const pl: i32 = @intFromFloat(g.plunger * 10);
    cv.rect(@intFromFloat(sx(362)), @as(i32, @intFromFloat(sy(792))) + pl, @intFromFloat(16 * scale), 3, 0xaaaaaa);
    for (g.world.balls) |b| {
        if (!b.active) continue;
        cv.disc(sx(b.p.x), sy(b.p.y), table.ball_r * scale, 0xd0d0e0);
    }

    // panel placeholder until #10
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
