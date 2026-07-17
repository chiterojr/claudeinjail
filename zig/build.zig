const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Default to ReleaseSmall for a compact binary; overridable with -Doptimize.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size (default: ReleaseSmall)",
    ) orelse .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "claudeinjail",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // Strip debug info by default (still overridable via -Dstrip=false).
            .strip = b.option(bool, "strip", "Strip debug info (default: true)") orelse true,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run claudeinjail");
    run_step.dependOn(&run_cmd.step);

    // `zig build lint` — run the zlint linter (must be installed on PATH).
    const lint_cmd = b.addSystemCommand(&.{"zlint"});
    lint_cmd.setCwd(b.path("."));
    const lint_step = b.step("lint", "Lint the source with zlint");
    lint_step.dependOn(&lint_cmd.step);
}
