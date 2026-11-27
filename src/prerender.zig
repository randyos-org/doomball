//! The table rendered once, at startup: each pixel of the view ray cast
//! against the solids and the playfield, kept as a color, a depth, its
//! palette index and light, and what it shows. Each object's second look
//! is kept as a patch of the pixels it changes.
const std = @import("std");
const vec = @import("vec.zig");
const layout = @import("layout.zig");
const camera = @import("camera.zig");
const raycast = @import("raycast.zig");
const scene = @import("scene.zig");
const pal = @import("palette.zig");
const tex = @import("textures.zig");

const Allocator = std.mem.Allocator;
const V3 = vec.V3;
const v2 = vec.v2;

pub const w: usize = layout.view.w;
pub const h: usize = layout.view.h;

/// `obj` of a pixel showing the playfield, and of one showing the cabinet.
pub const on_floor: u8 = 255;
pub const off_table: u8 = 254;

pub const Sample = struct { color: u32, depth: f32, index: u8, light: u8, obj: u8 };

const Box = struct {
    x0: usize,
    y0: usize,
    x1: usize,
    y1: usize,

    fn contains(b: Box, x: usize, y: usize) bool {
        return x >= b.x0 and x < b.x1 and y >= b.y0 and y < b.y1;
    }

    fn join(a: Box, b: Box) Box {
        if (a.x1 == 0) return b;
        return .{ .x0 = @min(a.x0, b.x0), .y0 = @min(a.y0, b.y0), .x1 = @max(a.x1, b.x1), .y1 = @max(a.y1, b.y1) };
    }
};

const empty_box: Box = .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 };

/// The view pixels a box on the table covers, from height z0 to z1.
pub fn screenBox(cam: camera.Camera, lo: vec.V2, hi: vec.V2, z0: f32, z1: f32) Box {
    var x0: f32 = 1e9;
    var y0: f32 = 1e9;
    var x1: f32 = -1e9;
    var y1: f32 = -1e9;
    for ([_]f32{ lo.x, hi.x }) |x| for ([_]f32{ lo.y, hi.y }) |y| for ([_]f32{ z0, z1 }) |z| {
        const p = cam.project(vec.v3(x, y, z));
        x0 = @min(x0, p.x);
        y0 = @min(y0, p.y);
        x1 = @max(x1, p.x);
        y1 = @max(y1, p.y);
    };
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);
    return .{
        .x0 = @intFromFloat(std.math.clamp(@floor(x0) - 1, 0, fw)),
        .y0 = @intFromFloat(std.math.clamp(@floor(y0) - 1, 0, fh)),
        .x1 = @intFromFloat(std.math.clamp(@ceil(x1) + 1, 0, fw)),
        .y1 = @intFromFloat(std.math.clamp(@ceil(y1) + 1, 0, fh)),
    };
}

pub const Patch = struct {
    /// view pixel indices, and what they show in the object's second look
    at: []u32 = &.{},
    color: []u32 = &.{},
    depth: []f32 = &.{},
};

pub const Background = struct {
    cam: camera.Camera,
    boxes: [scene.solids.len]Box,
    color: []u32,
    depth: []f32,
    index: []u8,
    light: []u8,
    obj: []u8,
    patches: [scene.obj.count]Patch,

    pub fn init(gpa: Allocator) !Background {
        tex.init();
        const cam = camera.Camera.init();
        var bg: Background = .{ .cam = cam, .boxes = undefined, .color = &.{}, .depth = &.{}, .index = &.{}, .light = &.{}, .obj = &.{}, .patches = @splat(.{}) };
        errdefer bg.deinit(gpa);
        for (scene.solids, &bg.boxes) |s, *b| {
            const bb = s.box();
            b.* = screenBox(cam, bb[0], bb[1], s.h0, s.h1);
        }
        bg.color = try gpa.alloc(u32, w * h);
        bg.depth = try gpa.alloc(f32, w * h);
        bg.index = try gpa.alloc(u8, w * h);
        bg.light = try gpa.alloc(u8, w * h);
        bg.obj = try gpa.alloc(u8, w * h);
        const base: scene.States = @splat(0);
        for (0..h) |y| for (0..w) |x| {
            const s = bg.trace(&base, x, y);
            const i = y * w + x;
            bg.color[i] = s.color;
            bg.depth[i] = s.depth;
            bg.index[i] = s.index;
            bg.light[i] = s.light;
            bg.obj[i] = s.obj;
        };
        for (1..scene.obj.count) |o| bg.patches[o] = try bg.makePatch(gpa, @intCast(o));
        return bg;
    }

    pub fn deinit(bg: *Background, gpa: Allocator) void {
        for (&bg.patches) |*p| {
            gpa.free(p.at);
            gpa.free(p.color);
            gpa.free(p.depth);
            p.* = .{};
        }
        gpa.free(bg.color);
        gpa.free(bg.depth);
        gpa.free(bg.index);
        gpa.free(bg.light);
        gpa.free(bg.obj);
    }

    fn makePatch(bg: *const Background, gpa: Allocator, o: u8) !Patch {
        var states: scene.States = @splat(0);
        states[o] = 1;
        var box = empty_box;
        for (scene.solids, bg.boxes) |s, b| {
            if (s.obj == o) box = box.join(b);
        }
        var at: std.ArrayList(u32) = .empty;
        defer at.deinit(gpa);
        var color: std.ArrayList(u32) = .empty;
        defer color.deinit(gpa);
        var depth: std.ArrayList(f32) = .empty;
        defer depth.deinit(gpa);
        for (box.y0..box.y1) |y| for (box.x0..box.x1) |x| {
            const i = y * w + x;
            const s = bg.trace(&states, x, y);
            if (s.obj != o and bg.obj[i] != o) continue;
            try at.append(gpa, @intCast(i));
            try color.append(gpa, s.color);
            try depth.append(gpa, s.depth);
        };
        return .{ .at = try at.toOwnedSlice(gpa), .color = try color.toOwnedSlice(gpa), .depth = try depth.toOwnedSlice(gpa) };
    }

    /// What view pixel (x, y) shows with the objects in `states`.
    pub fn trace(bg: *const Background, states: *const scene.States, x: usize, y: usize) Sample {
        const d = bg.cam.ray(@as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5);
        const o = camera.eye;
        var best: ?raycast.Hit = null;
        var which: usize = 0;
        for (scene.solids, bg.boxes, 0..) |s, b, i| {
            if (!b.contains(x, y) or !s.visible(states)) continue;
            const hit = switch (s.shape) {
                .capsule => |c| raycast.capsule(o, d, c.a, c.b, c.r, s.h0, s.h1),
                .cylinder => |c| raycast.cylinder(o, d, c.c, c.r, s.h0, s.h1),
                .triangle => |t| raycast.prism(o, d, &t, s.h0, s.h1),
            } orelse continue;
            if (best == null or hit.t < best.?.t) {
                best = hit;
                which = i;
            }
        }
        const t_floor = raycast.floor(o, d);
        if (best) |hit| {
            if (t_floor == null or hit.t < t_floor.?) {
                const s = scene.solids[which];
                const p = o.add(d.mul(hit.t));
                const m = if (hit.top) s.top else s.side;
                const tx = scene.texel(m, p, !hit.top, s);
                const l: i32 = if (tx.glow) pal.full_light else scene.light(p, hit.n, hit.t, true);
                return sample(tx.i, l, hit.t, s.obj);
            }
        }
        const t = t_floor orelse return .{ .color = 0, .depth = 1e9, .index = 0, .light = 0, .obj = off_table };
        const p = o.add(d.mul(t));
        const f = scene.floor(v2(p.x, p.y));
        const l: i32 = if (f.glow) pal.full_light else scene.light(p, vec.v3(0, 0, 1), t, f.table);
        return sample(f.i, l, t, if (f.table) on_floor else off_table);
    }
};

fn sample(i: u8, light: i32, depth: f32, o: u8) Sample {
    const l: u8 = @intCast(std.math.clamp(light, 0, pal.full_light));
    return .{ .color = pal.lit(i, l), .depth = depth, .index = i, .light = l, .obj = o };
}

test "the background shows the table, its bumpers and their lit patches" {
    var bg = try Background.init(std.testing.allocator);
    defer bg.deinit(std.testing.allocator);
    // a bumper's cap, seen from the camera
    const b = @import("table.zig").bumpers[0];
    const p = bg.cam.project(vec.v3(b.c.x, b.c.y, b.h));
    const x: usize = @intFromFloat(p.x);
    const y: usize = @intFromFloat(p.y);
    try std.testing.expectEqual(@as(u8, scene.obj.bumper), bg.obj[y * w + x]);
    const patch = bg.patches[scene.obj.bumper];
    try std.testing.expect(patch.at.len > 50);
    var found = false;
    for (patch.at, patch.color) |at, c| {
        if (at == y * w + x) {
            found = true;
            try std.testing.expect(c != bg.color[at]);
        }
    }
    try std.testing.expect(found);
    // the middle of the pit is lava, shining at full light
    const pit = bg.cam.project(vec.v3(184, 400, 0));
    const pi = @as(usize, @intFromFloat(pit.y)) * w + @as(usize, @intFromFloat(pit.x));
    try std.testing.expectEqual(on_floor, bg.obj[pi]);
    try std.testing.expectEqual(@as(u8, pal.full_light), bg.light[pi]);
}
