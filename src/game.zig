//! The rules: serving, the plunger, scoring, draining and game over, on top
//! of the physics world.
const std = @import("std");
const platform = @import("platform.zig");
const physics = @import("physics.zig");
const table = @import("table.zig");

pub const start_balls = 3;

pub const Phase = enum { playing, game_over };

pub const ranks = [_][]const u8{ "PRIVATE", "CORPORAL", "SERGEANT", "LIEUTENANT", "CAPTAIN", "MAJOR", "COLONEL", "GENERAL" };

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
    /// index into `ranks`
    rank: u8 = 0,
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
                self.serve();
            }
        }
    }

    fn handle(self: *Game, e: physics.Event) void {
        switch (e.kind) {
            .bumper => {
                self.score += points.bumper;
                self.bumper_flash[e.id] = 0.15;
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
                }
            },
            .target => {
                self.score += if (table.targets[e.id].kind == .mission) points.mission_target else points.target;
                self.target_flash[e.id] = 0.3;
            },
            .wall, .rubber, .gate, .flipper, .flipper_up, .demon, .lock, .drain => {},
        }
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

test "completing the top lanes scores the bonus and clears them" {
    var g = Game.init();
    for (0..table.rollovers.len) |i| g.handle(.{ .kind = .rollover, .id = @intCast(i) });
    try std.testing.expectEqual(@as(u32, points.rollover * 3 + points.lanes_done), g.score);
    try std.testing.expect(!g.lanes_lit[0]);
}
