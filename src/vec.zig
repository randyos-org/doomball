//! 2-D and 3-D vectors of f32.
const std = @import("std");

pub const V2 = struct {
    x: f32,
    y: f32,

    pub fn add(a: V2, b: V2) V2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: V2, b: V2) V2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn mul(a: V2, s: f32) V2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    pub fn dot(a: V2, b: V2) f32 {
        return a.x * b.x + a.y * b.y;
    }
    pub fn cross(a: V2, b: V2) f32 {
        return a.x * b.y - a.y * b.x;
    }
    pub fn len(a: V2) f32 {
        return @sqrt(a.dot(a));
    }
    /// `a` scaled to length 1, or `a` itself when it has none.
    pub fn norm(a: V2) V2 {
        const l = a.len();
        return if (l > 1e-9) a.mul(1 / l) else a;
    }
    /// Turned a quarter to the left (x right, y down: counterclockwise on screen).
    pub fn perp(a: V2) V2 {
        return .{ .x = a.y, .y = -a.x };
    }
    pub fn mix(a: V2, b: V2, t: f32) V2 {
        return a.add(b.sub(a).mul(t));
    }
};

pub fn v2(x: f32, y: f32) V2 {
    return .{ .x = x, .y = y };
}

pub const V3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(a: V3, b: V3) V3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: V3, b: V3) V3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn mul(a: V3, s: f32) V3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub fn dot(a: V3, b: V3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub fn cross(a: V3, b: V3) V3 {
        return .{ .x = a.y * b.z - a.z * b.y, .y = a.z * b.x - a.x * b.z, .z = a.x * b.y - a.y * b.x };
    }
    pub fn len(a: V3) f32 {
        return @sqrt(a.dot(a));
    }
    pub fn norm(a: V3) V3 {
        const l = a.len();
        return if (l > 1e-9) a.mul(1 / l) else a;
    }
};

pub fn v3(x: f32, y: f32, z: f32) V3 {
    return .{ .x = x, .y = y, .z = z };
}

/// The point of segment a-b nearest `p`, as its parameter 0..1.
pub fn nearestOnSegment(p: V2, a: V2, b: V2) f32 {
    const ab = b.sub(a);
    const l2 = ab.dot(ab);
    if (l2 < 1e-12) return 0;
    return std.math.clamp(p.sub(a).dot(ab) / l2, 0, 1);
}

test "vectors" {
    try std.testing.expectEqual(@as(f32, 5), v2(3, 4).len());
    try std.testing.expectEqual(@as(f32, 0.5), nearestOnSegment(v2(5, 3), v2(0, 0), v2(10, 0)));
    try std.testing.expectEqual(@as(f32, 1), nearestOnSegment(v2(15, 3), v2(0, 0), v2(10, 0)));
    const z = v3(1, 0, 0).cross(v3(0, 1, 0));
    try std.testing.expectEqual(@as(f32, 1), z.z);
    try std.testing.expectEqual(@as(f32, 0), v2(1, 0).perp().dot(v2(1, 0)));
}
