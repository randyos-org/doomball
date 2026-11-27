//! Balls on the table plane: gravity, the table's walls and parts, the
//! flippers, demons and each other. `World.step` reports what happened as
//! events for the rules.
const std = @import("std");
const vec = @import("vec.zig");
const table = @import("table.zig");

const V2 = vec.V2;
const v2 = vec.v2;

pub const max_balls = 3;
pub const max_demons = 4;
pub const substeps = 12;
const max_speed: f32 = 2200;
const max_events = 64;
/// Impacts slower than this make no event (a ball resting on a wall).
const quiet: f32 = 60;

pub const Ball = struct {
    p: V2 = table.plunger_rest,
    v: V2 = v2(0, 0),
    active: bool = false,
    /// held in the lock
    locked: bool = false,
    /// the rollovers it is over, a bit each
    over: u8 = 0,
};

pub const Circle = struct { c: V2, r: f32 };

pub const Flipper = struct {
    spec: table.FlipperSpec,
    angle: f32 = table.flipper_rest,
    omega: f32 = 0,

    pub fn tipAt(self: Flipper, a: f32) V2 {
        return v2(self.spec.pivot.x + self.spec.dir * table.flipper_len * @cos(a), self.spec.pivot.y + table.flipper_len * @sin(a));
    }

    pub fn tip(self: Flipper) V2 {
        return self.tipAt(self.angle);
    }

    /// Moves toward up or rest; true when it starts swinging up.
    fn step(self: *Flipper, pressed: bool, dt: f32) bool {
        const target: f32 = if (pressed) table.flipper_up else table.flipper_rest;
        const old = self.angle;
        const max = table.flipper_speed * dt;
        self.angle += std.math.clamp(target - self.angle, -max, max);
        const was_still = self.omega >= 0;
        self.omega = (self.angle - old) / dt;
        return pressed and was_still and self.omega < 0;
    }
};

pub const EventKind = enum { wall, rubber, sling, bumper, target, rollover, gate, flipper, flipper_up, demon, lock, drain };

pub const Event = struct {
    kind: EventKind,
    /// which bumper, target, rollover, demon or flipper
    id: u8 = 0,
    ball: u8 = 0,
    speed: f32 = 0,
};

const Contact = struct { n: V2, depth: f32 };

fn capsuleContact(p: V2, a: V2, b: V2, r: f32) ?Contact {
    const t = vec.nearestOnSegment(p, a, b);
    const q = a.mix(b, t);
    const d = p.sub(q);
    const dist = d.len();
    const min = r + table.ball_r;
    if (dist >= min) return null;
    const n = if (dist > 1e-6) d.mul(1 / dist) else b.sub(a).perp().norm();
    return .{ .n = n, .depth = min - dist };
}

fn circleContact(p: V2, c: V2, r: f32) ?Contact {
    return capsuleContact(p, c, c, r);
}

pub const World = struct {
    balls: [max_balls]Ball = @splat(.{}),
    flippers: [2]Flipper = .{ .{ .spec = table.flippers[0] }, .{ .spec = table.flippers[1] } },
    gate_closed: bool = true,
    /// set by the rules each frame
    demons: [max_demons]?Circle = @splat(null),
    events: [max_events]Event = undefined,
    n_events: usize = 0,

    pub fn eventList(self: *const World) []const Event {
        return self.events[0..self.n_events];
    }

    pub fn activeBalls(self: *const World) usize {
        var n: usize = 0;
        for (self.balls) |b| n += @intFromBool(b.active);
        return n;
    }

    /// One frame: the flippers, then `substeps` steps of the balls.
    pub fn step(self: *World, left: bool, right: bool, dt: f32) void {
        self.n_events = 0;
        for (&self.flippers, [2]bool{ left, right }, 0..) |*f, pressed, i| {
            if (f.step(pressed, dt)) self.emit(.{ .kind = .flipper_up, .id = @intCast(i) });
        }
        const h = dt / substeps;
        for (0..substeps) |_| self.substep(h);
    }

    fn emit(self: *World, e: Event) void {
        if (self.n_events == max_events) return;
        self.events[self.n_events] = e;
        self.n_events += 1;
    }

    fn substep(self: *World, h: f32) void {
        for (&self.balls, 0..) |*b, i| {
            if (!b.active or b.locked) continue;
            b.v.y += table.gravity * h;
            b.p = b.p.add(b.v.mul(h));
            self.collideTable(b, @intCast(i));
            self.sense(b, @intCast(i));
            const sp = b.v.len();
            if (sp > max_speed) b.v = b.v.mul(max_speed / sp);
        }
        self.collideBalls();
    }

    /// Pushes the ball out along the contact and reflects its velocity
    /// relative to a surface moving at `surf`; returns the impact speed.
    fn resolve(b: *Ball, c: Contact, surf: V2, restitution: f32) f32 {
        b.p = b.p.add(c.n.mul(c.depth));
        const vn = b.v.sub(surf).dot(c.n);
        if (vn >= 0) return 0;
        b.v = b.v.sub(c.n.mul(vn * (1 + restitution)));
        return -vn;
    }

    fn collideTable(self: *World, b: *Ball, bi: u8) void {
        const still = v2(0, 0);
        for (table.walls) |w| {
            if (w.kind == .oneway) {
                const wn = w.b.sub(w.a).perp().norm();
                if (b.v.dot(wn) >= 0 or b.p.sub(w.a).dot(wn) < 0) continue;
            }
            const c = capsuleContact(b.p, w.a, w.b, w.r) orelse continue;
            const e: f32 = switch (w.kind) {
                .wall, .oneway => 0.45,
                .rubber, .sling => 0.7,
            };
            const s = resolve(b, c, still, e);
            if (w.kind == .sling and s > 30) {
                b.v = b.v.add(c.n.mul(table.sling_kick));
                self.emit(.{ .kind = .sling, .id = if (w.a.x < table.axis_x) 0 else 1, .ball = bi, .speed = s });
            } else if (s > quiet) {
                self.emit(.{ .kind = if (w.kind == .rubber) .rubber else .wall, .ball = bi, .speed = s });
            }
        }
        if (self.gate_closed) {
            if (capsuleContact(b.p, table.gate.a, table.gate.b, table.gate.r)) |c| {
                const s = resolve(b, c, still, 0.4);
                if (s > quiet) self.emit(.{ .kind = .gate, .ball = bi, .speed = s });
            }
        }
        for (table.targets, 0..) |t, i| {
            const c = capsuleContact(b.p, t.a, t.b, t.r) orelse continue;
            const s = resolve(b, c, still, 0.4);
            if (s > 40) self.emit(.{ .kind = .target, .id = @intCast(i), .ball = bi, .speed = s });
        }
        for (table.bumpers, 0..) |bp, i| {
            const c = circleContact(b.p, bp.c, bp.r) orelse continue;
            const s = resolve(b, c, still, 0.5);
            b.v = b.v.add(c.n.mul(table.bumper_kick));
            self.emit(.{ .kind = .bumper, .id = @intCast(i), .ball = bi, .speed = s });
        }
        for (self.flippers, 0..) |f, i| {
            const a = f.spec.pivot;
            const tp = f.tip();
            const t = vec.nearestOnSegment(b.p, a, tp);
            const r = table.flipper_r0 + (table.flipper_r1 - table.flipper_r0) * t;
            const c = capsuleContact(b.p, a.mix(tp, t), a.mix(tp, t), r) orelse continue;
            const swing = v2(-f.spec.dir * @sin(f.angle), @cos(f.angle)).mul(t * table.flipper_len * f.omega);
            const s = resolve(b, c, swing, 0.25);
            if (s > quiet * 2) self.emit(.{ .kind = .flipper, .id = @intCast(i), .ball = bi, .speed = s });
        }
        for (self.demons, 0..) |d, i| {
            const dm = d orelse continue;
            const c = circleContact(b.p, dm.c, dm.r) orelse continue;
            const s = resolve(b, c, still, 0.6);
            if (s > 30) self.emit(.{ .kind = .demon, .id = @intCast(i), .ball = bi, .speed = s });
        }
    }

    fn sense(self: *World, b: *Ball, bi: u8) void {
        for (table.rollovers, 0..) |ro, i| {
            const bit = @as(u8, 1) << @intCast(i);
            const d = b.p.sub(ro.c).len();
            if (d < ro.r and b.over & bit == 0) {
                b.over |= bit;
                self.emit(.{ .kind = .rollover, .id = @intCast(i), .ball = bi });
            } else if (d > ro.r + 6) b.over &= ~bit;
        }
        if (!self.gate_closed and b.p.sub(table.lock_c).len() < table.lock_r) {
            b.locked = true;
            b.p = table.lock_c;
            b.v = v2(0, 0);
            self.emit(.{ .kind = .lock, .ball = bi });
        }
        if (b.p.y > table.drain_y) {
            b.active = false;
            self.emit(.{ .kind = .drain, .ball = bi });
        }
    }

    // equal masses: swap the velocity along the line between centers
    fn collideBalls(self: *World) void {
        for (0..max_balls) |i| {
            for (i + 1..max_balls) |j| {
                const a = &self.balls[i];
                const b = &self.balls[j];
                if (!a.active or !b.active) continue;
                const d = b.p.sub(a.p);
                const dist = d.len();
                const min = 2 * table.ball_r;
                if (dist >= min or dist < 1e-6) continue;
                const n = d.mul(1 / dist);
                const push = n.mul((min - dist) / 2);
                if (!a.locked) a.p = a.p.sub(push);
                if (!b.locked) b.p = b.p.add(push);
                const rel = b.v.sub(a.v).dot(n);
                if (rel >= 0) continue;
                if (!a.locked) a.v = a.v.add(n.mul(rel));
                if (!b.locked) b.v = b.v.sub(n.mul(rel));
            }
        }
    }

    /// Launches every ball resting in the plunger lane at `power` 0..1;
    /// true when one went.
    pub fn launch(self: *World, power: f32) bool {
        var any = false;
        for (&self.balls) |*b| {
            if (!b.active or b.p.x < table.lane_x or b.p.y < table.lane_y or @abs(b.v.y) > 80) continue;
            b.v.y = -(table.launch_min + (table.launch_max - table.launch_min) * std.math.clamp(power, 0, 1));
            any = true;
        }
        return any;
    }
};

const frame_dt = 1.0 / 60.0;

fn served() World {
    var w = World{};
    w.balls[0] = .{ .active = true };
    return w;
}

fn has(w: *const World, k: EventKind) bool {
    for (w.eventList()) |e| if (e.kind == k) return true;
    return false;
}

test "a served ball settles on the plunger and a full launch sends it round the arch" {
    var w = served();
    for (0..30) |_| w.step(false, false, frame_dt);
    try std.testing.expect(@abs(w.balls[0].p.y - table.plunger_rest.y) < 2);
    try std.testing.expect(w.launch(1));
    var top: f32 = 1000;
    for (0..120) |_| {
        w.step(false, false, frame_dt);
        top = @min(top, w.balls[0].p.y);
    }
    try std.testing.expect(top < 60);
    // it came out of the lane, over to the playfield
    try std.testing.expect(w.balls[0].p.x < table.field_right);
}

test "the ball stays on the table until it drains" {
    var w = served();
    _ = w.launch(0.8);
    var drained = false;
    for (0..60 * 60) |i| {
        w.step(i % 50 < 8, i % 70 < 8, frame_dt);
        if (has(&w, .drain)) {
            drained = true;
            break;
        }
        const p = w.balls[0].p;
        try std.testing.expect(p.x > 0 and p.x < table.width and p.y > 0);
    }
    try std.testing.expect(drained);
}

test "a flipper sends a ball on it up the table" {
    var w = World{};
    const f = w.flippers[0];
    const on = f.spec.pivot.mix(f.tip(), 0.6).add(v2(0, -(table.ball_r + 8)));
    w.balls[0] = .{ .active = true, .p = on };
    var min_vy: f32 = 0;
    for (0..20) |_| {
        w.step(true, false, frame_dt);
        min_vy = @min(min_vy, w.balls[0].v.y);
    }
    try std.testing.expect(min_vy < -600);
}

test "a bumper kicks the ball away and says so" {
    var w = World{};
    const bp = table.bumpers[2];
    w.balls[0] = .{ .active = true, .p = bp.c.add(v2(0, -(bp.r + table.ball_r + 2))), .v = v2(0, 200) };
    var bumped = false;
    for (0..5) |_| {
        w.step(false, false, frame_dt);
        bumped = bumped or has(&w, .bumper);
    }
    try std.testing.expect(bumped);
    try std.testing.expect(w.balls[0].v.y < 0);
}

test "the lane gate lets the ball up but not back down" {
    var w = World{};
    w.balls[0] = .{ .active = true, .p = v2(370, 220), .v = v2(0, 100) };
    for (0..30) |_| w.step(false, false, frame_dt);
    try std.testing.expect(w.balls[0].p.y < 236);
}

test "the lock holds a ball only once the gate is open" {
    var w = World{};
    w.balls[0] = .{ .active = true, .p = table.lock_c, .v = v2(0, 0) };
    w.step(false, false, frame_dt);
    try std.testing.expect(!w.balls[0].locked);
    w = World{ .gate_closed = false };
    w.balls[0] = .{ .active = true, .p = table.lock_c.add(v2(0, 4)), .v = v2(0, -50) };
    w.step(false, false, frame_dt);
    try std.testing.expect(w.balls[0].locked);
    try std.testing.expect(has(&w, .lock));
}

test "two balls bounce off each other" {
    var w = World{};
    w.balls[0] = .{ .active = true, .p = v2(150, 500), .v = v2(300, 0) };
    w.balls[1] = .{ .active = true, .p = v2(180, 500), .v = v2(-300, 0) };
    for (0..6) |_| w.step(false, false, frame_dt);
    try std.testing.expect(w.balls[0].v.x < 0 and w.balls[1].v.x > 0);
}

test "rolling over a lane reports it once" {
    var w = World{};
    w.balls[0] = .{ .active = true, .p = v2(144, 70), .v = v2(0, 120) };
    var n: usize = 0;
    for (0..20) |_| {
        w.step(false, false, frame_dt);
        for (w.eventList()) |e| n += @intFromBool(e.kind == .rollover);
    }
    try std.testing.expectEqual(@as(usize, 1), n);
}
