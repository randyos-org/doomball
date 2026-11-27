//! The demons' pixel art, our own: rows of characters, each a palette color
//! ('.' is clear). Two walk frames each, facing the player.
const std = @import("std");
const pal = @import("palette.zig");

pub const Sprite = struct {
    rows: []const []const u8,

    pub fn width(s: Sprite) usize {
        return s.rows[0].len;
    }

    pub fn height(s: Sprite) usize {
        return s.rows.len;
    }

    /// The palette index at (x, y), whether it shines by itself, or null
    /// where the sprite is clear.
    pub fn at(s: Sprite, x: usize, y: usize) ?Texel {
        return texelOf(s.rows[y][x]);
    }
};

pub const Texel = struct { i: u8, glow: bool = false };

fn texelOf(ch: u8) ?Texel {
    return switch (ch) {
        'k' => .{ .i = pal.index(.crimson, 1) },
        'r' => .{ .i = pal.index(.blood, 6) },
        'R' => .{ .i = pal.index(.blood, 9) },
        'd' => .{ .i = pal.index(.blood, 3) },
        'h', 'B' => .{ .i = pal.index(.bone, 11) },
        'H', 'b' => .{ .i = pal.index(.bone, 7) },
        'c' => .{ .i = pal.index(.bone, 12) },
        't' => .{ .i = pal.index(.bone, 14) },
        'm' => .{ .i = pal.index(.gray, 0) },
        'y' => .{ .i = pal.index(.yellow, 15), .glow = true },
        'Y' => .{ .i = pal.index(.toxic, 15), .glow = true },
        else => null,
    };
}

// pixel rows, not words
// cspell:disable
const brute_body = [_][]const u8{
    "..h..............h..",
    ".hH..............Hh.",
    ".hH..............Hh.",
    ".hHk...kkkkkk...kHh.",
    "..hHkkkrrrrrrkkkHh..",
    "...kkrRRRRRRRRrkk...",
    "...krRkyRRRRykRrk...",
    "...krRyyRRRRyyRrk...",
    "...krrRRRddRRRrrk...",
    "...kdrmtmtmtmtrdk...",
    "....kdmmmmmmmmdk....",
    "..kkkkdttttttdkkkk..",
    ".krrrkkddddddkkrrrk.",
    "krRRrrkrRRRRrkrrRRrk",
    "krRrrkrRRRRRRrkrrRrk",
    "krrrkrrRRRRRRrrkrrrk",
    "kcckkrrrRRRRrrrkkcck",
    "kcck.krrrrrrrrk.kcck",
    ".cc..kdrrrrrrdk..cc.",
    ".....kddrrrrddk.....",
};

pub const brute = [2]Sprite{
    .{ .rows = &(brute_body ++ [_][]const u8{
        "....kdrrk..krrdk....",
        "....krrk....krrk....",
        "...kdrrk....krrdk...",
        "...krrk......krrk...",
        "..kddk........kddk..",
        "..kkkk........kkkk..",
    }) },
    .{ .rows = &(brute_body ++ [_][]const u8{
        "....kdrrk..krrdk....",
        "....krrk...krrk.....",
        "....krrdk..kdrrk....",
        ".....kdrrkkrrdk.....",
        "....kddk....kddk....",
        "....kkkk....kkkk....",
    }) },
};

const crawler_body = [_][]const u8{
    "......kkkkkkkkkk......",
    "....kkbBBBBBBBBbkk....",
    "...kbBBBBBBBBBBBBbk...",
    "h..kbBkkBBBBBBkkBbk..h",
    ".h.kbBkYBBBBBBYkBbk.h.",
    "..hkbBBBBBkkBBBBBbkh..",
    "...hkbBBBBBBBBBBbkh...",
    "..h.kkbtmtmtmtmbkk.h..",
};

pub const crawler = [2]Sprite{
    .{ .rows = &(crawler_body ++ [_][]const u8{
        ".h..h.kkkkkkkkkk.h..h.",
        "h..h..............h..h",
        "..h................h..",
        ".h..................h.",
    }) },
    .{ .rows = &(crawler_body ++ [_][]const u8{
        "..h.h.kkkkkkkkkk.h.h..",
        ".h...h..........h...h.",
        "h.....h........h.....h",
        "......h........h......",
    }) },
};

// cspell:enable

test "every sprite is a rectangle of known colors" {
    for ([_][2]Sprite{ brute, crawler }) |frames| for (frames) |s| {
        for (s.rows) |row| {
            try std.testing.expectEqual(s.width(), row.len);
            for (row) |ch| try std.testing.expect(ch == '.' or texelOf(ch) != null);
        }
        try std.testing.expectEqual(frames[0].height(), s.height());
    };
    try std.testing.expect(brute[0].at(0, 0) == null);
    try std.testing.expect(brute[0].at(7, 6).?.glow);
}
