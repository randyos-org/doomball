//! The table as the renderer sees it: solids with materials, the painted
//! playfield, and the light. Parts with two looks (lit or not, a gate open
//! or closed) belong to an object whose state picks the look.
const std = @import("std");
const vec = @import("vec.zig");
const table = @import("table.zig");
const pal = @import("palette.zig");
const tex = @import("textures.zig");
const font = @import("font.zig");

const V2 = vec.V2;
const V3 = vec.V3;
const v2 = vec.v2;
const v3 = vec.v3;
const Tex = tex.Tex;

pub const Mat = union(enum) {
    /// a texture, lit
    tex: Tex,
    /// one palette index, lit
    solid: u8,
    /// one palette index, shining by itself
    glow: u8,
    /// a texture shining by itself
    glow_tex: Tex,
};

pub const Shape = union(enum) {
    capsule: struct { a: V2, b: V2, r: f32 },
    cylinder: struct { c: V2, r: f32 },
    triangle: [3]V2,
};

/// Objects with a second look, state 1 (0 is the first). 0 is no object.
pub const obj = struct {
    pub const bumper = 1;
    pub const lane = bumper + table.bumpers.len;
    pub const target = lane + table.rollovers.len;
    pub const gate = target + table.targets.len;
    pub const lock = gate + 1;
    pub const sling = lock + 1;
    pub const count = sling + 2;
};

pub const States = [obj.count]u1;

pub const Solid = struct {
    shape: Shape,
    h0: f32 = 0,
    h1: f32,
    side: Mat,
    top: Mat,
    /// the object it belongs to, and the state it shows in
    obj: u8 = 0,
    state: u1 = 0,

    pub fn visible(s: Solid, states: *const States) bool {
        return s.obj == 0 or states[s.obj] == s.state;
    }

    /// Bounds on the playfield, for culling.
    pub fn box(s: Solid) [2]V2 {
        return switch (s.shape) {
            .capsule => |c| .{ v2(@min(c.a.x, c.b.x) - c.r, @min(c.a.y, c.b.y) - c.r), v2(@max(c.a.x, c.b.x) + c.r, @max(c.a.y, c.b.y) + c.r) },
            .cylinder => |c| .{ v2(c.c.x - c.r, c.c.y - c.r), v2(c.c.x + c.r, c.c.y + c.r) },
            .triangle => |t| .{ v2(@min(t[0].x, @min(t[1].x, t[2].x)), @min(t[0].y, @min(t[1].y, t[2].y))), v2(@max(t[0].x, @max(t[1].x, t[2].x)), @max(t[0].y, @max(t[1].y, t[2].y))) },
        };
    }
};

fn idx(r: pal.Ramp, s: u4) u8 {
    return pal.index(r, s);
}

fn keyRamp(k: table.TargetKind) pal.Ramp {
    return switch (k) {
        .key_red => .blood,
        .key_blue => .blue,
        .key_yellow => .yellow,
        .mission => .toxic,
    };
}

const rubber: Mat = .{ .solid = idx(.gray, 4) };

pub const solids = blk: {
    @setEvalBranchQuota(20000);
    var s: [table.walls.len + 40]Solid = undefined;
    var n: usize = 0;
    for (table.walls) |w| {
        const sling_id: u8 = if (w.a.x < table.axis_x) 0 else 1;
        switch (w.kind) {
            .sling => {
                for ([2]u1{ 0, 1 }) |st| {
                    s[n] = .{ .shape = .{ .capsule = .{ .a = w.a, .b = w.b, .r = w.r } }, .h1 = w.h, .side = if (st == 0) .{ .solid = idx(.crimson, 9) } else .{ .glow = idx(.bright, 13) }, .top = rubber, .obj = obj.sling + sling_id, .state = st };
                    n += 1;
                }
            },
            .rubber => {
                s[n] = .{ .shape = .{ .capsule = .{ .a = w.a, .b = w.b, .r = w.r } }, .h1 = w.h, .side = rubber, .top = rubber };
                n += 1;
            },
            .wall, .oneway => {
                s[n] = .{ .shape = .{ .capsule = .{ .a = w.a, .b = w.b, .r = w.r } }, .h1 = w.h, .side = .{ .tex = w.side }, .top = .{ .tex = w.top } };
                n += 1;
            },
        }
    }
    // slingshot bodies, under their rubber edges
    for (table.slings) |tri| {
        s[n] = .{ .shape = .{ .triangle = tri }, .h1 = 20, .side = .{ .tex = .hellstone }, .top = .{ .tex = .tech } };
        n += 1;
    }
    for (table.bumpers, 0..) |b, i| {
        s[n] = .{ .shape = .{ .cylinder = .{ .c = b.c, .r = b.r } }, .h1 = 14, .side = .{ .tex = .tech }, .top = .{ .solid = idx(.steel, 5) } };
        n += 1;
        for ([2]u1{ 0, 1 }) |st| {
            s[n] = .{
                .shape = .{ .cylinder = .{ .c = b.c, .r = b.r * 0.72 } },
                .h1 = b.h,
                .side = if (st == 0) .{ .solid = idx(.crimson, 10) } else .{ .glow = idx(.fire, 14) },
                .top = if (st == 0) .{ .solid = idx(.crimson, 12) } else .{ .glow = idx(.bright, 15) },
                .obj = obj.bumper + i,
                .state = st,
            };
            n += 1;
        }
    }
    for (table.rollovers, 0..) |ro, i| {
        for ([2]u1{ 0, 1 }) |st| {
            s[n] = .{ .shape = .{ .cylinder = .{ .c = ro.c, .r = 7 } }, .h1 = 0.6, .side = .{ .solid = idx(.yellow, 3) }, .top = if (st == 0) .{ .solid = idx(.yellow, 5) } else .{ .glow = idx(.yellow, 15) }, .obj = obj.lane + i, .state = st };
            n += 1;
        }
    }
    for (table.targets, 0..) |t, i| {
        const r = keyRamp(t.kind);
        for ([2]u1{ 0, 1 }) |st| {
            s[n] = .{ .shape = .{ .capsule = .{ .a = t.a, .b = t.b, .r = t.r } }, .h1 = t.h, .side = if (st == 0) .{ .solid = idx(r, 8) } else .{ .glow = idx(r, 15) }, .top = .{ .solid = idx(r, 10) }, .obj = obj.target + i, .state = st };
            n += 1;
        }
    }
    const g = table.gate;
    s[n] = .{ .shape = .{ .capsule = .{ .a = g.a, .b = g.b, .r = g.r } }, .h1 = g.h, .side = .{ .tex = .grate }, .top = .{ .solid = idx(.rust, 6) }, .obj = obj.gate, .state = 0 };
    s[n + 1] = .{ .shape = .{ .capsule = .{ .a = g.a, .b = g.b, .r = g.r } }, .h1 = 1, .side = .{ .solid = idx(.gray, 1) }, .top = .{ .solid = idx(.gray, 1) }, .obj = obj.gate, .state = 1 };
    n += 2;
    s[n] = .{ .shape = .{ .cylinder = .{ .c = table.lock_c, .r = table.lock_r + 4 } }, .h1 = 1, .side = .{ .solid = idx(.gray, 3) }, .top = .{ .solid = idx(.violet, 4) }, .obj = obj.lock, .state = 0 };
    s[n + 1] = .{ .shape = .{ .cylinder = .{ .c = table.lock_c, .r = table.lock_r + 4 } }, .h1 = 1, .side = .{ .solid = idx(.gray, 3) }, .top = .{ .glow = idx(.violet, 14) }, .obj = obj.lock, .state = 1 };
    s[n + 2] = .{ .shape = .{ .cylinder = .{ .c = table.lock_c, .r = table.lock_r } }, .h1 = 1.2, .side = .{ .solid = idx(.gray, 0) }, .top = .{ .solid = idx(.gray, 0) } };
    n += 3;
    break :blk s[0..n].*;
};

/// The material at a point of the solid: texture coordinates follow the
/// side around, and the top across the table.
pub fn texel(m: Mat, p: V3, side: bool, s: Solid) struct { i: u8, glow: bool } {
    const tx = switch (m) {
        .solid => |i| return .{ .i = i, .glow = false },
        .glow => |i| return .{ .i = i, .glow = true },
        .tex, .glow_tex => |t| t,
    };
    var u: f32 = p.x;
    var v: f32 = p.y;
    if (side) {
        v = s.h1 - p.z;
        u = switch (s.shape) {
            .capsule => |c| p.x - c.a.x + p.y - c.a.y,
            .cylinder => |c| std.math.atan2(p.y - c.c.y, p.x - c.c.x) * c.r,
            .triangle => p.x + p.y,
        };
    }
    return .{ .i = tex.texel(tx, @intFromFloat(@floor(u)), @intFromFloat(@floor(v))), .glow = m == .glow_tex };
}

pub const Floor = struct { i: u8, glow: bool = false, table: bool = true };

fn inTable(p: V2) bool {
    if (p.x < 8 or p.x > 396 or p.y > 834) return false;
    if (p.y > 196) return true;
    const dx = p.x - 202;
    const dy = p.y - 196;
    return dx * dx + dy * dy < 194 * 194;
}

fn ring(p: V2, c: V2, r0: f32, r1: f32) bool {
    const d = p.sub(c).len();
    return d >= r0 and d <= r1;
}

/// Painted letters on the playfield, `cell` units a font pixel.
fn lettering(p: V2, text: []const u8, x0: f32, y0: f32, cell: f32) bool {
    if (p.y < y0 or p.y >= y0 + font.glyph_h * cell or p.x < x0) return false;
    const col: usize = @intFromFloat((p.x - x0) / cell);
    const row: usize = @intFromFloat((p.y - y0) / cell);
    const ch = col / font.advance;
    if (ch >= text.len) return false;
    return font.bit(text[ch], col % font.advance, row);
}

const title = "DOOMBALL";
const title_cell: f32 = 5;
const title_x = table.axis_x - (title.len * font.advance - 1) * title_cell / 2;

/// The playfield's art at a point.
pub fn floor(p: V2) Floor {
    const x: i32 = @intFromFloat(@floor(p.x));
    const y: i32 = @intFromFloat(@floor(p.y));
    if (!inTable(p)) return .{ .i = tex.texel(.flagstone, x, y), .table = false };
    if (p.x > 352) return .{ .i = tex.texel(.grate, x, y) };
    const pit = table.pit;
    if (p.x > pit.x0 and p.x < pit.x1 and p.y > pit.y0 and p.y < pit.y1) {
        const rim = p.x < pit.x0 + 8 or p.x > pit.x1 - 8 or p.y < pit.y0 + 8 or p.y > pit.y1 - 8;
        return if (rim) .{ .i = tex.texel(.grate, x, y) } else .{ .i = tex.texel(.lava, x, y), .glow = true };
    }
    // a sigil ring around the bumpers, and spokes
    if (ring(p, v2(table.axis_x, 236), 80, 84)) return .{ .i = idx(.crimson, 11), .glow = true };
    if (lettering(p, title, title_x, 478, title_cell)) return .{ .i = idx(.blood, 10) };
    // hazard stripes on the apron
    if (p.y > 760 and p.y < 790 and p.x < 352) {
        return .{ .i = if (@mod(x + y, 24) < 12) idx(.yellow, 9) else idx(.gray, 1) };
    }
    // chevrons under the top lanes
    for (table.rollovers) |ro| {
        const dy = p.y - 124;
        const dx = @abs(p.x - ro.c.x);
        if (dy > 0 and dy < 16 and @abs(dy - dx * 0.8) < 2.5 and dx < 10) return .{ .i = idx(.yellow, 8) };
    }
    if (p.y < 300) return .{ .i = tex.texel(.tech, x, y) };
    if (p.y > 640) return .{ .i = tex.texel(.hellstone, x, y) };
    return .{ .i = tex.texel(.marble, x, y) };
}

const key_light = v3(-0.45, 0.55, 1).norm();
const pit_glow = v3((table.pit.x0 + table.pit.x1) / 2, (table.pit.y0 + table.pit.y1) / 2, 10);

/// The light level at a point with normal `n`, seen from `depth`: a key
/// light, the glow of the pit, and falloff with distance.
pub fn light(p: V3, n: V3, depth: f32, in_table: bool) i32 {
    var l: f32 = 11 + 11 * @max(0, n.dot(key_light));
    const d = p.sub(pit_glow).len();
    l += 9 * @max(0, 1 - d / 150);
    l -= @max(0, depth - 2300) / 120;
    if (!in_table) l -= 13;
    return @intFromFloat(@round(l));
}

test "the solids include every part with two looks, in both looks" {
    var seen: [obj.count][2]bool = @splat(.{ false, false });
    for (solids) |s| seen[s.obj][s.state] = true;
    for (1..obj.count) |o| try std.testing.expect(seen[o][0] and seen[o][1]);
}

test "the playfield has the pit's lava, the plunger lane's grate and the cabinet outside" {
    tex.init();
    try std.testing.expect(floor(v2(184, 400)).glow);
    try std.testing.expect(floor(v2(370, 600)).table);
    try std.testing.expect(!floor(v2(2, 600)).table);
    try std.testing.expect(!floor(v2(20, 20)).table);
}

test "light falls off with distance" {
    const up = v3(0, 0, 1);
    try std.testing.expect(light(v3(20, 700, 0), up, 2400, true) > light(v3(20, 700, 0), up, 3200, true));
}
