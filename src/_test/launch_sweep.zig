//! Every launch strength, from a dribble to full: the ball must never come
//! to rest where the player cannot move it (a softlock, #26). On the
//! plunger or cradled on a flipper is fine.
const std = @import("std");
const physics = @import("../physics.zig");

const frame_dt = 1.0 / 60.0;

/// Where a ball sits still for a second, away from the plunger; null if
/// it never does within `seconds`.
fn restsAt(power: f32, seconds: usize) ?physics.Ball {
    var w = physics.World{};
    w.balls[0] = .{ .active = true };
    for (0..30) |_| w.step(false, false, frame_dt);
    _ = w.launch(power);
    var still: usize = 0;
    for (0..60 * seconds) |_| {
        w.step(false, false, frame_dt);
        const b = w.balls[0];
        if (!b.active) return null;
        still = if (b.v.len() < 6 and !w.waiting(b)) still + 1 else 0;
        if (still > 60) return b;
    }
    return null;
}

test "no launch strength leaves the ball resting out of reach" {
    var i: usize = 0;
    while (i <= 200) : (i += 1) {
        const power = @as(f32, @floatFromInt(i)) / 200;
        if (restsAt(power, 20)) |b| {
            std.debug.print("power {d:.3}: the ball rests at ({d:.1}, {d:.1})\n", .{ power, b.p.x, b.p.y });
            return error.BallStuck;
        }
    }
}
