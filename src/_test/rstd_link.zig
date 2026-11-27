//! rstd builds and links here (#28): rgl's software surface fills a rect.
//! The game does not use rstd yet; real-time 3-D in rgl is rstd#817.
const std = @import("std");
const rstd = @import("rstd");

const rgl = rstd.rgl;

test "rgl's software surface draws a rect" {
    var s = try rgl.sw.SwSurface.init(std.testing.allocator, 4, 4, .{ .fill = rgl.color.RGBA.blank });
    defer s.deinit(std.testing.allocator);
    const red: rgl.color.RGBA = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    rgl.sw.fillRect(&s, .{ .x = 1, .y = 1, .w = 2, .h = 2 }, red);
    try std.testing.expect(s.target.getPixel(1, 1).equals(red));
    try std.testing.expect(s.target.getPixel(0, 0).equals(rgl.color.RGBA.blank));
}
