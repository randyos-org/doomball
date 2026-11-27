const std = @import("std");

pub const Canvas = struct {
    pixels: []u32,
    w: i32,
    h: i32,

    pub fn put(self: Canvas, x: i32, y: i32, c: u32) void {
        if (x < 0 or y < 0 or x >= self.w or y >= self.h) return;
        self.pixels[@intCast(y * self.w + x)] = c;
    }

    pub fn rect(self: Canvas, x: i32, y: i32, w: i32, h: i32, c: u32) void {
        var j = y;
        while (j < y + h) : (j += 1) {
            var i = x;
            while (i < x + w) : (i += 1) self.put(i, j, c);
        }
    }

    pub fn disc(self: Canvas, cx: f32, cy: f32, r: f32, c: u32) void {
        const x0: i32 = @intFromFloat(@floor(cx - r));
        const x1: i32 = @intFromFloat(@ceil(cx + r));
        const y0: i32 = @intFromFloat(@floor(cy - r));
        const y1: i32 = @intFromFloat(@ceil(cy + r));
        var y = y0;
        while (y <= y1) : (y += 1) {
            var x = x0;
            while (x <= x1) : (x += 1) {
                const dx = @as(f32, @floatFromInt(x)) + 0.5 - cx;
                const dy = @as(f32, @floatFromInt(y)) + 0.5 - cy;
                if (dx * dx + dy * dy <= r * r) self.put(x, y, c);
            }
        }
    }

    /// Thick line made of stamped discs.
    pub fn line(self: Canvas, x0: f32, y0: f32, x1: f32, y1: f32, r: f32, c: u32) void {
        const dx = x1 - x0;
        const dy = y1 - y0;
        const len = @sqrt(dx * dx + dy * dy);
        const steps: usize = @max(1, @as(usize, @intFromFloat(len / 0.75)));
        var i: usize = 0;
        while (i <= steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            self.disc(x0 + dx * t, y0 + dy * t, r, c);
        }
    }

    pub fn text(self: Canvas, s: []const u8, x: i32, y: i32, scale: i32, c: u32) void {
        var cx = x;
        for (s) |ch| {
            if (glyph(ch)) |g| {
                for (0..5) |row| {
                    for (0..3) |col| {
                        if (g[row * 3 + col] == '1') {
                            self.rect(cx + @as(i32, @intCast(col)) * scale, y + @as(i32, @intCast(row)) * scale, scale, scale, c);
                        }
                    }
                }
            }
            cx += 4 * scale;
        }
    }

    pub fn textWidth(s: []const u8, scale: i32) i32 {
        return @as(i32, @intCast(s.len)) * 4 * scale - scale;
    }
};

const digits = [10]*const [15]u8{
    "111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
    "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
};
const letters = [26]*const [15]u8{
    "010101111101101", "110101110101110", "011100100100011", "110101101101110", "111100110100111",
    "111100110100100", "011100101101011", "101101111101101", "111010010010111", "001001001101010",
    "101101110101101", "100100100100111", "101111111101101", "110101101101101", "010101101101010",
    "110101110100100", "010101101111011", "110101110101101", "011100010001110", "111010010010010",
    "101101101101111", "101101101101010", "101101111111101", "101101010101101", "101101010010010",
    "111001010100111",
};

pub fn glyph(ch: u8) ?*const [15]u8 {
    return switch (ch) {
        '0'...'9' => digits[ch - '0'],
        'A'...'Z' => letters[ch - 'A'],
        'a'...'z' => letters[ch - 'a'],
        else => null,
    };
}

test "canvas clips and draws" {
    var buf: [16]u32 = @splat(0);
    const c = Canvas{ .pixels = &buf, .w = 4, .h = 4 };
    c.put(-1, 0, 1);
    c.put(4, 0, 1);
    c.put(1, 1, 7);
    try std.testing.expectEqual(@as(u32, 7), buf[5]);
    c.rect(0, 0, 2, 2, 3);
    try std.testing.expectEqual(@as(u32, 3), buf[0]);
}
