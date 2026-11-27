const std = @import("std");

pub const Backend = enum { win32, headless };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const default_backend: Backend = if (target.result.os.tag == .windows) .win32 else .headless;
    const backend = b.option(Backend, "backend", "Platform backend (win32, headless)") orelse default_backend;

    const options = b.addOptions();
    options.addOption(Backend, "backend", backend);

    const exe = b.addExecutable(.{
        .name = "doomball",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_options", options);
    if (backend == .win32) {
        exe.subsystem = .Windows;
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
    }
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the game").dependOn(&run.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
