//! Procedural 64x64 textures of palette indices, made once by `init`. Each is
//! seamless, so they tile across walls and the playfield.
const std = @import("std");
const pal = @import("palette.zig");

pub const size = 64;
const mask = size - 1;

pub const Tex = enum {
    tech,
    hellstone,
    sludge,
    grate,
    marble,
    bloodmetal,
    lava,
    flagstone,
};

const count = @typeInfo(Tex).@"enum".field_names.len;

var data: [count][size * size]u8 = undefined;
var ready = false;

/// The texel at (u, v), wrapping. Panics if `init` was not called.
pub fn texel(t: Tex, u: i32, v: i32) u8 {
    std.debug.assert(ready);
    const x: usize = @intCast(u & mask);
    const y: usize = @intCast(v & mask);
    return data[@backingInt(t)][y * size + x];
}

pub fn init() void {
    if (ready) return;
    inline for (@typeInfo(Tex).@"enum".field_names, 0..) |name, i| {
        const t: Tex = @field(Tex, name);
        for (0..size) |y| {
            for (0..size) |x| data[i][y * size + x] = make(t, @intCast(x), @intCast(y));
        }
    }
    ready = true;
}

fn make(t: Tex, x: i32, y: i32) u8 {
    return switch (t) {
        .tech => tech(x, y),
        .hellstone => hellstone(x, y),
        .sludge => sludge(x, y),
        .grate => grate(x, y),
        .marble => marble(x, y),
        .bloodmetal => bloodmetal(x, y),
        .lava => lava(x, y),
        .flagstone => flagstone(x, y),
    };
}

fn hash(x: i32, y: i32, seed: u32) u32 {
    var h: u32 = @bitCast(x *% 374761393 +% y *% 668265263);
    h +%= seed *% 2246822519;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}

fn rand01(x: i32, y: i32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash(x, y, seed) & 0xffff)) / 65535;
}

/// Value noise in 0..1 with `n` cells across the tile, seamless.
fn noise(x: i32, y: i32, n: i32, seed: u32) f32 {
    const step = @divExact(size, n);
    const cx = @divFloor(x, step);
    const cy = @divFloor(y, step);
    const fx = @as(f32, @floatFromInt(@mod(x, step))) / @as(f32, @floatFromInt(step));
    const fy = @as(f32, @floatFromInt(@mod(y, step))) / @as(f32, @floatFromInt(step));
    const sx = fx * fx * (3 - 2 * fx);
    const sy = fy * fy * (3 - 2 * fy);
    const x0 = @mod(cx, n);
    const y0 = @mod(cy, n);
    const x1 = @mod(cx + 1, n);
    const y1 = @mod(cy + 1, n);
    const a = rand01(x0, y0, seed);
    const b = rand01(x1, y0, seed);
    const c = rand01(x0, y1, seed);
    const d = rand01(x1, y1, seed);
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
}

fn fbm(x: i32, y: i32, seed: u32) f32 {
    return noise(x, y, 4, seed) * 0.5 + noise(x, y, 8, seed + 1) * 0.3 + noise(x, y, 16, seed + 2) * 0.2;
}

fn shade(ramp: pal.Ramp, v: f32) u8 {
    return pal.index(ramp, @intFromFloat(std.math.clamp(@round(v), 0, 15)));
}

/// Distance to the nearest of a seamless set of points, and to the second
/// nearest: their difference is small on the cell edges (cracks).
fn cellDistances(x: i32, y: i32, n: i32, seed: u32) [2]f32 {
    const step = @divExact(size, n);
    const cx = @divFloor(x, step);
    const cy = @divFloor(y, step);
    var d1: f32 = 1e9;
    var d2: f32 = 1e9;
    var j: i32 = -1;
    while (j <= 1) : (j += 1) {
        var i: i32 = -1;
        while (i <= 1) : (i += 1) {
            const gx = cx + i;
            const gy = cy + j;
            const px = @as(f32, @floatFromInt(gx * step)) + rand01(@mod(gx, n), @mod(gy, n), seed) * @as(f32, @floatFromInt(step));
            const py = @as(f32, @floatFromInt(gy * step)) + rand01(@mod(gx, n), @mod(gy, n), seed + 7) * @as(f32, @floatFromInt(step));
            const dx = px - @as(f32, @floatFromInt(x));
            const dy = py - @as(f32, @floatFromInt(y));
            const d = @sqrt(dx * dx + dy * dy);
            if (d < d1) {
                d2 = d1;
                d1 = d;
            } else if (d < d2) d2 = d;
        }
    }
    return .{ d1, d2 };
}

// riveted steel panels, 32 texels square, with grime
fn tech(x: i32, y: i32) u8 {
    const px = @mod(x, 32);
    const py = @mod(y, 32);
    if (px == 0 or py == 0) return pal.index(.steel, 1);
    const grime = fbm(x, y, 11);
    if (grime > 0.72) return shade(.brown, 3 + (grime - 0.72) * 10);
    const rivet = for ([_][2]i32{ .{ 4, 4 }, .{ 27, 4 }, .{ 4, 27 }, .{ 27, 27 } }) |r| {
        const dx = px - r[0];
        const dy = py - r[1];
        if (dx * dx + dy * dy <= 2) break true;
    } else false;
    if (rivet) return pal.index(.steel, if (px < 16 and py < 16) 13 else 11);
    var v: f32 = 7 + (noise(x, y, 16, 3) - 0.5) * 2;
    if (px == 1 or py == 1) v = 11;
    if (px == 31 or py == 31) v = 3;
    return shade(.steel, v);
}

// brown stone, cracked, with a red glow deep in the widest cracks
fn hellstone(x: i32, y: i32) u8 {
    const c = cellDistances(x, y, 4, 21);
    const edge = c[1] - c[0];
    if (edge < 1.2) return if (noise(x, y, 8, 22) > 0.6) pal.index(.blood, 6) else pal.index(.brown, 1);
    const v = 4 + fbm(x, y, 23) * 6 - (if (edge < 2.5) @as(f32, 2) else 0);
    return shade(.brown, v);
}

// dark green ooze with brighter swirls and a few bubbles
fn sludge(x: i32, y: i32) u8 {
    const n = fbm(x, y, 31);
    const swirl = @abs(fbm(x, y, 33) - 0.5);
    if (rand01(x, y, 32) > 0.99) return pal.index(.toxic, 14);
    if (swirl < 0.04) return shade(.toxic, 10 + n * 3);
    return shade(.toxic, 2 + n * n * 9);
}

// rusted bars every 8 texels, dark holes between
fn grate(x: i32, y: i32) u8 {
    const bx = @mod(x, 8);
    const by = @mod(y, 8);
    const rust = fbm(x, y, 41);
    if (bx < 2 or by < 2) {
        const hl: f32 = if (bx == 0 or by == 0) 3 else 0;
        return shade(.rust, 6 + rust * 4 + hl);
    }
    return pal.index(.gray, if (bx == 2 or by == 2) 1 else 0);
}

// green marble with pale veins along two contours of the noise
fn marble(x: i32, y: i32) u8 {
    const n = fbm(x, y, 51);
    const m = fbm(x, y, 52);
    if (@abs(n - 0.45) < 0.012 or @abs(m - 0.55) < 0.01) return shade(.bone, 8 + m * 4);
    return shade(.moss, 2 + n * 6 + m * 2);
}

// gray plates with blood running down them in thin drips
fn bloodmetal(x: i32, y: i32) u8 {
    const streak = rand01(x, 0, 61);
    const run = noise(x, y, 8, 62);
    if (streak > 0.86 and run > 0.4) return shade(.blood, 3 + (run - 0.4) * 14);
    var v: f32 = 6 + (noise(x, y, 16, 63) - 0.5) * 2;
    if (@mod(y, 16) == 0) v = 2;
    return shade(.gray, v);
}

// dark crust plates over glowing cracks
fn lava(x: i32, y: i32) u8 {
    const n = fbm(x, y, 71);
    const c = cellDistances(x, y, 4, 72);
    const edge = c[1] - c[0] + (n - 0.5) * 2;
    if (edge < 1.0) return shade(.bright, 9 + n * 5);
    if (edge < 2.5) return shade(.fire, 9 + n * 3);
    return shade(.blood, 2 + n * 4);
}

// dark flagstones, 16x16, with worn mortar
fn flagstone(x: i32, y: i32) u8 {
    const row = @divFloor(y, 16);
    const off: i32 = if (@mod(row, 2) == 0) 0 else 8;
    const sx = @mod(x + off, 16);
    const sy = @mod(y, 16);
    if (sx == 0 or sy == 0) return pal.index(.gray, 1);
    const stone = rand01(@divFloor(x + off, 16), row, 81);
    var v = 3 + stone * 3 + (fbm(x, y, 82) - 0.5) * 3;
    if (sx == 1 or sy == 1) v += 2;
    return shade(.gray, v);
}

test "textures are made the same every time and tile" {
    init();
    const first = texel(.hellstone, 5, 9);
    ready = false;
    init();
    try std.testing.expectEqual(first, texel(.hellstone, 5, 9));
    try std.testing.expectEqual(texel(.tech, 3, 4), texel(.tech, 3 + size, 4 - size));
}

test "the tech panel is mostly steel, with steel seams" {
    init();
    try std.testing.expectEqual(pal.index(.steel, 1), texel(.tech, 0, 10));
    var steel: usize = 0;
    for (0..size) |y| for (0..size) |x| {
        if (pal.rampOf(texel(.tech, @intCast(x), @intCast(y))) == .steel) steel += 1;
    };
    try std.testing.expect(steel > size * size * 3 / 4);
}
