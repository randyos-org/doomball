//! Our 5x7 bitmap font: capitals (lowercase draws as capitals), digits and
//! some punctuation; each glyph sits in a 6x8 cell.
const std = @import("std");

pub const glyph_w = 5;
pub const glyph_h = 7;
pub const advance = glyph_w + 1;

const sources = [_]struct { u8, *const [35]u8 }{
    .{ 'A', ".###.#...##...#######...##...##...#" },
    .{ 'B', "####.#...##...#####.#...##...#####." },
    .{ 'C', ".###.#...##....#....#....#...#.###." },
    .{ 'D', "####.#...##...##...##...##...#####." },
    .{ 'E', "######....#....####.#....#....#####" },
    .{ 'F', "######....#....####.#....#....#...." },
    .{ 'G', ".###.#...##....#.####...##...#.####" },
    .{ 'H', "#...##...##...#######...##...##...#" },
    .{ 'I', ".###...#....#....#....#....#...###." },
    .{ 'J', "..###...#....#....#....#.#..#..##.." },
    .{ 'K', "#...##..#.#.#..##...#.#..#..#.#...#" },
    .{ 'L', "#....#....#....#....#....#....#####" },
    .{ 'M', "#...###.###.#.##.#.##...##...##...#" },
    .{ 'N', "#...##...###..##.#.##..###...##...#" },
    .{ 'O', ".###.#...##...##...##...##...#.###." },
    .{ 'P', "####.#...##...#####.#....#....#...." },
    .{ 'Q', ".###.#...##...##...##.#.##..#..##.#" },
    .{ 'R', "####.#...##...#####.#.#..#..#.#...#" },
    .{ 'S', ".#####....#.....###.....#....#####." },
    .{ 'T', "#####..#....#....#....#....#....#.." },
    .{ 'U', "#...##...##...##...##...##...#.###." },
    .{ 'V', "#...##...##...##...##...#.#.#...#.." },
    .{ 'W', "#...##...##...##.#.##.#.##.#.#.#.#." },
    .{ 'X', "#...##...#.#.#...#...#.#.#...##...#" },
    .{ 'Y', "#...##...#.#.#...#....#....#....#.." },
    .{ 'Z', "#####....#...#...#...#...#....#####" },
    .{ '0', ".###.#...##..###.#.###..##...#.###." },
    .{ '1', "..#...##....#....#....#....#...###." },
    .{ '2', ".###.#...#....#...#...#...#...#####" },
    .{ '3', "#####...#...#.....#.....##...#.###." },
    .{ '4', "...#...##..#.#.#..#.#####...#....#." },
    .{ '5', "######....####.....#....##...#.###." },
    .{ '6', "..##..#...#....####.#...##...#.###." },
    .{ '7', "#####....#...#...#...#....#....#..." },
    .{ '8', ".###.#...##...#.###.#...##...#.###." },
    .{ '9', ".###.#...##...#.####....#...#..##.." },
    .{ ' ', "..................................." },
    .{ '.', "..........................##...##.." },
    .{ ',', ".....................##....#...#..." },
    .{ ':', "......##...##........##...##......." },
    .{ '!', "..#....#....#....#....#.........#.." },
    .{ '?', ".###.#...#....#...#...#.........#.." },
    .{ '-', "...............#####..............." },
    .{ '\'', "..#....#...#......................." },
    .{ '/', "....#....#...#...#...#...#....#...." },
    .{ '+', ".......#....#..#####..#....#......." },
    .{ '%', "##..###..#...#...#...#...#..###..##" },
    .{ '(', "...#...#...#....#....#.....#.....#." },
    .{ ')', ".#.....#.....#....#....#...#...#..." },
    .{ '*', ".....#.#.#.###.#####.###.#.#.#....." },
};

/// Each glyph as 7 rows of 5 bits, the leftmost column the highest bit.
const table = blk: {
    @setEvalBranchQuota(20000);
    var t: [128]?[glyph_h]u8 = @splat(null);
    for (sources) |src| {
        var rows: [glyph_h]u8 = undefined;
        for (0..glyph_h) |r| {
            var bits: u8 = 0;
            for (0..glyph_w) |c| bits = (bits << 1) | @intFromBool(src[1][r * glyph_w + c] == '#');
            rows[r] = bits;
        }
        t[src[0]] = rows;
    }
    break :blk t;
};

pub fn glyph(ch: u8) ?[glyph_h]u8 {
    const c = std.ascii.toUpper(ch);
    return if (c < 128) table[c] else null;
}

/// Whether column `col`, row `row` of the glyph of `ch` is set.
pub fn bit(ch: u8, col: usize, row: usize) bool {
    if (col >= glyph_w or row >= glyph_h) return false;
    const g = glyph(ch) orelse return false;
    return (g[row] >> @intCast(glyph_w - 1 - col)) & 1 == 1;
}

pub fn width(text: []const u8, scale: usize) usize {
    if (text.len == 0) return 0;
    return (text.len * advance - 1) * scale;
}

/// Draws `text` into a frame `stride` pixels wide, its top left at (x, y).
pub fn draw(pixels: []u32, stride: usize, x: usize, y: usize, text: []const u8, scale: usize, color: u32) void {
    const rows = pixels.len / stride;
    for (text, 0..) |ch, k| {
        const gx = x + k * advance * scale;
        for (0..glyph_h * scale) |py| for (0..glyph_w * scale) |px| {
            if (!bit(ch, px / scale, py / scale)) continue;
            const fx = gx + px;
            const fy = y + py;
            if (fx < stride and fy < rows) pixels[fy * stride + fx] = color;
        };
    }
}

test "every glyph has its 35 cells and the font draws" {
    for (sources) |s| try std.testing.expectEqual(@as(usize, 35), s[1].len);
    try std.testing.expect(bit('A', 2, 0));
    try std.testing.expect(!bit('A', 0, 0));
    try std.testing.expect(bit('a', 2, 0));
    try std.testing.expect(glyph('~') == null);
    var px: [20 * 10]u32 = @splat(0);
    draw(&px, 20, 0, 0, "HI", 1, 7);
    try std.testing.expectEqual(@as(u32, 7), px[0]);
    try std.testing.expectEqual(@as(usize, 11), width("HI", 1));
}
