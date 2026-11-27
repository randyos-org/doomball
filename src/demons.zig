//! Demons roaming the pit: they wander, the ball knocks them back, and a few
//! hits slay them; a slain one sinks into the sludge and returns later.
const std = @import("std");
const vec = @import("vec.zig");
const table = @import("table.zig");
const physics = @import("physics.zig");

const V2 = vec.V2;
const v2 = vec.v2;

pub const Kind = enum {
    brute,
    crawler,

    pub fn radius(k: Kind) f32 {
        return switch (k) {
            .brute => 17,
            .crawler => 14,
        };
    }

    /// height of the sprite above the playfield
    pub fn height(k: Kind) f32 {
        return switch (k) {
            .brute => 54,
            .crawler => 22,
        };
    }

    fn speed(k: Kind) f32 {
        return switch (k) {
            .brute => 22,
            .crawler => 48,
        };
    }

    fn hits(k: Kind) u8 {
        return switch (k) {
            .brute => 3,
            .crawler => 2,
        };
    }

    pub fn points(k: Kind) u32 {
        return switch (k) {
            .brute => 1500,
            .crawler => 1000,
        };
    }
};

pub const State = enum { away, walking, pain, dying };

pub const pain_time: f32 = 0.35;
pub const death_time: f32 = 1.2;
const return_time: f32 = 7;
pub const hit_points = 150;

pub const Demon = struct {
    kind: Kind,
    state: State = .away,
    p: V2 = v2(0, 0),
    goal: V2 = v2(0, 0),
    hp: u8 = 0,
    /// seconds into the current state
    timer: f32 = 0,
    /// distance walked, for the walk frames
    stride: f32 = 0,
    facing_left: bool = false,
    /// not yet arrived since the game began
    first: bool = true,

    pub fn solid(d: Demon) bool {
        return d.state == .walking or d.state == .pain;
    }
};

pub const Hit = enum { none, hurt, slain };

pub const Demons = struct {
    list: [physics.max_demons]Demon = .{ .{ .kind = .brute }, .{ .kind = .crawler }, .{ .kind = .crawler }, .{ .kind = .brute } },
    rng: u32 = 0x9e3779b9,

    fn rand(self: *Demons) f32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 17;
        self.rng ^= self.rng << 5;
        return @as(f32, @floatFromInt(self.rng & 0xffff)) / 65535;
    }

    fn spot(self: *Demons, k: Kind) V2 {
        const pit = table.pit;
        const m = k.radius() + 8;
        return v2(pit.x0 + m + self.rand() * (pit.x1 - pit.x0 - 2 * m), pit.y0 + m + self.rand() * (pit.y1 - pit.y0 - 2 * m));
    }

    /// How many roam at a rank: two at first, up to four.
    pub fn wanted(rank: u8) usize {
        return @min(physics.max_demons, 2 + @as(usize, rank) / 2);
    }

    pub fn update(self: *Demons, dt: f32, rank: u8) void {
        const n = wanted(rank);
        for (&self.list, 0..) |*d, i| {
            d.timer += dt;
            switch (d.state) {
                .away => if (i < n and (d.first or d.timer > return_time)) self.arrive(d),
                .pain => if (d.timer > pain_time) self.setState(d, .walking),
                .dying => if (d.timer > death_time) self.setState(d, .away),
                .walking => {
                    const to = d.goal.sub(d.p);
                    const dist = to.len();
                    if (dist < 4) {
                        d.goal = self.spot(d.kind);
                        continue;
                    }
                    const step = @min(dist, d.kind.speed() * dt);
                    d.p = d.p.add(to.mul(step / dist));
                    d.stride += step;
                    d.facing_left = to.x < 0;
                },
            }
        }
    }

    fn arrive(self: *Demons, d: *Demon) void {
        d.p = self.spot(d.kind);
        d.goal = self.spot(d.kind);
        d.hp = d.kind.hits();
        d.first = false;
        self.setState(d, .walking);
    }

    fn setState(_: *Demons, d: *Demon, s: State) void {
        d.state = s;
        d.timer = 0;
    }

    /// The ball at `ball` hit demon `i`: knocks it back, and maybe slays it.
    /// A demon in pain cannot be hurt again until it recovers.
    pub fn hit(self: *Demons, i: usize, ball: V2) Hit {
        const d = &self.list[i];
        if (d.state != .walking) return .none;
        const away = d.p.sub(ball).norm();
        const pit = table.pit;
        const r = d.kind.radius();
        d.p = d.p.add(away.mul(10));
        d.p = v2(std.math.clamp(d.p.x, pit.x0 + r, pit.x1 - r), std.math.clamp(d.p.y, pit.y0 + r, pit.y1 - r));
        d.hp -|= 1;
        if (d.hp == 0) {
            self.setState(d, .dying);
            return .slain;
        }
        self.setState(d, .pain);
        return .hurt;
    }

    /// The circles the balls collide with.
    pub fn circles(self: *const Demons) [physics.max_demons]?physics.Circle {
        var out: [physics.max_demons]?physics.Circle = @splat(null);
        for (self.list, &out) |d, *o| {
            if (d.solid()) o.* = .{ .c = d.p, .r = d.kind.radius() };
        }
        return out;
    }
};

test "two demons arrive at first, inside the pit, and wander there" {
    var ds = Demons{};
    ds.update(0.016, 0);
    var n: usize = 0;
    for (ds.list) |d| n += @intFromBool(d.solid());
    try std.testing.expectEqual(@as(usize, 2), n);
    for (0..600) |_| ds.update(0.016, 0);
    for (ds.list) |d| {
        if (!d.solid()) continue;
        try std.testing.expect(d.p.x > table.pit.x0 and d.p.x < table.pit.x1);
        try std.testing.expect(d.p.y > table.pit.y0 and d.p.y < table.pit.y1);
    }
    try std.testing.expectEqual(@as(usize, 4), Demons.wanted(7));
}

test "a brute takes three hits, with a pause between, and returns later" {
    var ds = Demons{};
    ds.update(0.016, 0);
    const ball = ds.list[0].p.add(v2(-20, 0));
    try std.testing.expectEqual(Hit.hurt, ds.hit(0, ball));
    try std.testing.expectEqual(Hit.none, ds.hit(0, ball));
    ds.update(pain_time + 0.01, 0);
    try std.testing.expectEqual(Hit.hurt, ds.hit(0, ball));
    ds.update(pain_time + 0.01, 0);
    try std.testing.expectEqual(Hit.slain, ds.hit(0, ball));
    try std.testing.expect(ds.circles()[0] == null);
    ds.update(death_time + 0.01, 0);
    try std.testing.expectEqual(State.away, ds.list[0].state);
    ds.update(return_time + 0.01, 0);
    try std.testing.expectEqual(State.walking, ds.list[0].state);
}
