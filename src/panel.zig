//! The status panel right of the table view: a steel frame with recessed
//! displays for the score, the ball, the rank, the mission, the keys,
//! demons slain and the message log.
const std = @import("std");
const platform = @import("platform.zig");
const layout = @import("layout.zig");
const pal = @import("palette.zig");
const tex = @import("textures.zig");
const font = @import("font.zig");
const game = @import("game.zig");

const Game = game.Game;
const stride = platform.width;
const px0: usize = @intCast(layout.panel.x);
const pw: usize = @intCast(layout.panel.w);

fn c(r: pal.Ramp, s: u4) u32 {
    return pal.rgb[pal.index(r, s)];
}

const label = c(.steel, 10);
const value = c(.yellow, 13);
const led_on = c(.blood, 15);
const led_off = c(.crimson, 2);

fn fill(pixels: []u32, x: usize, y: usize, w: usize, h: usize, color: u32) void {
    for (y..y + h) |yy| @memset(pixels[yy * stride + x ..][0..w], color);
}

/// A recessed display: dark inside, shadowed at the top left, lit at the
/// bottom right.
fn well(pixels: []u32, x: usize, y: usize, w: usize, h: usize) void {
    fill(pixels, x, y, w, h, c(.gray, 0));
    fill(pixels, x, y, w, 1, c(.steel, 2));
    fill(pixels, x, y, 1, h, c(.steel, 2));
    fill(pixels, x, y + h - 1, w, 1, c(.steel, 11));
    fill(pixels, x + w - 1, y, 1, h, c(.steel, 11));
}

fn text(pixels: []u32, x: usize, y: usize, s: []const u8, scale: usize, color: u32) void {
    font.draw(pixels, stride, x, y, s, scale, color);
}

fn centered(pixels: []u32, y: usize, s: []const u8, scale: usize, color: u32) void {
    text(pixels, px0 + (pw -| font.width(s, scale)) / 2, y, s, scale, color);
}

// segments a to g, bit 0 to 6, of 0 to 9
const segments = [10]u7{ 0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f };

fn digit(pixels: []u32, x: usize, y: usize, d: ?u4) void {
    const dw = 16;
    const dh = 32;
    const t = 3;
    const half = dh / 2;
    const bars = [7][4]usize{
        .{ x + 2, y, dw - 4, t },
        .{ x + dw - t, y + 2, t, half - 3 },
        .{ x + dw - t, y + half + 1, t, half - 3 },
        .{ x + 2, y + dh - t, dw - 4, t },
        .{ x, y + half + 1, t, half - 3 },
        .{ x, y + 2, t, half - 3 },
        .{ x + 2, y + half - 1, dw - 4, t },
    };
    const on: u7 = if (d) |v| segments[v] else 0;
    for (bars, 0..) |r, i| fill(pixels, r[0], r[1], r[2], r[3], if ((on >> @intCast(i)) & 1 == 1) led_on else led_off);
}

/// A key icon, 9x5 cells.
const key_icon = [_][]const u8{ ".###.....", "#...#....", "#...#####", "#...#.#.#", ".###..#.#" };
const skull_icon = [_][]const u8{ ".#####.", "#######", "#..#..#", "#######", ".#.#.#.", ".#####." };

fn icon(pixels: []u32, x: usize, y: usize, rows: []const []const u8, scale: usize, color: u32) void {
    for (rows, 0..) |row, ry| for (row, 0..) |ch, rx| {
        if (ch == '#') fill(pixels, x + rx * scale, y + ry * scale, scale, scale, color);
    };
}

pub fn draw(g: *const Game, pixels: []u32) void {
    for (0..platform.height) |y| for (0..pw) |x| {
        pixels[y * stride + px0 + x] = pal.lit(tex.texel(.tech, @intCast(x), @intCast(y)), 15);
    };
    fill(pixels, px0, 0, 2, platform.height, c(.steel, 1));

    const title = "DOOMBALL";
    const tx = px0 + (pw - font.width(title, 3)) / 2;
    text(pixels, tx + 2, 12, title, 3, c(.blood, 2));
    text(pixels, tx, 10, title, 3, c(.blood, 13));

    // the score, nine LED digits
    well(pixels, px0 + 10, 44, pw - 20, 46);
    var digits: [9]?u4 = @splat(null);
    var s = g.score;
    var i: usize = digits.len;
    while (i > 0) {
        i -= 1;
        digits[i] = @intCast(s % 10);
        s /= 10;
        if (s == 0) break;
    }
    for (digits, 0..) |d, k| digit(pixels, px0 + 21 + k * 20, 51, d);

    // the ball, and the balls still to come
    var buf: [32]u8 = undefined;
    text(pixels, px0 + 12, 100, "BALL", 2, label);
    const ball_no = game.start_balls + 1 - @as(usize, g.balls_left);
    text(pixels, px0 + 66, 100, std.mem.print(&buf, "{d}", .{@min(ball_no, game.start_balls)}) catch "", 2, value);
    for (0..g.balls_left -| 1) |k| {
        const bx = px0 + pw - 24 - k * 18;
        icon(pixels, bx, 101, &.{ ".###.", "#####", "#####", "#####", ".###." }, 3, c(.steel, 12));
    }

    well(pixels, px0 + 10, 124, pw - 20, 40);
    text(pixels, px0 + 16, 129, "RANK", 1, label);
    text(pixels, px0 + 16, 141, game.ranks[g.rank], 2, value);
    for (0..g.rank) |k| {
        // a chevron per rank above private
        const cx = px0 + pw - 22;
        const cy = 158 - k * 4;
        icon(pixels, cx - 6, cy, &.{ "#.....#", ".#...#.", "..#.#..", "...#..." }, 1, c(.yellow, 12));
    }

    well(pixels, px0 + 10, 170, pw - 20, 64);
    text(pixels, px0 + 16, 175, "MISSION", 1, label);
    text(pixels, px0 + 16, 189, "HIT THE", 2, c(.toxic, 12));
    text(pixels, px0 + 16, 207, "GREEN TARGET", 2, c(.toxic, 12));

    // keys held, and demons slain
    well(pixels, px0 + 10, 240, pw - 20, 34);
    const key_colors = [3]pal.Ramp{ .blood, .blue, .yellow };
    for (key_colors, g.keys, 0..) |kr, held, k| icon(pixels, px0 + 18 + k * 34, 247, &key_icon, 3, c(kr, if (held) 14 else 3));
    icon(pixels, px0 + 128, 248, &skull_icon, 3, c(.bone, if (g.slain > 0) 13 else 5));
    text(pixels, px0 + 156, 251, std.mem.print(&buf, "{d}", .{g.slain}) catch "", 2, value);

    // the log, newest brightest
    well(pixels, px0 + 10, 280, pw - 20, 18 * game.log_lines + 12);
    for (g.log, 0..) |m, k| {
        const shade: u4 = if (k == 0) 14 else if (m.age < 3) 11 else 8;
        text(pixels, px0 + 16, 287 + k * 18, m.str(), 2, c(.bone, shade));
    }

    centered(pixels, 412, "Z / SHIFT  FLIPPERS", 1, label);
    centered(pixels, 424, "SPACE  LAUNCH", 1, label);
    centered(pixels, 436, "ENTER  NEW GAME   ESC  QUIT", 1, label);

    if (g.phase == .game_over) gameOver(pixels);
}

// a band across the table view
fn gameOver(pixels: []u32) void {
    const y0 = 200;
    for (y0..y0 + 64) |y| for (0..@as(usize, @intCast(layout.view.w))) |x| {
        const p = &pixels[y * stride + x];
        p.* = (p.* >> 2) & 0x3f3f3f;
    };
    const s = "GAME OVER";
    const x = (@as(usize, @intCast(layout.view.w)) - font.width(s, 4)) / 2;
    text(pixels, x + 3, y0 + 21, s, 4, c(.blood, 2));
    text(pixels, x, y0 + 18, s, 4, c(.blood, 14));
}

test "a log line of the longest length fits its well" {
    const longest: [game.max_message]u8 = @splat('W');
    try std.testing.expect(16 + font.width(&longest, 2) <= pw - 10);
}

test "the panel draws into its part of the frame only" {
    tex.init();
    const fb = try std.testing.allocator.alloc(u32, platform.width * platform.height);
    defer std.testing.allocator.free(fb);
    @memset(fb, 0x123456);
    var g = Game.init();
    g.score = 1234567;
    draw(&g, fb);
    try std.testing.expectEqual(@as(u32, 0x123456), fb[px0 - 1]);
    try std.testing.expect(fb[px0 + 5] != 0x123456);
}
