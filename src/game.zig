//! The rules: serving, the plunger, scoring, draining and game over, on top
//! of the physics world.
const std = @import("std");
const platform = @import("platform.zig");
const physics = @import("physics.zig");
const table = @import("table.zig");
const missions = @import("missions.zig");

pub const start_balls = 3;

pub const Phase = enum { playing, game_over };

/// A line of the panel's message log.
pub const Message = struct {
    text: [max_message]u8 = undefined,
    len: u8 = 0,
    /// seconds since it was said
    age: f32 = 0,

    pub fn str(m: *const Message) []const u8 {
        return m.text[0..m.len];
    }
};
/// what fits a line of the panel's log
pub const max_message = 15;

const key_names = [3][]const u8{ "RED KEY", "BLUE KEY", "YELLOW KEY" };
pub const log_lines = 6;

/// Points for each event.
pub const points = struct {
    pub const bumper = 100;
    pub const sling = 10;
    pub const rollover = 50;
    pub const lanes_done = 1000;
    pub const target = 250;
    pub const mission_target = 500;
};

pub const Game = struct {
    world: physics.World = .{},
    score: u32 = 0,
    /// balls still to play, the one in play included
    balls_left: u8 = start_balls,
    plunger: f32 = 0,
    phase: Phase = .playing,
    prev_start: bool = false,
    time: f32 = 0,
    /// seconds each part stays lit after a hit
    bumper_flash: [table.bumpers.len]f32 = @splat(0),
    sling_flash: [2]f32 = @splat(0),
    target_flash: [table.targets.len]f32 = @splat(0),
    lanes_lit: [table.rollovers.len]bool = @splat(false),
    missions: missions.Missions = .{},
    keys: [3]bool = @splat(false),
    slain: u32 = 0,
    /// newest first
    log: [log_lines]Message = @splat(.{}),

    pub fn init() Game {
        var g = Game{};
        g.serve();
        g.say("SPACE: LAUNCH");
        return g;
    }

    /// Adds a line to the message log, cut to `max_message` characters.
    pub fn say(self: *Game, text: []const u8) void {
        var i: usize = log_lines - 1;
        while (i > 0) : (i -= 1) self.log[i] = self.log[i - 1];
        const n = @min(text.len, max_message);
        self.log[0] = .{ .len = @intCast(n) };
        @memcpy(self.log[0].text[0..n], text[0..n]);
    }

    pub fn update(self: *Game, in: platform.Input, dt: f32) void {
        self.time += dt;
        for (&self.log) |*m| m.age += dt;
        const start_edge = in.start and !self.prev_start;
        self.prev_start = in.start;
        if (self.phase == .game_over) {
            if (start_edge) self.reset();
            return;
        }
        for (&self.bumper_flash) |*f| f.* = @max(0, f.* - dt);
        for (&self.sling_flash) |*f| f.* = @max(0, f.* - dt);
        for (&self.target_flash) |*f| f.* = @max(0, f.* - dt);
        self.missionOutcome(self.missions.tick(dt));

        if (in.plunger) {
            self.plunger = @min(1, self.plunger + dt * 1.2);
        } else if (self.plunger > 0) {
            _ = self.world.launch(self.plunger);
            self.plunger = 0;
        }

        self.world.step(in.left, in.right, dt);
        for (self.world.eventList()) |e| self.handle(e);

        if (self.world.activeBalls() == 0) {
            self.balls_left -|= 1;
            if (self.balls_left == 0) {
                self.phase = .game_over;
                self.say("GAME OVER");
                self.say("ENTER: NEW GAME");
            } else {
                self.say("BALL LOST");
                self.missionOutcome(self.missions.drained());
                self.serve();
            }
        }
    }

    fn handle(self: *Game, e: physics.Event) void {
        switch (e.kind) {
            .bumper => {
                self.score += points.bumper;
                self.bumper_flash[e.id] = 0.15;
                self.missionOutcome(self.missions.count(.barrage, 1));
            },
            .sling => {
                self.score += points.sling;
                self.sling_flash[e.id] = 0.12;
            },
            .rollover => {
                self.score += points.rollover;
                self.lanes_lit[e.id] = true;
                if (std.mem.allEqual(bool, &self.lanes_lit, true)) {
                    self.score += points.lanes_done;
                    self.lanes_lit = @splat(false);
                    self.say("LANES COMPLETE");
                    self.missionOutcome(self.missions.count(.lanes, 1));
                }
            },
            .target => {
                self.target_flash[e.id] = 0.3;
                switch (table.targets[e.id].kind) {
                    .mission => {
                        self.score += points.mission_target;
                        if (self.missions.start()) |s| self.say(s.name);
                    },
                    .key_red, .key_blue, .key_yellow => |k| {
                        self.score += points.target;
                        const i = @backingInt(k);
                        if (!self.keys[i]) {
                            self.keys[i] = true;
                            self.say(key_names[i]);
                            self.missionOutcome(self.missions.count(.keys, 1));
                        }
                    },
                }
            },
            .wall, .rubber, .gate, .flipper, .flipper_up, .demon, .lock, .drain => {},
        }
    }

    fn missionOutcome(self: *Game, o: missions.Outcome) void {
        switch (o) {
            .none => {},
            .done => {
                self.score += missions.bonus(self.missions.rank);
                self.say("MISSION DONE");
                self.say("PROMOTED TO");
                self.say(missions.ranks[self.missions.rank]);
            },
            .failed => self.say("MISSION FAILED"),
        }
    }

    /// Whether target `i` shows lit: just hit, a key held, or the mission
    /// target blinking for a mission to start.
    pub fn targetLit(self: *const Game, i: usize) bool {
        if (self.target_flash[i] > 0) return true;
        return switch (table.targets[i].kind) {
            .mission => self.missions.active == null and @mod(self.time, 0.8) < 0.4,
            .key_red, .key_blue, .key_yellow => |k| self.keys[@backingInt(k)],
        };
    }

    fn serve(self: *Game) void {
        self.world.balls[0] = .{ .active = true };
    }

    pub fn reset(self: *Game) void {
        self.* = init();
        self.prev_start = true;
    }
};

const frame_dt = 1.0 / 60.0;

test "holding and releasing the plunger launches the ball" {
    var g = Game.init();
    for (0..30) |_| g.update(.{}, frame_dt);
    for (0..60) |_| g.update(.{ .plunger = true }, frame_dt);
    g.update(.{}, frame_dt);
    try std.testing.expect(g.world.balls[0].v.y < -1000);
}

test "draining every ball ends the game, and start begins a new one" {
    var g = Game.init();
    for (0..60 * 600) |i| {
        // launch whenever a ball waits in the lane; never flip
        g.update(.{ .plunger = i % 90 < 60 }, frame_dt);
        if (g.phase == .game_over) break;
    }
    try std.testing.expectEqual(Phase.game_over, g.phase);
    try std.testing.expect(g.score > 0);
    g.update(.{ .start = true }, frame_dt);
    try std.testing.expectEqual(Phase.playing, g.phase);
    try std.testing.expectEqual(@as(u8, start_balls), g.balls_left);
}

test "the message log keeps the newest lines first, cut to fit" {
    var g = Game.init();
    g.say("ONE");
    g.say("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    try std.testing.expectEqualStrings("ABCDEFGHIJKLMNO", g.log[0].str());
    try std.testing.expectEqualStrings("ONE", g.log[1].str());
}

test "the mission target starts a mission, and finishing it promotes" {
    var g = Game.init();
    const mission = for (table.targets, 0..) |t, i| {
        if (t.kind == .mission) break i;
    } else unreachable;
    g.handle(.{ .kind = .target, .id = @intCast(mission) });
    try std.testing.expect(g.missions.active != null);
    try std.testing.expectEqualStrings("BUMPER BARRAGE", g.log[0].str());
    for (0..missions.specs[0].goal) |_| g.handle(.{ .kind = .bumper });
    try std.testing.expectEqual(@as(u8, 1), g.missions.rank);
    try std.testing.expectEqualStrings("CORPORAL", g.log[0].str());
}

test "a key is held once hit and counts toward finding the keys" {
    var g = Game.init();
    g.missions.next = 3;
    _ = g.missions.start();
    g.handle(.{ .kind = .target, .id = 0 });
    g.handle(.{ .kind = .target, .id = 0 });
    try std.testing.expect(g.keys[0] and g.targetLit(0));
    try std.testing.expectEqual(@as(u16, 1), g.missions.active.?.progress);
}

test "completing the top lanes scores the bonus and clears them" {
    var g = Game.init();
    for (0..table.rollovers.len) |i| g.handle(.{ .kind = .rollover, .id = @intCast(i) });
    try std.testing.expectEqual(@as(u32, points.rollover * 3 + points.lanes_done), g.score);
    try std.testing.expect(!g.lanes_lit[0]);
}
