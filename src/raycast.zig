//! Ray intersections with the table's solids: 2-D convex shapes on the
//! playfield extruded from one height to another, and spheres.
const std = @import("std");
const vec = @import("vec.zig");

const V2 = vec.V2;
const V3 = vec.V3;
const v2 = vec.v2;
const v3 = vec.v3;

pub const Hit = struct {
    t: f32,
    n: V3,
    /// on the top face rather than the side
    top: bool,
};

/// The part of a 2-D ray (o + t u) inside a convex shape, and the outward
/// normal where it enters.
const Span = struct { t0: f32, t1: f32, n: V2 };

fn circleSpan(o: V2, u: V2, c: V2, r: f32) ?Span {
    const oc = o.sub(c);
    const a = u.dot(u);
    if (a < 1e-12) return if (oc.dot(oc) <= r * r) Span{ .t0 = -1e30, .t1 = 1e30, .n = v2(0, 0) } else null;
    const b = oc.dot(u);
    const disc = b * b - a * (oc.dot(oc) - r * r);
    if (disc < 0) return null;
    const s = @sqrt(disc);
    const t0 = (-b - s) / a;
    return .{ .t0 = t0, .t1 = (-b + s) / a, .n = oc.add(u.mul(t0)).mul(1 / r) };
}

/// A convex polygon, its corners in either winding.
fn polygonSpan(o: V2, u: V2, pts: []const V2) ?Span {
    var area: f32 = 0;
    for (pts, 0..) |p, i| area += p.cross(pts[(i + 1) % pts.len]);
    const sign: f32 = if (area > 0) 1 else -1;
    var t0: f32 = -1e30;
    var t1: f32 = 1e30;
    var n0 = v2(0, 0);
    for (pts, 0..) |p, i| {
        const q = pts[(i + 1) % pts.len];
        // outward normal of edge p-q
        const out = v2(q.y - p.y, p.x - q.x).mul(sign).norm();
        const num = o.sub(p).dot(out);
        const den = u.dot(out);
        if (@abs(den) < 1e-12) {
            if (num > 0) return null;
            continue;
        }
        const t = -num / den;
        if (den < 0) {
            if (t > t0) {
                t0 = t;
                n0 = out;
            }
        } else t1 = @min(t1, t);
        if (t0 > t1) return null;
    }
    return .{ .t0 = t0, .t1 = t1, .n = n0 };
}

/// The union of convex spans that overlap (pieces of one convex shape).
fn join(spans: []const ?Span) ?Span {
    var out: ?Span = null;
    for (spans) |sp| {
        const s = sp orelse continue;
        if (out) |*o| {
            if (s.t0 < o.t0) {
                o.t0 = s.t0;
                o.n = s.n;
            }
            o.t1 = @max(o.t1, s.t1);
        } else out = s;
    }
    return out;
}

/// The 2-D span lifted to the solid from height h0 to h1: its side where
/// the ray enters it within those heights, else its top face.
fn lift(o: V3, d: V3, span: ?Span, h0: f32, h1: f32) ?Hit {
    const s = span orelse return null;
    if (s.t1 <= 0) return null;
    const z0 = o.z + d.z * s.t0;
    if (z0 >= h0 and z0 <= h1 and s.t0 > 0) return .{ .t = s.t0, .n = v3(s.n.x, s.n.y, 0), .top = false };
    if (z0 > h1 and d.z < 0) {
        const tt = (h1 - o.z) / d.z;
        if (tt >= s.t0 and tt <= s.t1 and tt > 0) return .{ .t = tt, .n = v3(0, 0, 1), .top = true };
    }
    return null;
}

fn flat(p: V3) V2 {
    return v2(p.x, p.y);
}

/// A wall: segment a-b with half thickness r, from h0 up to h1.
pub fn capsule(o: V3, d: V3, a: V2, b: V2, r: f32, h0: f32, h1: f32) ?Hit {
    return tapered(o, d, a, r, b, r, h0, h1);
}

pub fn cylinder(o: V3, d: V3, c: V2, r: f32, h0: f32, h1: f32) ?Hit {
    return lift(o, d, circleSpan(flat(o), flat(d), c, r), h0, h1);
}

/// The convex hull of a circle at a (radius ra) and one at b (radius rb).
pub fn tapered(o: V3, d: V3, a: V2, ra: f32, b: V2, rb: f32, h0: f32, h1: f32) ?Hit {
    const o2 = flat(o);
    const u = flat(d);
    const ab = b.sub(a);
    const l = ab.len();
    if (l < 1e-6) return cylinder(o, d, a, @max(ra, rb), h0, h1);
    const e = ab.mul(1 / l);
    const m = e.perp();
    const sin_phi = (ra - rb) / l;
    const cos_phi = @sqrt(@max(0, 1 - sin_phi * sin_phi));
    const np = e.mul(sin_phi).add(m.mul(cos_phi));
    const nm = e.mul(sin_phi).sub(m.mul(cos_phi));
    const quad = [4]V2{ a.add(np.mul(ra)), b.add(np.mul(rb)), b.add(nm.mul(rb)), a.add(nm.mul(ra)) };
    const spans = [3]?Span{ circleSpan(o2, u, a, ra), circleSpan(o2, u, b, rb), polygonSpan(o2, u, &quad) };
    return lift(o, d, join(&spans), h0, h1);
}

/// A convex polygon (a slingshot), from h0 up to h1.
pub fn prism(o: V3, d: V3, pts: []const V2, h0: f32, h1: f32) ?Hit {
    return lift(o, d, polygonSpan(flat(o), flat(d), pts), h0, h1);
}

pub fn sphere(o: V3, d: V3, c: V3, r: f32) ?Hit {
    const oc = o.sub(c);
    const a = d.dot(d);
    const b = oc.dot(d);
    const disc = b * b - a * (oc.dot(oc) - r * r);
    if (disc < 0) return null;
    const t = (-b - @sqrt(disc)) / a;
    if (t <= 0) return null;
    return .{ .t = t, .n = oc.add(d.mul(t)).mul(1 / r), .top = false };
}

/// Where the ray meets the playfield plane z = 0.
pub fn floor(o: V3, d: V3) ?f32 {
    if (d.z >= 0) return null;
    return -o.z / d.z;
}

const down = v3(0, 0, -1);

test "a ray straight down hits a wall's top, one from the side its side" {
    const top = capsule(v3(5, 0, 100), down, v2(0, 0), v2(10, 0), 2, 0, 20).?;
    try std.testing.expect(top.top);
    try std.testing.expectApproxEqAbs(@as(f32, 80), top.t, 1e-3);
    const side = capsule(v3(5, -50, 10), v3(0, 1, 0), v2(0, 0), v2(10, 0), 2, 0, 20).?;
    try std.testing.expect(!side.top);
    try std.testing.expectApproxEqAbs(@as(f32, 48), side.t, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -1), side.n.y, 1e-3);
}

test "a ray over a wall misses it, and one under its base does too" {
    try std.testing.expect(capsule(v3(5, -50, 30), v3(0, 1, 0), v2(0, 0), v2(10, 0), 2, 0, 20) == null);
    try std.testing.expect(cylinder(v3(0, -50, 2), v3(0, 1, 0), v2(0, 0), 5, 10, 20) == null);
}

test "a tapered shape is wider at its big end" {
    const big = tapered(v3(0, -50, 5), v3(0, 1, 0), v2(0, 0), 8, v2(40, 0), 3, 0, 10).?;
    try std.testing.expectApproxEqAbs(@as(f32, 42), big.t, 1e-3);
    const small = tapered(v3(40, -50, 5), v3(0, 1, 0), v2(0, 0), 8, v2(40, 0), 3, 0, 10).?;
    try std.testing.expectApproxEqAbs(@as(f32, 47), small.t, 0.1);
    try std.testing.expect(tapered(v3(40, -50, 5), v3(1, 0, 0), v2(0, 0), 8, v2(40, 0), 3, 0, 10) == null);
}

test "a sphere and the floor" {
    const s = sphere(v3(0, 0, 50), down, v3(0, 0, 8), 8).?;
    try std.testing.expectApproxEqAbs(@as(f32, 34), s.t, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 1), s.n.z, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 50), floor(v3(0, 0, 50), down).?, 1e-3);
    try std.testing.expect(floor(v3(0, 0, 50), v3(0, 0, 1)) == null);
}

test "a triangular prism" {
    const tri = [_]V2{ v2(0, 0), v2(10, 0), v2(0, 10) };
    try std.testing.expect(prism(v3(2, 2, 50), down, &tri, 0, 5).?.top);
    try std.testing.expect(prism(v3(9, 9, 50), down, &tri, 0, 5) == null);
}
