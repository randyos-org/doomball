//! Each frame: the prerendered table and the patches of what is lit, then
//! the moving parts over it, depth-tested: ball shadows, the flippers, the
//! plunger and the balls; then the panel.
const std = @import("std");
const vec = @import("vec.zig");
const platform = @import("platform.zig");
const layout = @import("layout.zig");
const camera = @import("camera.zig");
const raycast = @import("raycast.zig");
const scene = @import("scene.zig");
const pal = @import("palette.zig");
const prerender = @import("prerender.zig");
const table = @import("table.zig");
const panel = @import("panel.zig");
const sprites = @import("sprites.zig");
const demons = @import("demons.zig");
const Game = @import("game.zig").Game;

const Allocator = std.mem.Allocator;
const V2 = vec.V2;
const V3 = vec.V3;
const v2 = vec.v2;
const v3 = vec.v3;
const w = prerender.w;
const h = prerender.h;

/// The state of each two-look object, from the game.
pub fn states(g: *const Game) scene.States {
    var s: scene.States = @splat(0);
    for (g.bumper_flash, 0..) |f, i| s[scene.obj.bumper + i] = @intFromBool(f > 0);
    for (g.lanes_lit, 0..) |l, i| s[scene.obj.lane + i] = @intFromBool(l);
    for (0..table.targets.len) |i| s[scene.obj.target + i] = @intFromBool(g.targetLit(i));
    s[scene.obj.gate] = @intFromBool(!g.world.gate_closed);
    s[scene.obj.lock] = @intFromBool(!g.world.gate_closed);
    for (g.sling_flash, 0..) |f, i| s[scene.obj.sling + i] = @intFromBool(f > 0);
    return s;
}

pub const Renderer = struct {
    bg: prerender.Background,
    depth: []f32,

    pub fn init(gpa: Allocator) !Renderer {
        var bg = try prerender.Background.init(gpa);
        errdefer bg.deinit(gpa);
        return .{ .bg = bg, .depth = try gpa.alloc(f32, w * h) };
    }

    pub fn deinit(r: *Renderer, gpa: Allocator) void {
        r.bg.deinit(gpa);
        gpa.free(r.depth);
    }

    fn put(pixels: []u32, i: usize, c: u32) void {
        pixels[(i / w + @as(usize, @intCast(layout.view.y))) * platform.width + i % w + @as(usize, @intCast(layout.view.x))] = c;
    }

    pub fn draw(r: *Renderer, g: *const Game, pixels: []u32) void {
        const bg = &r.bg;
        for (0..h) |y| {
            const row = (y + @as(usize, @intCast(layout.view.y))) * platform.width + @as(usize, @intCast(layout.view.x));
            @memcpy(pixels[row..][0..w], bg.color[y * w ..][0..w]);
        }
        @memcpy(r.depth, bg.depth);
        const st = states(g);
        for (1..scene.obj.count) |o| {
            if (st[o] == 0) continue;
            const p = bg.patches[o];
            for (p.at, p.color, p.depth) |at, c, d| {
                put(pixels, at, c);
                r.depth[at] = d;
            }
        }
        for (g.world.balls) |b| if (b.active and !b.locked) r.shadow(pixels, b.p);
        for (g.world.flippers) |f| r.flipper(pixels, f.spec.pivot, f.tip());
        r.plunger(pixels, g.plunger);
        for (g.demons.list) |d| if (d.state != .away) r.demon(pixels, d);
        for (g.world.balls) |b| if (b.active) r.ball(pixels, b);
        panel.draw(g, pixels);
    }

    // away from the key light, on the playfield only
    fn shadow(r: *Renderer, pixels: []u32, p: V2) void {
        const c = p.add(v2(4, -5));
        const rad = table.ball_r * 1.1;
        const box = prerender.screenBox(r.bg.cam, c.sub(v2(rad, rad)), c.add(v2(rad, rad)), 0, 0);
        for (box.y0..box.y1) |y| for (box.x0..box.x1) |x| {
            const i = y * w + x;
            if (r.bg.obj[i] != prerender.on_floor or r.depth[i] != r.bg.depth[i]) continue;
            const q = camera.eye.add(r.bg.cam.ray(@as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5).mul(r.bg.depth[i]));
            if (v2(q.x, q.y).sub(c).len() > rad) continue;
            put(pixels, i, pal.lit(r.bg.index[i], @as(i32, r.bg.light[i]) - 9));
        };
    }

    fn flipper(r: *Renderer, pixels: []u32, pivot: V2, tip: V2) void {
        const m = table.flipper_r0;
        const box = prerender.screenBox(r.bg.cam, v2(@min(pivot.x, tip.x) - m, @min(pivot.y, tip.y) - m), v2(@max(pivot.x, tip.x) + m, @max(pivot.y, tip.y) + m), 0, table.flipper_h);
        for (box.y0..box.y1) |y| for (box.x0..box.x1) |x| {
            const d = r.ray(x, y);
            const hit = raycast.tapered(camera.eye, d, pivot, table.flipper_r0, tip, table.flipper_r1, 0, table.flipper_h) orelse continue;
            const i = y * w + x;
            if (hit.t >= r.depth[i]) continue;
            const p = camera.eye.add(d.mul(hit.t));
            const idx = if (hit.top) pal.index(.bone, 12) else pal.index(.blood, 9);
            r.depth[i] = hit.t;
            put(pixels, i, pal.lit(idx, scene.light(p, hit.n, hit.t, true)));
        };
    }

    fn plunger(r: *Renderer, pixels: []u32, pull: f32) void {
        const c = v2(370, 798 + pull * 16);
        const box = prerender.screenBox(r.bg.cam, c.sub(v2(7, 7)), c.add(v2(7, 7)), 0, 10);
        for (box.y0..box.y1) |y| for (box.x0..box.x1) |x| {
            const d = r.ray(x, y);
            const hit = raycast.cylinder(camera.eye, d, c, 7, 0, 10) orelse continue;
            const i = y * w + x;
            if (hit.t >= r.depth[i]) continue;
            const p = camera.eye.add(d.mul(hit.t));
            r.depth[i] = hit.t;
            put(pixels, i, pal.lit(pal.index(.steel, if (hit.top) 11 else 7), scene.light(p, hit.n, hit.t, true)));
        };
    }

    // chrome: the sky above reflected bright, the fiery table below dim
    fn ball(r: *Renderer, pixels: []u32, b: @import("physics.zig").Ball) void {
        const z: f32 = if (b.locked) table.ball_r - 5 else table.ball_r;
        const c = v3(b.p.x, b.p.y, z);
        const rad = table.ball_r;
        const box = prerender.screenBox(r.bg.cam, v2(c.x - rad, c.y - rad), v2(c.x + rad, c.y + rad), z - rad, z + rad);
        const key = v3(-0.45, 0.55, 1).norm();
        for (box.y0..box.y1) |y| for (box.x0..box.x1) |x| {
            const d = r.ray(x, y);
            const hit = raycast.sphere(camera.eye, d, c, rad) orelse continue;
            const i = y * w + x;
            if (hit.t >= r.depth[i]) continue;
            const v = d.norm();
            const refl = v.sub(hit.n.mul(2 * v.dot(hit.n)));
            const spec = std.math.pow(f32, @max(0, refl.dot(key)), 24);
            const idx = if (spec > 0.5)
                pal.index(.bright, 15)
            else if (refl.z < -0.2)
                pal.index(.fire, @intFromFloat(std.math.clamp(4 - refl.z * 4, 0, 9)))
            else
                pal.index(.steel, @intFromFloat(std.math.clamp(6 + refl.z * 9 + spec * 8, 0, 15)));
            r.depth[i] = hit.t;
            put(pixels, i, pal.lit(idx, 28));
        };
    }

    /// A billboard standing on the table, depth-tested at its foot; a dying
    /// demon sinks into the sludge, clipped at the floor.
    fn demon(r: *Renderer, pixels: []u32, d: demons.Demon) void {
        const frames = switch (d.kind) {
            .brute => &sprites.brute,
            .crawler => &sprites.crawler,
        };
        const spr = frames[@as(usize, @intFromFloat(d.stride / 9)) % 2];
        const tall = d.kind.height();
        const sink = if (d.state == .dying) tall * @min(1, d.timer / demons.death_time) else 0;
        const cam = r.bg.cam;
        const foot = cam.project(v3(d.p.x, d.p.y, -sink));
        const head = cam.project(v3(d.p.x, d.p.y, tall - sink));
        const floor_y = @min(foot.y, cam.project(v3(d.p.x, d.p.y, 0)).y);
        const ppt = (foot.y - head.y) / @as(f32, @floatFromInt(spr.height()));
        if (ppt <= 0) return;
        const half = ppt * @as(f32, @floatFromInt(spr.width())) / 2;
        var light = scene.light(v3(d.p.x, d.p.y, tall / 2), v3(0, 1, 0.6).norm(), foot.z, true);
        if (d.state == .pain) light += 9;
        if (d.state == .dying) light -= @intFromFloat(d.timer * 10);
        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        const y0: usize = @intFromFloat(std.math.clamp(@floor(head.y), 0, fh));
        const y1: usize = @intFromFloat(std.math.clamp(@ceil(floor_y), 0, fh));
        const x0: usize = @intFromFloat(std.math.clamp(@floor(foot.x - half), 0, fw));
        const x1: usize = @intFromFloat(std.math.clamp(@ceil(foot.x + half), 0, fw));
        for (y0..y1) |y| for (x0..x1) |x| {
            const fy = (@as(f32, @floatFromInt(y)) + 0.5 - head.y) / ppt;
            const fx = (@as(f32, @floatFromInt(x)) + 0.5 - (foot.x - half)) / ppt;
            if (fy < 0 or fx < 0) continue;
            const row: usize = @intFromFloat(fy);
            var col: usize = @intFromFloat(fx);
            if (row >= spr.height() or col >= spr.width()) continue;
            if (d.facing_left) col = spr.width() - 1 - col;
            const t = spr.at(col, row) orelse continue;
            const i = y * w + x;
            if (foot.z >= r.depth[i]) continue;
            r.depth[i] = foot.z;
            put(pixels, i, pal.lit(t.i, if (t.glow) pal.full_light else light));
        };
    }

    fn ray(r: *const Renderer, x: usize, y: usize) V3 {
        return r.bg.cam.ray(@as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5);
    }
};

test "a frame draws the ball where the camera sees it" {
    var r = try Renderer.init(std.testing.allocator);
    defer r.deinit(std.testing.allocator);
    var g = Game.init();
    g.world.balls[0].p = v2(184, 560);
    const fb = try std.testing.allocator.alloc(u32, platform.width * platform.height);
    defer std.testing.allocator.free(fb);
    r.draw(&g, fb);
    const p = r.bg.cam.project(v3(184, 560, table.ball_r));
    const i = @as(usize, @intFromFloat(p.y)) * w + @as(usize, @intFromFloat(p.x));
    try std.testing.expect(r.depth[i] < r.bg.depth[i]);
    g.bumper_flash[0] = 1;
    try std.testing.expectEqual(@as(u1, 1), states(&g)[scene.obj.bumper]);
}
