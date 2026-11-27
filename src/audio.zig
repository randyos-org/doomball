//! Sound effects, synthesized once at startup from notes (square, saw,
//! sine and noise, swept and decaying), and a mixer that plays them as
//! 16-bit mono PCM.
const std = @import("std");
const platform = @import("platform.zig");

const Allocator = std.mem.Allocator;

pub const rate = platform.audio_rate;

pub const Cue = enum {
    bumper,
    sling,
    flipper,
    knock,
    rollover,
    target,
    key,
    gate,
    lock,
    multiball,
    saved,
    demon_hurt,
    demon_slain,
    mission_start,
    promoted,
    mission_failed,
    drain,
    launch,
    game_over,
};

const cue_count = @typeInfo(Cue).@"enum".field_names.len;

const Wave = enum { square, saw, sine, noise };

const Note = struct {
    at: f32 = 0,
    dur: f32,
    wave: Wave,
    f0: f32 = 0,
    f1: f32 = 0,
    vol: f32 = 0.5,
    /// vibrato depth, a fraction of the pitch
    wobble: f32 = 0,
};

fn notes(c: Cue) []const Note {
    return switch (c) {
        .bumper => &.{ .{ .dur = 0.09, .wave = .square, .f0 = 240, .f1 = 110, .vol = 0.45 }, .{ .dur = 0.04, .wave = .noise, .vol = 0.3 } },
        .sling => &.{ .{ .dur = 0.05, .wave = .noise, .vol = 0.4 }, .{ .dur = 0.05, .wave = .square, .f0 = 520, .f1 = 300, .vol = 0.25 } },
        .flipper => &.{ .{ .dur = 0.06, .wave = .noise, .vol = 0.25 }, .{ .dur = 0.07, .wave = .sine, .f0 = 110, .f1 = 70, .vol = 0.5 } },
        .knock => &.{.{ .dur = 0.02, .wave = .noise, .vol = 0.18 }},
        .rollover => &.{.{ .dur = 0.06, .wave = .square, .f0 = 880, .f1 = 880, .vol = 0.25 }},
        .target => &.{ .{ .dur = 0.14, .wave = .square, .f0 = 660, .f1 = 660, .vol = 0.25 }, .{ .at = 0.05, .dur = 0.14, .wave = .square, .f0 = 990, .f1 = 990, .vol = 0.2 } },
        .key => &.{ .{ .dur = 0.08, .wave = .square, .f0 = 523, .f1 = 523, .vol = 0.3 }, .{ .at = 0.08, .dur = 0.08, .wave = .square, .f0 = 659, .f1 = 659, .vol = 0.3 }, .{ .at = 0.16, .dur = 0.16, .wave = .square, .f0 = 784, .f1 = 784, .vol = 0.3 } },
        .gate => &.{ .{ .dur = 0.5, .wave = .saw, .f0 = 320, .f1 = 70, .vol = 0.4 }, .{ .dur = 0.12, .wave = .noise, .vol = 0.3 } },
        .lock => &.{ .{ .dur = 0.1, .wave = .noise, .vol = 0.4 }, .{ .dur = 0.18, .wave = .sine, .f0 = 90, .f1 = 50, .vol = 0.6 } },
        .multiball => &.{
            .{ .dur = 0.15, .wave = .square, .f0 = 600, .f1 = 800, .vol = 0.3 },
            .{ .at = 0.15, .dur = 0.15, .wave = .square, .f0 = 800, .f1 = 600, .vol = 0.3 },
            .{ .at = 0.3, .dur = 0.15, .wave = .square, .f0 = 600, .f1 = 800, .vol = 0.3 },
            .{ .at = 0.45, .dur = 0.3, .wave = .square, .f0 = 800, .f1 = 1200, .vol = 0.3 },
        },
        .saved => &.{ .{ .dur = 0.1, .wave = .square, .f0 = 440, .f1 = 440, .vol = 0.3 }, .{ .at = 0.1, .dur = 0.16, .wave = .square, .f0 = 880, .f1 = 880, .vol = 0.3 } },
        .demon_hurt => &.{ .{ .dur = 0.28, .wave = .saw, .f0 = 120, .f1 = 90, .vol = 0.5, .wobble = 0.08 }, .{ .dur = 0.12, .wave = .noise, .vol = 0.2 } },
        .demon_slain => &.{ .{ .dur = 0.7, .wave = .saw, .f0 = 150, .f1 = 35, .vol = 0.55, .wobble = 0.1 }, .{ .dur = 0.35, .wave = .noise, .vol = 0.35 } },
        .mission_start => &.{ .{ .dur = 0.1, .wave = .square, .f0 = 440, .f1 = 440, .vol = 0.3 }, .{ .at = 0.14, .dur = 0.18, .wave = .square, .f0 = 660, .f1 = 660, .vol = 0.3 } },
        .promoted => &.{
            .{ .dur = 0.1, .wave = .square, .f0 = 392, .f1 = 392, .vol = 0.3 },
            .{ .at = 0.1, .dur = 0.1, .wave = .square, .f0 = 523, .f1 = 523, .vol = 0.3 },
            .{ .at = 0.2, .dur = 0.1, .wave = .square, .f0 = 659, .f1 = 659, .vol = 0.3 },
            .{ .at = 0.3, .dur = 0.4, .wave = .square, .f0 = 784, .f1 = 784, .vol = 0.3 },
        },
        .mission_failed => &.{
            .{ .dur = 0.16, .wave = .square, .f0 = 330, .f1 = 330, .vol = 0.3 },
            .{ .at = 0.16, .dur = 0.16, .wave = .square, .f0 = 247, .f1 = 247, .vol = 0.3 },
            .{ .at = 0.32, .dur = 0.35, .wave = .square, .f0 = 196, .f1 = 180, .vol = 0.3 },
        },
        .drain => &.{.{ .dur = 0.6, .wave = .square, .f0 = 400, .f1 = 90, .vol = 0.35 }},
        .launch => &.{ .{ .dur = 0.22, .wave = .noise, .vol = 0.3 }, .{ .dur = 0.2, .wave = .sine, .f0 = 180, .f1 = 600, .vol = 0.3 } },
        .game_over => &.{ .{ .dur = 0.4, .wave = .saw, .f0 = 220, .f1 = 220, .vol = 0.35 }, .{ .at = 0.4, .dur = 0.9, .wave = .saw, .f0 = 165, .f1 = 110, .vol = 0.35 } },
    };
}

/// Each cue's samples.
pub const Bank = struct {
    pcm: [cue_count][]i16,

    pub fn init(gpa: Allocator) !Bank {
        var b: Bank = .{ .pcm = @splat(&.{}) };
        errdefer b.deinit(gpa);
        var seed: u32 = 0x1234567;
        for (&b.pcm, 0..) |*pcm, ci| {
            const ns = notes(@fromBackingInt(@intCast(ci)));
            var end: f32 = 0;
            for (ns) |n| end = @max(end, n.at + n.dur);
            const len: usize = @intFromFloat(@ceil(end * rate));
            const acc = try gpa.alloc(f32, len);
            defer gpa.free(acc);
            @memset(acc, 0);
            for (ns) |n| render(acc, n, &seed);
            pcm.* = try gpa.alloc(i16, len);
            for (pcm.*, acc) |*o, v| o.* = @intFromFloat(std.math.clamp(v, -1, 1) * 30000);
        }
        return b;
    }

    pub fn deinit(b: *Bank, gpa: Allocator) void {
        for (&b.pcm) |*p| {
            gpa.free(p.*);
            p.* = &.{};
        }
    }
};

fn render(acc: []f32, n: Note, seed: *u32) void {
    const start: usize = @intFromFloat(n.at * rate);
    const len: usize = @intFromFloat(n.dur * rate);
    var phase: f32 = 0;
    for (0..len) |k| {
        const i = start + k;
        if (i >= acc.len) break;
        const t = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(len));
        var f = n.f0 + (n.f1 - n.f0) * t;
        f *= 1 + n.wobble * @sin(@as(f32, @floatFromInt(k)) * 2 * std.math.pi * 18 / rate);
        phase = @mod(phase + f / rate, 1);
        const s: f32 = switch (n.wave) {
            .square => if (phase < 0.5) 1 else -1,
            .saw => 2 * phase - 1,
            .sine => @sin(phase * 2 * std.math.pi),
            .noise => blk: {
                seed.* ^= seed.* << 13;
                seed.* ^= seed.* >> 17;
                seed.* ^= seed.* << 5;
                break :blk @as(f32, @floatFromInt(seed.* & 0xffff)) / 32768 - 1;
            },
        };
        // a quick attack and a decay to silence
        const attack = @min(1, @as(f32, @floatFromInt(k)) / (0.003 * rate));
        const env = attack * (1 - t) * (1 - t);
        acc[i] += s * env * n.vol;
    }
}

const max_voices = 12;

pub const Mixer = struct {
    bank: *const Bank,
    voices: [max_voices]?struct { cue: Cue, at: usize } = @splat(null),
    /// the fraction of a sample carried from one frame to the next
    carry: f32 = 0,

    pub fn play(m: *Mixer, c: Cue) void {
        // a free voice, else the one furthest along
        var pick: usize = 0;
        var furthest: usize = 0;
        for (m.voices, 0..) |v, i| {
            const at = if (v) |x| x.at else {
                pick = i;
                break;
            };
            if (at >= furthest) {
                furthest = at;
                pick = i;
            }
        }
        m.voices[pick] = .{ .cue = c, .at = 0 };
    }

    /// How many samples a frame of `dt` seconds needs.
    pub fn samplesFor(m: *Mixer, dt: f32) usize {
        const want = dt * rate + m.carry;
        const n = @floor(want);
        m.carry = want - n;
        return @intFromFloat(n);
    }

    pub fn mix(m: *Mixer, out: []i16) void {
        for (out, 0..) |*o, k| {
            var sum: i32 = 0;
            for (&m.voices) |*vo| {
                const v = &(vo.* orelse continue);
                const pcm = m.bank.pcm[@backingInt(v.cue)];
                if (v.at + k < pcm.len) sum += pcm[v.at + k];
            }
            o.* = @intCast(std.math.clamp(sum, std.math.minInt(i16), std.math.maxInt(i16)));
        }
        for (&m.voices) |*vo| {
            const v = &(vo.* orelse continue);
            v.at += out.len;
            if (v.at >= m.bank.pcm[@backingInt(v.cue)].len) vo.* = null;
        }
    }
};

test "every cue has sound, and the mixer plays and finishes it" {
    var bank = try Bank.init(std.testing.allocator);
    defer bank.deinit(std.testing.allocator);
    for (bank.pcm) |p| try std.testing.expect(p.len > 100);
    var m = Mixer{ .bank = &bank };
    var out: [512]i16 = undefined;
    m.mix(&out);
    try std.testing.expect(std.mem.allEqual(i16, &out, 0));
    m.play(.bumper);
    m.mix(&out);
    try std.testing.expect(!std.mem.allEqual(i16, &out, 0));
    for (0..20) |_| m.mix(&out);
    try std.testing.expect(m.voices[0] == null);
}

test "frames get samples at the rate, with the remainder carried" {
    var bank = Bank{ .pcm = @splat(&.{}) };
    var m = Mixer{ .bank = &bank };
    var total: usize = 0;
    for (0..60) |_| total += m.samplesFor(1.0 / 60.0);
    try std.testing.expect(total >= rate - 1 and total <= rate);
}
