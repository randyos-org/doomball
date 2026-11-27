//! Where things are on the 640x480 frame: the table view on the left, the
//! status panel on the right.
const std = @import("std");
const platform = @import("platform.zig");

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn contains(r: Rect, x: i32, y: i32) bool {
        return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h;
    }
};

pub const panel_w = 220;

pub const view: Rect = .{ .x = 0, .y = 0, .w = platform.width - panel_w, .h = platform.height };
pub const panel: Rect = .{ .x = platform.width - panel_w, .y = 0, .w = panel_w, .h = platform.height };

test "the view and the panel tile the frame" {
    try std.testing.expectEqual(@as(i32, platform.width), view.w + panel.w);
    try std.testing.expect(view.contains(view.w - 1, 0));
    try std.testing.expect(!view.contains(view.w, 0));
    try std.testing.expect(panel.contains(view.w, platform.height - 1));
}
