//! Missions and ranks: the mission target starts the next mission, each with
//! a goal and a time limit; finishing one raises the rank.
const std = @import("std");

pub const ranks = [_][]const u8{ "PRIVATE", "CORPORAL", "SERGEANT", "LIEUTENANT", "CAPTAIN", "MAJOR", "COLONEL", "GENERAL" };

pub const Kind = enum { barrage, lanes, purge, keys, hold };

pub const Spec = struct {
    kind: Kind,
    name: []const u8,
    /// what the goal counts, for the panel
    unit: []const u8,
    goal: u16,
    /// more for each rank above private
    goal_per_rank: u16 = 0,
    seconds: f32,
};

pub const specs = [_]Spec{
    .{ .kind = .barrage, .name = "BUMPER BARRAGE", .unit = "BUMPER HITS", .goal = 12, .goal_per_rank = 3, .seconds = 45 },
    .{ .kind = .lanes, .name = "RUN THE LANES", .unit = "LANE SETS", .goal = 1, .goal_per_rank = 1, .seconds = 60 },
    .{ .kind = .purge, .name = "PURGE THE PIT", .unit = "DEMONS SLAIN", .goal = 2, .goal_per_rank = 1, .seconds = 60 },
    .{ .kind = .keys, .name = "FIND THE KEYS", .unit = "KEYS FOUND", .goal = 3, .seconds = 75 },
    // its goal is the time to survive
    .{ .kind = .hold, .name = "HOLD THE LINE", .unit = "SECONDS", .goal = 25, .goal_per_rank = 5, .seconds = 0 },
};

pub fn bonus(rank: u8) u32 {
    return 5000 * (@as(u32, rank) + 1);
}

pub const Active = struct {
    spec: u8,
    goal: u16,
    progress: u16 = 0,
    /// seconds left; for `hold`, seconds survived so far
    clock: f32,

    pub fn kind(a: Active) Kind {
        return specs[a.spec].kind;
    }
};

pub const Outcome = enum { none, done, failed };

pub const Missions = struct {
    active: ?Active = null,
    next: u8 = 0,
    rank: u8 = 0,

    /// Starts the next mission, if none is under way; its spec, or null.
    pub fn start(m: *Missions) ?Spec {
        if (m.active != null) return null;
        const s = specs[m.next];
        m.active = .{ .spec = m.next, .goal = s.goal + s.goal_per_rank * m.rank, .clock = if (s.kind == .hold) 0 else s.seconds };
        m.next = @intCast((m.next + 1) % specs.len);
        return s;
    }

    /// Counts `n` toward the active mission, if it is of `kind`.
    pub fn count(m: *Missions, kind: Kind, n: u16) Outcome {
        const a = &(m.active orelse return .none);
        if (a.kind() != kind) return .none;
        a.progress = @min(a.goal, a.progress + n);
        return if (a.progress >= a.goal) m.finish() else .none;
    }

    pub fn tick(m: *Missions, dt: f32) Outcome {
        const a = &(m.active orelse return .none);
        if (a.kind() == .hold) {
            a.clock += dt;
            a.progress = @intFromFloat(@min(@as(f32, @floatFromInt(a.goal)), @floor(a.clock)));
            return if (a.progress >= a.goal) m.finish() else .none;
        }
        a.clock -= dt;
        if (a.clock > 0) return .none;
        m.active = null;
        return .failed;
    }

    /// A ball drained: fatal to holding the line.
    pub fn drained(m: *Missions) Outcome {
        const a = m.active orelse return .none;
        if (a.kind() != .hold) return .none;
        m.active = null;
        return .failed;
    }

    fn finish(m: *Missions) Outcome {
        m.active = null;
        m.rank = @min(m.rank + 1, ranks.len - 1);
        return .done;
    }
};

test "a mission counts only its own kind and finishing it ranks up" {
    var m = Missions{};
    try std.testing.expectEqual(Kind.barrage, m.start().?.kind);
    try std.testing.expect(m.start() == null);
    try std.testing.expectEqual(Outcome.none, m.count(.lanes, 5));
    for (0..11) |_| try std.testing.expectEqual(Outcome.none, m.count(.barrage, 1));
    try std.testing.expectEqual(Outcome.done, m.count(.barrage, 1));
    try std.testing.expectEqual(@as(u8, 1), m.rank);
    try std.testing.expect(m.active == null);
    // the next one is harder at the higher rank
    _ = m.start();
    try std.testing.expectEqual(@as(u16, 2), m.active.?.goal);
}

test "a mission fails when its time runs out" {
    var m = Missions{};
    _ = m.start();
    try std.testing.expectEqual(Outcome.none, m.tick(44));
    try std.testing.expectEqual(Outcome.failed, m.tick(2));
    try std.testing.expectEqual(@as(u8, 0), m.rank);
}

test "holding the line is won by surviving and lost by draining" {
    var m = Missions{ .next = 4 };
    try std.testing.expectEqual(Kind.hold, m.start().?.kind);
    try std.testing.expectEqual(Outcome.none, m.tick(10));
    try std.testing.expectEqual(@as(u16, 10), m.active.?.progress);
    try std.testing.expectEqual(Outcome.failed, m.drained());
    m = Missions{ .next = 4 };
    _ = m.start();
    for (0..26) |_| _ = m.tick(1);
    try std.testing.expectEqual(@as(u8, 1), m.rank);
    // drains outside it do nothing
    try std.testing.expectEqual(Outcome.none, m.drained());
}

test "the rank stops at general" {
    var m = Missions{ .rank = ranks.len - 1 };
    _ = m.start();
    for (0..100) |_| _ = m.count(.barrage, 1);
    try std.testing.expectEqual(@as(u8, ranks.len - 1), m.rank);
}
