const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");
const templates = @import("templates.zig");
const profile = @import("profile.zig");
const images = @import("images.zig");
const app = @import("app.zig");

// ── Docker build ────────────────────────────────────────────────────────────

pub fn buildImage(a: std.mem.Allocator, paths: config.Paths, image: images.Image) void {
    util.mkdirAll(paths.cache_dir);
    const dockerfile = util.join(a, &.{ paths.cache_dir, "Dockerfile" });

    if (std.mem.startsWith(u8, image.variant, "custom:")) {
        const cname = image.variant["custom:".len..];
        const src = paths.imageDockerfile(a, cname);
        const content = util.readFile(a, src) orelse {
            util.outf(a, "Error: custom image '{s}' not found at {s}\n", .{ cname, src });
            std.process.exit(1);
        };
        util.writeOrDie(a, dockerfile, content);
        util.out("\n");
        util.outf(a, "Using custom image '{s}' from {s}\n", .{ cname, src });
        util.outf(a, "Building image '{s}'...\n", .{image.name});
        util.out("\n");
    } else {
        const body = templates.dockerfileForVariant(image.variant) orelse templates.dockerfile_alpine;
        util.writeOrDie(a, dockerfile, body);
        util.out("\n");
        util.outf(a, "Building image '{s}'. Docker cache ensures that\n", .{image.name});
        util.out("rebuilds with no changes are instantaneous.\n");
        util.out("\n");
    }

    const code = util.run(a, &.{ "docker", "build", "-t", image.name, "-f", dockerfile, paths.cache_dir });
    if (code != 0) std.process.exit(code);
}

// ── Profile resolution / validation ─────────────────────────────────────────

pub fn resolveProfile(a: std.mem.Allocator, paths: config.Paths, state: *app.State) void {
    if (state.profile.len > 0) return;

    util.mkdirAll(paths.config_dir);

    if (util.fileExists(paths.default_file)) {
        state.profile = util.readFileTrimmed(a, paths.default_file) orelse "";

        if (util.dirExists(paths.profileDir(a, state.profile))) {
            util.outf(a, "Default profile found: '{s}'\n", .{state.profile});
            util.out("To use a different profile, pass the --profile <name> flag.\n");
            return;
        }

        util.outf(a, "The default profile '{s}' is configured in {s}\n", .{ state.profile, paths.default_file });
        util.outf(a, "but the corresponding directory was not found in {s}\n", .{paths.config_dir});
        util.out("\n");
        const answer = util.prompt(a, "Do you want to remove this pointer? [y/N]: ");
        if (util.eql(answer, "y") or util.eql(answer, "Y")) util.removeFile(paths.default_file);
        state.profile = "";
        util.out("\n");
    }

    const profiles = profile.list(a, paths);

    if (profiles.len == 0) {
        util.out("\n");
        util.outf(a, "No profiles found in {s}\n", .{paths.config_dir});
        util.out("\n");
        util.out("Profiles let you use different Claude accounts (e.g., personal, work).\n");
        util.out("Each profile keeps its own credentials and settings fully isolated.\n");
        util.out("\n");
        state.profile = util.sanitizeName(a, util.prompt(a, "Name for the first profile to create: "));
        return;
    }

    util.out("\n");
    util.outf(a, "No default profile set in {s}\n", .{paths.default_file});
    util.out("\n");
    util.out("Profiles let you use different Claude accounts (e.g., personal, work).\n");
    util.out("Select an existing profile or create a new one:\n");
    util.out("\n");
    for (profiles, 0..) |p, i| util.outf(a, "  {d}) {s}\n", .{ i + 1, p });
    util.out("  n) Create new profile\n");
    util.out("\n");
    const pchoice = util.prompt(a, "Choose: ");

    if (util.eql(pchoice, "n") or util.eql(pchoice, "N")) {
        util.out("\n");
        util.outf(a, "The profile name will be used as a directory in {s}\n", .{paths.config_dir});
        util.out("Use only letters, numbers, hyphens, and underscores.\n");
        util.out("\n");
        state.profile = util.sanitizeName(a, util.prompt(a, "New profile name: "));
        return;
    }

    if (std.fmt.parseInt(usize, pchoice, 10)) |n| {
        if (n >= 1 and n <= profiles.len) {
            state.profile = profiles[n - 1];
            return;
        }
    } else |_| {}

    util.out("Invalid option.\n");
    std.process.exit(1);
}

pub fn validateProfile(a: std.mem.Allocator, paths: config.Paths, state: *app.State) void {
    if (state.profile.len == 0) return;

    state.profile = util.sanitizeName(a, state.profile);
    if (state.profile.len == 0) {
        util.out("Error: invalid profile name. Use only letters, numbers, hyphens, and underscores.\n");
        std.process.exit(1);
    }

    if (!util.dirExists(paths.profileDir(a, state.profile))) {
        util.outf(a, "Error: profile '{s}' not found in {s}\n", .{ state.profile, paths.config_dir });
        util.out("\n");
        util.out("Available profiles:\n");
        const profiles = profile.list(a, paths);
        if (profiles.len == 0) {
            util.out("  (none)\n");
        } else {
            for (profiles) |p| util.outf(a, "  - {s}\n", .{p});
        }
        util.out("\n");
        util.outf(a, "Create one with: claudeinjail profile create {s}\n", .{state.profile});
        std.process.exit(1);
    }
}

// ── git identity ────────────────────────────────────────────────────────────

/// Generates a temporary gitconfig from the host's resolved user.name/email.
/// Aborts if no identity can be produced. Returns the temp file path.
pub fn generateGitconfig(a: std.mem.Allocator, instance: []const u8) []const u8 {
    if (!util.commandExists(a, "git")) {
        util.err("Error: git is not installed on the host; cannot generate a .gitconfig for the container.\n");
        std.process.exit(1);
    }

    const name_res = util.capture(a, &.{ "git", "config", "user.name" });
    const email_res = util.capture(a, &.{ "git", "config", "user.email" });
    const git_name = if (name_res) |r| util.trimWs(r.stdout) else "";
    const git_email = if (email_res) |r| util.trimWs(r.stdout) else "";

    if (git_name.len == 0 and git_email.len == 0) {
        util.err("Error: no git user.name or user.email configured; cannot generate a .gitconfig for the container.\n");
        util.err("Configure one first, e.g.:\n");
        util.err("  git config --global user.name \"Your Name\"\n");
        util.err("  git config --global user.email you@example.com\n");
        std.process.exit(1);
    }

    var buf = std.ArrayList(u8){};
    util.pushSlice(a, &buf, "[user]\n");
    if (git_name.len > 0) util.pushSlice(a, &buf, util.fmt(a, "    name = {s}\n", .{git_name}));
    if (git_email.len > 0) util.pushSlice(a, &buf, util.fmt(a, "    email = {s}\n", .{git_email}));

    const path = util.fmt(a, "/tmp/{s}-gitconfig", .{instance});
    util.writeFileMode(path, buf.items, 0o644) catch {
        util.errf(a, "Error: failed to write temporary gitconfig at {s}.\n", .{path});
        std.process.exit(1);
    };
    if (!util.fileExists(path)) {
        util.errf(a, "Error: temporary gitconfig was not created at {s}.\n", .{path});
        std.process.exit(1);
    }
    return path;
}
