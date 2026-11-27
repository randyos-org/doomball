//! The fixed camera above the table's near end: table coordinates to view
//! pixels and back. Depth is the distance along the view direction.
const std = @import("std");
const vec = @import("vec.zig");
const layout = @import("layout.zig");
const table = @import("table.zig");

const V3 = vec.V3;
const v3 = vec.v3;

pub const eye = v3(table.width / 2, 2150, 1650);
const target = v3(table.width / 2, 400, 0);
/// margin around the table, in pixels
const margin: f32 = 4;

pub const Camera = struct {
    fwd: V3,
    right: V3,
    up: V3,
    /// focal length in pixels, and the view pixel the axis goes through
    f: f32,
    cx: f32,
    cy: f32,

    /// The camera fitted so the whole table fills the view.
    pub fn init() Camera {
        const fwd = target.sub(eye).norm();
        const right = v3(0, 0, 1).cross(fwd).norm();
        var c = Camera{ .fwd = fwd, .right = right, .up = fwd.cross(right), .f = 1, .cx = 0, .cy = 0 };
        var x0: f32 = 1e9;
        var x1: f32 = -1e9;
        var y0: f32 = 1e9;
        var y1: f32 = -1e9;
        for ([_]f32{ 0, table.width }) |x| for ([_]f32{ 0, table.drain_y - 10 }) |y| for ([_]f32{ 0, 40 }) |z| {
            const p = c.project(v3(x, y, z));
            x0 = @min(x0, p.x);
            x1 = @max(x1, p.x);
            y0 = @min(y0, p.y);
            y1 = @max(y1, p.y);
        };
        const w: f32 = @floatFromInt(layout.view.w);
        const h: f32 = @floatFromInt(layout.view.h);
        c.f = @min((w - 2 * margin) / (x1 - x0), (h - 2 * margin) / (y1 - y0));
        c.cx = w / 2 - c.f * (x0 + x1) / 2;
        c.cy = h / 2 - c.f * (y0 + y1) / 2;
        return c;
    }

    /// The view pixel (x, y) of a table point, and its depth.
    pub fn project(c: Camera, p: V3) V3 {
        const d = p.sub(eye);
        const z = d.dot(c.fwd);
        return v3(c.cx + c.f * d.dot(c.right) / z, c.cy - c.f * d.dot(c.up) / z, z);
    }

    /// The ray through view pixel (x, y), scaled so that a point at
    /// parameter t along it is at depth t.
    pub fn ray(c: Camera, x: f32, y: f32) V3 {
        return c.fwd.add(c.right.mul((x - c.cx) / c.f)).add(c.up.mul((c.cy - y) / c.f));
    }
};

test "a point projects back onto its own ray at its depth" {
    const c = Camera.init();
    const p = v3(120, 500, 10);
    const s = c.project(p);
    const back = eye.add(c.ray(s.x, s.y).mul(s.z));
    try std.testing.expectApproxEqAbs(p.x, back.x, 0.01);
    try std.testing.expectApproxEqAbs(p.y, back.y, 0.01);
    try std.testing.expectApproxEqAbs(p.z, back.z, 0.01);
}

test "the table fits in the view, its near end lower and wider" {
    const c = Camera.init();
    const near_l = c.project(v3(0, 800, 0));
    const near_r = c.project(v3(table.width, 800, 0));
    const far_l = c.project(v3(0, 0, 0));
    const far_r = c.project(v3(table.width, 0, 0));
    try std.testing.expect(near_l.y > far_l.y);
    try std.testing.expect(near_r.x - near_l.x > far_r.x - far_l.x);
    try std.testing.expect(near_l.x >= 0 and near_r.x <= layout.view.w and far_l.y >= 0);
}
