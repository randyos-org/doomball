//! The table: one description for the physics and the renderer, so what is
//! drawn is what the ball hits. Units: 400 across (x, right), 800 along
//! (y, toward the player), z up; the playfield is z = 0.
const std = @import("std");
const vec = @import("vec.zig");
const Tex = @import("textures.zig").Tex;

const V2 = vec.V2;
const v2 = vec.v2;

pub const width: f32 = 400;
pub const length: f32 = 800;
/// A ball whose center passes this has drained.
pub const drain_y: f32 = 840;

pub const ball_r: f32 = 8;
pub const gravity: f32 = 820;

/// The playfield proper, left of the plunger lane; mirrored around `axis_x`.
pub const field_left: f32 = 20;
pub const field_right: f32 = 348;
pub const axis_x: f32 = 184;

pub const Wall = struct {
    a: V2,
    b: V2,
    /// half thickness
    r: f32,
    /// height above the playfield
    h: f32 = 24,
    side: Tex = .bloodmetal,
    top: Tex = .tech,
    kind: Kind = .wall,
};

pub const Kind = enum {
    wall,
    /// lively rubber: bounces more
    rubber,
    /// a slingshot's kicking face
    sling,
    /// lets the ball pass in the direction of its normal (a, b turned left)
    oneway,
};

// the top arch, from the left wall over to the right
const arch_cx: f32 = 202;
const arch_cy: f32 = 196;
const arch_r: f32 = 188;
const arch_steps = 24;

fn archPoint(i: usize) V2 {
    const t = std.math.pi + std.math.pi * @as(f32, @floatFromInt(i)) / arch_steps;
    return v2(arch_cx + arch_r * @cos(t), arch_cy + arch_r * @sin(t));
}

fn mirror(p: V2) V2 {
    return v2(2 * axis_x - p.x, p.y);
}

// slingshot corners, left side: top, bottom, inner
const sling_l = [3]V2{ v2(70, 540), v2(70, 616), v2(104, 642) };
const sling_r = [3]V2{ mirror(sling_l[0]), mirror(sling_l[1]), mirror(sling_l[2]) };

pub const walls = blk: {
    var w: [arch_steps + 32]Wall = undefined;
    var n: usize = 0;
    for (0..arch_steps) |i| {
        w[n] = .{ .a = archPoint(i), .b = archPoint(i + 1), .r = 6, .h = 40 };
        n += 1;
    }
    const outer = [_]Wall{
        // outer walls and the plunger lane
        .{ .a = v2(14, arch_cy), .b = v2(14, 830), .r = 6, .h = 40 },
        .{ .a = v2(390, arch_cy), .b = v2(390, 830), .r = 6, .h = 40 },
        .{ .a = v2(352, 262), .b = v2(352, 830), .r = 4, .h = 32 },
        .{ .a = v2(352, 792), .b = v2(390, 792), .r = 4, .h = 32 },
        // the lane's one-way gate: the ball goes up, never back down
        .{ .a = v2(356, 236), .b = v2(384, 236), .r = 2, .h = 10, .kind = .oneway, .side = .grate },
        // top lane guides
        .{ .a = v2(124, 70), .b = v2(124, 110), .r = 4, .h = 18, .kind = .rubber },
        .{ .a = v2(164, 70), .b = v2(164, 110), .r = 4, .h = 18, .kind = .rubber },
        .{ .a = v2(204, 70), .b = v2(204, 110), .r = 4, .h = 18, .kind = .rubber },
        .{ .a = v2(244, 70), .b = v2(244, 110), .r = 4, .h = 18, .kind = .rubber },
        // inlane guides
        .{ .a = v2(46, 590), .b = v2(46, 650), .r = 4, .h = 20 },
        .{ .a = v2(46, 650), .b = v2(108, 704), .r = 4, .h = 20 },
        .{ .a = mirror(v2(46, 590)), .b = mirror(v2(46, 650)), .r = 4, .h = 20 },
        .{ .a = mirror(v2(46, 650)), .b = mirror(v2(108, 704)), .r = 4, .h = 20 },
        // slingshots: rubber sides, a kicking face toward the middle
        .{ .a = sling_l[0], .b = sling_l[1], .r = 4, .h = 22, .kind = .rubber },
        .{ .a = sling_l[1], .b = sling_l[2], .r = 4, .h = 22, .kind = .rubber },
        .{ .a = sling_l[2], .b = sling_l[0], .r = 4, .h = 22, .kind = .sling, .side = .hellstone },
        .{ .a = sling_r[1], .b = sling_r[0], .r = 4, .h = 22, .kind = .rubber },
        .{ .a = sling_r[2], .b = sling_r[1], .r = 4, .h = 22, .kind = .rubber },
        .{ .a = sling_r[0], .b = sling_r[2], .r = 4, .h = 22, .kind = .sling, .side = .hellstone },
        // the lock's alcove, against the lane wall
        .{ .a = v2(292, 268), .b = v2(348, 268), .r = 4, .h = 28 },
        .{ .a = v2(292, 268), .b = v2(292, 318), .r = 4, .h = 28 },
    };
    for (outer) |o| {
        w[n] = o;
        n += 1;
    }
    break :blk w[0..n].*;
};

pub const Bumper = struct { c: V2, r: f32 = 22, h: f32 = 26 };
pub const bumpers = [_]Bumper{ .{ .c = v2(144, 214) }, .{ .c = v2(224, 214) }, .{ .c = v2(184, 272) } };
pub const bumper_kick: f32 = 380;
pub const sling_kick: f32 = 520;

/// Rollover lanes at the top: sensors the ball rolls over.
pub const Rollover = struct { c: V2, r: f32 = 10 };
pub const rollovers = [_]Rollover{ .{ .c = v2(144, 92) }, .{ .c = v2(184, 92) }, .{ .c = v2(224, 92) } };

pub const TargetKind = enum { key_red, key_blue, key_yellow, mission };
pub const Target = struct { a: V2, b: V2, kind: TargetKind, r: f32 = 4, h: f32 = 20 };
pub const targets = [_]Target{
    .{ .a = v2(26, 286), .b = v2(26, 314), .kind = .key_red },
    .{ .a = v2(26, 336), .b = v2(26, 364), .kind = .key_blue },
    .{ .a = v2(26, 386), .b = v2(26, 414), .kind = .key_yellow },
    .{ .a = v2(168, 150), .b = v2(200, 150), .kind = .mission, .r = 3, .h = 16 },
};

/// The gate across the lock's alcove, closed until the keys open it.
pub const gate: Wall = .{ .a = v2(296, 322), .b = v2(344, 350), .r = 3, .h = 26, .side = .grate };
pub const lock_c = v2(322, 296);
pub const lock_r: f32 = 12;

/// Where demons roam.
pub const Pit = struct { x0: f32, y0: f32, x1: f32, y1: f32 };
pub const pit: Pit = .{ .x0 = 104, .y0 = 336, .x1 = 264, .y1 = 452 };

pub const FlipperSpec = struct { pivot: V2, dir: f32 };
pub const flippers = [2]FlipperSpec{ .{ .pivot = v2(118, 712), .dir = 1 }, .{ .pivot = mirror(v2(118, 712)), .dir = -1 } };
pub const flipper_len: f32 = 56;
pub const flipper_r0: f32 = 9;
pub const flipper_r1: f32 = 5;
pub const flipper_h: f32 = 14;
pub const flipper_rest: f32 = 0.5;
pub const flipper_up: f32 = -0.5;
pub const flipper_speed: f32 = 24;

/// Where a served ball waits on the plunger.
pub const plunger_rest = v2(370, 780);
/// A ball right of this, below `lane_y`, sits in the plunger lane.
pub const lane_x: f32 = 356;
pub const lane_y: f32 = 700;
pub const launch_min: f32 = 700;
pub const launch_max: f32 = 1700;

test "the table is mirrored where it should be" {
    try std.testing.expectEqual(@as(f32, 250), flippers[1].pivot.x);
    try std.testing.expectEqual(field_right - (axis_x - field_left), axis_x);
}

test "the flippers' tips at rest leave a drain gap wider than the ball" {
    const tip_l = flippers[0].pivot.x + flipper_len * @cos(flipper_rest) + flipper_r1;
    const tip_r = flippers[1].pivot.x - flipper_len * @cos(flipper_rest) - flipper_r1;
    try std.testing.expect(tip_r - tip_l > 2 * ball_r);
}

test "the outlanes are wider than the ball" {
    try std.testing.expect(46 - 4 - field_left > 2 * ball_r);
}
