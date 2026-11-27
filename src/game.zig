//! Platform-independent pinball game: physics, rules and software rendering.
const std = @import("std");
const platform = @import("platform.zig");
const render = @import("render.zig");

pub const W: f32 = platform.width;
pub const H: f32 = platform.height;

const gravity: f32 = 420;
const ball_r: f32 = 4;
const substeps = 10;
const flipper_len: f32 = 32;
const flipper_r: f32 = 3;
const flipper_rest: f32 = 0.52;
const flipper_up: f32 = -0.52;
const flipper_speed: f32 = 22;
const lane_x: f32 = 214;
const start_balls = 3;

const Vec = struct {
    x: f32,
    y: f32,

    fn add(a: Vec, b: Vec) Vec {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    fn sub(a: Vec, b: Vec) Vec {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    fn mul(a: Vec, s: f32) Vec {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    fn dot(a: Vec, b: Vec) f32 {
        return a.x * b.x + a.y * b.y;
    }
    fn len(a: Vec) f32 {
        return @sqrt(a.dot(a));
    }
};

const Segment = struct { a: Vec, b: Vec };

const Bumper = struct { pos: Vec, r: f32, flash: f32 = 0 };

const Flipper = struct {
    pivot: Vec,
    dir: f32, // +1: tip points right, -1: tip points left
    angle: f32 = flipper_rest,
    omega: f32 = 0,

    fn tip(self: Flipper) Vec {
        return self.tipAt(self.angle);
    }
    fn tipAt(self: Flipper, a: f32) Vec {
        return .{ .x = self.pivot.x + self.dir * flipper_len * @cos(a), .y = self.pivot.y + flipper_len * @sin(a) };
    }
    fn step(self: *Flipper, pressed: bool, dt: f32) void {
        const target: f32 = if (pressed) flipper_up else flipper_rest;
        const old = self.angle;
        const d = target - self.angle;
        const max = flipper_speed * dt;
        self.angle += std.math.clamp(d, -max, max);
        self.omega = (self.angle - old) / dt;
    }
};

const arc_steps = 20;
const static_segments = blk: {
    var s: [arc_steps + 7]Segment = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < arc_steps) : (i += 1) {
        const t0 = std.math.pi * @as(f32, @floatFromInt(i)) / arc_steps;
        const t1 = std.math.pi * @as(f32, @floatFromInt(i + 1)) / arc_steps;
        s[n] = .{
            .a = .{ .x = 120 + 110 * @cos(t0), .y = 120 - 110 * @sin(t0) },
            .b = .{ .x = 120 + 110 * @cos(t1), .y = 120 - 110 * @sin(t1) },
        };
        n += 1;
    }
    s[n] = .{ .a = .{ .x = 10, .y = 120 }, .b = .{ .x = 10, .y = 240 } };
    n += 1;
    s[n] = .{ .a = .{ .x = 10, .y = 240 }, .b = .{ .x = 73, .y = 297 } };
    n += 1;
    s[n] = .{ .a = .{ .x = lane_x, .y = 240 }, .b = .{ .x = 151, .y = 297 } };
    n += 1;
    s[n] = .{ .a = .{ .x = 230, .y = 120 }, .b = .{ .x = 230, .y = 330 } };
    n += 1;
    s[n] = .{ .a = .{ .x = lane_x, .y = 150 }, .b = .{ .x = lane_x, .y = 240 } };
    n += 1;
    s[n] = .{ .a = .{ .x = lane_x, .y = 240 }, .b = .{ .x = lane_x, .y = 330 } };
    n += 1;
    s[n] = .{ .a = .{ .x = lane_x, .y = 330 }, .b = .{ .x = 230, .y = 330 } };
    n += 1;
    break :blk s;
};

pub const Phase = enum { playing, game_over };

pub const Game = struct {
    ball: Vec = .{ .x = 222, .y = 324 },
    vel: Vec = .{ .x = 0, .y = 0 },
    bumpers: [4]Bumper = .{
        .{ .pos = .{ .x = 85, .y = 150 }, .r = 15 },
        .{ .pos = .{ .x = 155, .y = 150 }, .r = 15 },
        .{ .pos = .{ .x = 120, .y = 195 }, .r = 15 },
        .{ .pos = .{ .x = 50, .y = 205 }, .r = 10 },
    },
    flippers: [2]Flipper = .{
        .{ .pivot = .{ .x = 76, .y = 300 }, .dir = 1 },
        .{ .pivot = .{ .x = 148, .y = 300 }, .dir = -1 },
    },
    score: u32 = 0,
    balls_left: u8 = start_balls,
    plunger: f32 = 0,
    phase: Phase = .playing,
    prev_start: bool = false,
    time: f32 = 0,

    pub fn update(self: *Game, in: platform.Input, dt: f32) void {
        self.time += dt;
        const start_edge = in.start and !self.prev_start;
        self.prev_start = in.start;

        if (self.phase == .game_over) {
            if (start_edge or (in.plunger)) self.reset();
            return;
        }

        for (&self.bumpers) |*b| b.flash = @max(0, b.flash - dt);

        self.flippers[0].step(in.left, dt);
        self.flippers[1].step(in.right, dt);

        const in_lane = self.ball.x > lane_x and self.ball.y > 290;
        if (in.plunger) {
            self.plunger = @min(1, self.plunger + dt * 1.2);
        } else if (self.plunger > 0) {
            if (in_lane and @abs(self.vel.y) < 60) self.vel.y = -(300 + 320 * self.plunger);
            self.plunger = 0;
        }

        const h = dt / substeps;
        for (0..substeps) |_| self.substep(h);

        if (self.ball.y > H + 20) {
            self.balls_left -|= 1;
            if (self.balls_left == 0) {
                self.phase = .game_over;
            } else {
                self.serve();
            }
        }
    }

    fn serve(self: *Game) void {
        self.ball = .{ .x = 222, .y = 324 };
        self.vel = .{ .x = 0, .y = 0 };
    }

    pub fn reset(self: *Game) void {
        self.* = .{};
        self.prev_start = true;
    }

    fn substep(self: *Game, h: f32) void {
        self.vel.y += gravity * h;
        self.ball = self.ball.add(self.vel.mul(h));

        for (static_segments) |s| self.collide(s.a, s.b, 1.0, .{ .x = 0, .y = 0 }, 0.45);

        for (self.flippers) |f| {
            const a = f.pivot;
            const b = f.tip();
            const ab = b.sub(a);
            const t = std.math.clamp(self.ball.sub(a).dot(ab) / ab.dot(ab), 0, 1);
            const ang_dir = Vec{ .x = -f.dir * @sin(f.angle), .y = @cos(f.angle) };
            const sv = ang_dir.mul(t * flipper_len * f.omega);
            self.collide(a, b, flipper_r, sv, 0.3);
        }

        for (&self.bumpers) |*bp| {
            const d = self.ball.sub(bp.pos);
            const dist = d.len();
            const min = bp.r + ball_r;
            if (dist < min and dist > 0.0001) {
                const n = d.mul(1 / dist);
                self.ball = bp.pos.add(n.mul(min));
                const vn = self.vel.dot(n);
                if (vn < 0) self.vel = self.vel.sub(n.mul(vn * 2));
                self.vel = self.vel.add(n.mul(140));
                self.score += 100;
                bp.flash = 0.12;
            }
        }

        const sp = self.vel.len();
        if (sp > 900) self.vel = self.vel.mul(900 / sp);
    }

    fn collide(self: *Game, a: Vec, b: Vec, thick: f32, surf: Vec, restitution: f32) void {
        const ab = b.sub(a);
        const t = std.math.clamp(self.ball.sub(a).dot(ab) / ab.dot(ab), 0, 1);
        const p = a.add(ab.mul(t));
        const d = self.ball.sub(p);
        const dist = d.len();
        const min = ball_r + thick;
        if (dist >= min or dist < 0.0001) return;
        const n = d.mul(1 / dist);
        self.ball = p.add(n.mul(min));
        const vn = self.vel.sub(surf).dot(n);
        if (vn < 0) self.vel = self.vel.sub(n.mul(vn * (1 + restitution)));
    }

    // ---- rendering ----

    const c_bg: u32 = 0x1a0d08;
    const c_brick: u32 = 0x3a1c10;
    const c_wall: u32 = 0x8a8a8a;
    const c_blood: u32 = 0xb01010;
    const c_fire: u32 = 0xff8a1a;
    const c_gold: u32 = 0xe8c030;

    pub fn render(self: *const Game, pixels: []u32) void {
        const cv = render_mod.Canvas{ .pixels = pixels, .w = platform.width, .h = platform.height };

        var y: i32 = 0;
        while (y < platform.height) : (y += 1) {
            var x: i32 = 0;
            while (x < platform.width) : (x += 1) {
                const row = @divFloor(y, 12);
                const off: i32 = if (@mod(row, 2) == 0) 0 else 12;
                const mortar = @mod(y, 12) == 0 or @mod(x + off, 24) == 0;
                cv.put(x, y, if (mortar) c_bg else c_brick);
            }
        }

        // playfield interior
        for (0..platform.height) |yy| {
            for (0..platform.width) |xx| {
                const fx: f32 = @floatFromInt(xx);
                const fy: f32 = @floatFromInt(yy);
                const dx = fx - 120;
                const dy = fy - 120;
                const inside_arc = fy >= 120 or (dx * dx + dy * dy < 110 * 110);
                if (inside_arc and fx > 10 and fx < 230 and fy < 330) {
                    const shade: u32 = 0x10 + @as(u32, @intCast(yy / 12));
                    cv.put(@intCast(xx), @intCast(yy), (shade << 16) | ((shade / 4) << 8));
                }
            }
        }

        for (static_segments) |s| cv.line(s.a.x, s.a.y, s.b.x, s.b.y, 1.5, c_wall);

        for (self.bumpers) |b| {
            cv.disc(b.pos.x, b.pos.y, b.r, if (b.flash > 0) c_fire else c_blood);
            cv.disc(b.pos.x, b.pos.y, b.r - 3, if (b.flash > 0) c_gold else 0x600808);
            const e = b.r * 0.35;
            cv.disc(b.pos.x - e, b.pos.y - 2, 1.8, c_gold);
            cv.disc(b.pos.x + e, b.pos.y - 2, 1.8, c_gold);
            cv.rect(@intFromFloat(b.pos.x - e), @intFromFloat(b.pos.y + 3), @intFromFloat(e * 2 + 1), 1, 0x000000);
        }

        for (self.flippers) |f| {
            const t = f.tip();
            cv.line(f.pivot.x, f.pivot.y, t.x, t.y, flipper_r, 0x4a8a3a);
            cv.disc(f.pivot.x, f.pivot.y, flipper_r + 1, c_gold);
        }

        // plunger
        const pl: i32 = @intFromFloat(self.plunger * 14);
        cv.rect(217, 326 + pl, 10, 4, 0xaaaaaa);

        cv.disc(self.ball.x, self.ball.y, ball_r, c_fire);
        cv.disc(self.ball.x - 1, self.ball.y - 1, 2, 0xffee99);

        var buf: [32]u8 = undefined;
        const title = "DOOMBALL";
        cv.text(title, 120 - @divTrunc(render_mod.Canvas.textWidth(title, 2), 2), 38, 2, c_blood);
        const sc = std.fmt.bufPrint(&buf, "SCORE {d}", .{self.score}) catch "";
        cv.text(sc, 120 - @divTrunc(render_mod.Canvas.textWidth(sc, 1), 2), 58, 1, c_gold);
        const bl = std.fmt.bufPrint(&buf, "BALLS {d}", .{self.balls_left}) catch "";
        cv.text(bl, 120 - @divTrunc(render_mod.Canvas.textWidth(bl, 1), 2), 68, 1, c_gold);

        if (self.phase == .game_over) {
            cv.rect(30, 150, 180, 50, 0x000000);
            cv.text("GAME OVER", 120 - @divTrunc(render_mod.Canvas.textWidth("GAME OVER", 2), 2), 158, 2, c_blood);
            cv.text("PRESS SPACE", 120 - @divTrunc(render_mod.Canvas.textWidth("PRESS SPACE", 1), 2), 182, 1, c_gold);
        }
    }
};

const render_mod = render;

test "ball starts in lane and plunger launches it upward" {
    var g = Game{};
    const dt = 1.0 / 60.0;
    for (0..60) |_| g.update(.{ .plunger = true }, dt);
    g.update(.{}, dt);
    try std.testing.expect(g.vel.y < -100);
    for (0..30) |_| g.update(.{}, dt);
    try std.testing.expect(g.ball.y < 300);
}

test "ball stays inside the table walls" {
    var g = Game{};
    const dt = 1.0 / 60.0;
    for (0..60) |_| g.update(.{ .plunger = true }, dt);
    for (0..600) |i| {
        g.update(.{ .left = i % 40 < 10, .right = i % 50 < 10 }, dt);
        try std.testing.expect(g.ball.x > 0 and g.ball.x < W);
    }
}

test "draining all balls ends the game and start resets" {
    var g = Game{};
    const dt = 1.0 / 60.0;
    for (0..60 * 120) |i| {
        // launch whenever ball sits in the lane
        const launch = g.ball.x > lane_x and g.ball.y > 290 and i % 90 < 80;
        g.update(.{ .plunger = launch }, dt);
        if (g.phase == .game_over) break;
    }
    try std.testing.expectEqual(Phase.game_over, g.phase);
    g.update(.{ .start = true }, dt);
    try std.testing.expectEqual(Phase.playing, g.phase);
    try std.testing.expectEqual(@as(u8, start_balls), g.balls_left);
}

test "flipper hits ball upward" {
    var g = Game{};
    g.ball = .{ .x = 90, .y = 300.5 };
    g.vel = .{ .x = 0, .y = 0 };
    const dt = 1.0 / 60.0;
    var min_vy: f32 = 0;
    for (0..30) |_| {
        g.update(.{ .left = true }, dt);
        min_vy = @min(min_vy, g.vel.y);
    }
    try std.testing.expect(min_vy < -100);
}

test "render fills framebuffer" {
    var g = Game{};
    var fb: [platform.width * platform.height]u32 = undefined;
    g.render(&fb);
    try std.testing.expect(fb[0] != 0);
}
