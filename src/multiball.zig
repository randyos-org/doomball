//! Multiball: a ball in the lock starts it; the lock kicks that ball out
//! after a moment, two more are plunged one after the other, and a ball
//! save covers the start. It ends when one ball is left.
const std = @import("std");
const vec = @import("vec.zig");
const table = @import("table.zig");
const physics = @import("physics.zig");

const v2 = vec.v2;

const release_after: f32 = 1.2;
/// the gate closes once the released ball has left the alcove
const close_after: f32 = 0.9;
const spawn_every: f32 = 0.8;
pub const save_seconds: f32 = 10;
/// how hard the auto-plunger launches
const auto_launch: f32 = 1450;

pub const Multiball = struct {
    on: bool = false,
    /// seconds of ball save left
    save: f32 = 0,
    release: ?f32 = null,
    close_gate: ?f32 = null,
    /// balls still to be plunged
    pending: u8 = 0,
    spawn: f32 = 0,

    pub fn start(m: *Multiball) void {
        m.* = .{ .on = true, .save = save_seconds, .release = release_after, .pending = physics.max_balls - 1, .spawn = 0.4 };
    }

    /// A ball drained: during the ball save, another is plunged instead.
    pub fn saved(m: *Multiball) bool {
        if (m.save <= 0) return false;
        m.pending += 1;
        return true;
    }

    /// Whether balls are still to come into play.
    pub fn busy(m: *const Multiball) bool {
        return m.release != null or m.pending > 0;
    }

    /// True when multiball has just ended.
    pub fn update(m: *Multiball, w: *physics.World, dt: f32) bool {
        m.save = @max(0, m.save - dt);
        if (m.release) |*t| {
            t.* -= dt;
            if (t.* <= 0) {
                for (&w.balls) |*b| {
                    if (!b.locked) continue;
                    b.locked = false;
                    b.p = table.lock_c.add(v2(-4, 14));
                    b.v = v2(-260, 380);
                }
                m.release = null;
                m.close_gate = close_after;
            }
        }
        if (m.close_gate) |*t| {
            t.* -= dt;
            if (t.* <= 0) {
                w.gate_closed = true;
                m.close_gate = null;
            }
        }
        if (m.pending > 0) {
            m.spawn -= dt;
            if (m.spawn <= 0 and plunge(w)) {
                m.pending -= 1;
                m.spawn = spawn_every;
            }
        }
        if (m.on and !m.busy() and w.activeBalls() <= 1) {
            m.on = false;
            m.save = 0;
            return true;
        }
        return false;
    }
};

/// Puts a ball into play up the plunger lane, if a ball is free and the
/// lane's foot is clear.
pub fn plunge(w: *physics.World) bool {
    for (w.balls) |b| {
        if (b.active and b.p.x > table.lane_x and b.p.y > table.lane_y) return false;
    }
    for (&w.balls) |*b| {
        if (b.active) continue;
        b.* = .{ .active = true, .v = v2(0, -auto_launch) };
        return true;
    }
    return false;
}

const frame_dt = 1.0 / 60.0;

test "multiball kicks the locked ball out, plunges two more and closes the gate" {
    var w = physics.World{ .gate_closed = false };
    w.balls[0] = .{ .active = true, .locked = true, .p = table.lock_c };
    var m = Multiball{};
    m.start();
    var most: usize = 0;
    for (0..60 * 4) |_| {
        _ = m.update(&w, frame_dt);
        w.step(false, false, frame_dt);
        most = @max(most, w.activeBalls());
    }
    try std.testing.expect(!w.balls[0].locked);
    try std.testing.expect(w.gate_closed);
    try std.testing.expectEqual(@as(u8, 0), m.pending);
    try std.testing.expectEqual(@as(usize, 3), most);
}

test "the ball save plunges another ball, and multiball ends with one left" {
    var w = physics.World{};
    w.balls[0] = .{ .active = true, .p = v2(184, 500) };
    var m = Multiball{ .on = true, .save = 2 };
    try std.testing.expect(m.saved());
    _ = m.update(&w, frame_dt);
    try std.testing.expectEqual(@as(usize, 2), w.activeBalls());
    w.balls[1].active = false;
    m.save = 0;
    try std.testing.expect(!m.saved());
    try std.testing.expect(m.update(&w, frame_dt));
    try std.testing.expect(!m.on);
}
