//! The 256-color palette: 16 ramps of 16 shades, darkest first, and 32
//! light-level colormaps that darken each color within its own ramp. Our
//! own colors, in the spirit of 8-bit software renderers.
const std = @import("std");

pub const Ramp = enum(u4) {
    gray,
    brown,
    blue,
    blood,
    fire,
    yellow,
    toxic,
    moss,
    steel,
    violet,
    bone,
    rust,
    flesh,
    teal,
    crimson,
    /// emissive: the colormaps leave it as it is
    bright,
};

pub const light_levels = 32;
pub const full_light = light_levels - 1;

/// A palette index of `ramp`, `shade` 0 (darkest) to 15 (brightest).
pub fn index(ramp: Ramp, shade: u4) u8 {
    return (@as(u8, @backingInt(ramp)) << 4) | shade;
}

pub fn rampOf(i: u8) Ramp {
    return @fromBackingInt(@intCast(i >> 4));
}

pub fn shadeOf(i: u8) u4 {
    return @intCast(i & 15);
}

// dark, middle and bright stops of each ramp, 0xRRGGBB
const stops = [16][3]u32{
    .{ 0x060606, 0x5c5c5c, 0xe4e4e4 },
    .{ 0x0a0703, 0x5a3c20, 0xc8a070 },
    .{ 0x00030e, 0x1a3aa8, 0x96b8ff },
    .{ 0x0a0000, 0x7a0808, 0xff4a36 },
    .{ 0x120400, 0xb04408, 0xffbc48 },
    .{ 0x120e00, 0xa08810, 0xfff284 },
    .{ 0x000e00, 0x24a012, 0xb4ff64 },
    .{ 0x070904, 0x4a5028, 0xb0b880 },
    .{ 0x04060c, 0x405068, 0xb8c8e0 },
    .{ 0x08040c, 0x502878, 0xd0a0ff },
    .{ 0x0c0a08, 0x8a7e68, 0xf8f0dc },
    .{ 0x0c0402, 0x7a3818, 0xe89060 },
    .{ 0x100604, 0x9a5a44, 0xffc0a0 },
    .{ 0x000a0a, 0x107070, 0x80f0e0 },
    .{ 0x060000, 0x500012, 0xc82444 },
    .{ 0x4a1800, 0xff9010, 0xffffe8 },
};

fn mix(a: u32, b: u32, t: f32) u32 {
    var out: u32 = 0;
    inline for (.{ 16, 8, 0 }) |sh| {
        const ca: f32 = @floatFromInt((a >> sh) & 0xff);
        const cb: f32 = @floatFromInt((b >> sh) & 0xff);
        out |= @as(u32, @intFromFloat(@round(ca + (cb - ca) * t))) << sh;
    }
    return out;
}

/// 0x00RRGGBB of each index.
pub const rgb: [256]u32 = blk: {
    @setEvalBranchQuota(20000);
    var p: [256]u32 = undefined;
    for (0..16) |r| {
        for (0..16) |s| {
            const t = @as(f32, @floatFromInt(s)) / 15;
            p[r * 16 + s] = if (t < 0.5) mix(stops[r][0], stops[r][1], t * 2) else mix(stops[r][1], stops[r][2], (t - 0.5) * 2);
        }
    }
    break :blk p;
};

/// `colormap[light][i]`: index `i` seen at `light` (0 dark, 31 full).
pub const colormap: [light_levels][256]u8 = blk: {
    @setEvalBranchQuota(100000);
    var m: [light_levels][256]u8 = undefined;
    for (0..light_levels) |l| {
        const k = @as(f32, @floatFromInt(l)) / full_light;
        for (0..256) |i| {
            if (i >> 4 == 15) {
                m[l][i] = i;
                continue;
            }
            const s: f32 = @floatFromInt(i & 15);
            m[l][i] = @intCast((i & 0xf0) | @as(usize, @intFromFloat(@round(s * k))));
        }
    }
    break :blk m;
};

/// The color of index `i` at `light`, clamped to the levels.
pub fn lit(i: u8, light: i32) u32 {
    const l: usize = @intCast(std.math.clamp(light, 0, full_light));
    return rgb[colormap[l][i]];
}

test "full light is the identity and no light darkens to each ramp's darkest" {
    for (0..256) |i| {
        const c: u8 = @intCast(i);
        try std.testing.expectEqual(c, colormap[full_light][i]);
        try std.testing.expectEqual(rampOf(c), rampOf(colormap[0][i]));
        if (rampOf(c) != .bright) try std.testing.expectEqual(@as(u4, 0), shadeOf(colormap[0][i]));
    }
}

test "every ramp gets brighter with its shade" {
    for (0..16) |r| {
        var prev: u32 = 0;
        for (0..16) |s| {
            const c = rgb[r * 16 + s];
            const sum = (c >> 16) + ((c >> 8) & 0xff) + (c & 0xff);
            try std.testing.expect(sum >= prev);
            prev = sum;
        }
    }
}

test "index, ramp and shade round-trip" {
    const i = index(.toxic, 9);
    try std.testing.expectEqual(Ramp.toxic, rampOf(i));
    try std.testing.expectEqual(@as(u4, 9), shadeOf(i));
    try std.testing.expectEqual(rgb[i], lit(i, 99));
}
