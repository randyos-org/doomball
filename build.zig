const std = @import("std");
const rstd = @import("rstd");

pub const Backend = enum { win32, headless };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const default_backend: Backend = if (target.result.os.tag == .windows) .win32 else .headless;
    const backend = b.option(Backend, "backend", "Platform backend (win32, headless)") orelse default_backend;

    const options = b.addOptions();
    options.addOption(Backend, "backend", backend);

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addOptions("build_options", options);
    if (backend == .win32) {
        root.linkSystemLibrary("user32", .{});
        root.linkSystemLibrary("gdi32", .{});
        root.linkSystemLibrary("winmm", .{});
    }
    // rstd (vendor/rstd), for rgl as it grows (#28); no BLAS kernels, since
    // nothing here does linear algebra
    const rstd_mod = try rstd.buildutils.addRstd(b, target, null, false, .{ .optimize = optimize, .blas_cores = .none });
    rstd_mod.addImportToModule(root);
    const exe = b.addExecutable(.{ .name = "doomball", .root_module = root });
    if (backend == .win32) exe.subsystem = .windows;
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.option(u32, "frames", "Headless backend: number of frames to run")) |n| run.addArg(b.fmt("{d}", .{n}));
    b.step("run", "Run the game").dependOn(&run.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    rstd_mod.addImportToModule(test_mod);
    const tests = b.addTest(.{ .root_module = test_mod });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
