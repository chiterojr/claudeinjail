const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");

/// Reads the default profile name (trimmed), or null if none is set.
pub fn getDefault(a: std.mem.Allocator, paths: config.Paths) ?[]const u8 {
    if (!util.fileExists(paths.default_file)) return null;
    const name = util.readFileTrimmed(a, paths.default_file) orelse return null;
    if (name.len == 0) return null;
    return name;
}

/// Lists profile names: immediate sub-dirs of config_dir except "images".
pub fn list(a: std.mem.Allocator, paths: config.Paths) [][]u8 {
    return util.listDirs(a, paths.config_dir, "images");
}

pub fn cmdCreate(a: std.mem.Allocator, paths: config.Paths, name_arg: []const u8) noreturn {
    const name = util.sanitizeName(a, name_arg);

    if (name.len == 0) {
        util.out("Error: invalid or missing profile name.\n");
        util.out("Use only letters, numbers, hyphens, and underscores.\n");
        util.out("\n");
        util.out("Usage: claudeinjail profile create <name>\n");
        std.process.exit(1);
    }

    if (util.eql(name, "images")) {
        util.out("Error: 'images' is a reserved name (used for custom images).\n");
        std.process.exit(1);
    }

    const profile_dir = paths.profileDir(a, name);
    if (util.dirExists(profile_dir)) {
        util.outf(a, "Profile '{s}' already exists at {s}\n", .{ name, profile_dir });
        std.process.exit(1);
    }

    util.mkdirAll(util.join(a, &.{ profile_dir, ".claude" }));
    util.writeOrDie(a, util.join(a, &.{ profile_dir, ".claude.json" }), "{}\n");

    util.outf(a, "Profile '{s}' created successfully.\n", .{name});
    util.outf(a, "Location: {s}\n", .{profile_dir});
    util.out("\n");
    util.out("To use it:\n");
    util.outf(a, "  claudeinjail -p {s}\n", .{name});
    util.out("\n");
    util.out("To set it as default:\n");
    util.outf(a, "  claudeinjail profile set-default {s}\n", .{name});
    std.process.exit(0);
}

pub fn cmdList(a: std.mem.Allocator, paths: config.Paths) noreturn {
    util.mkdirAll(paths.config_dir);

    const default_name = getDefault(a, paths);
    const profiles = list(a, paths);

    if (profiles.len == 0) {
        util.out("No profiles found.\n");
        util.out("\n");
        util.out("Create one with: claudeinjail profile create <name>\n");
        std.process.exit(0);
    }

    util.out("Existing profiles:\n");
    util.out("\n");
    for (profiles) |p| {
        if (default_name != null and util.eql(p, default_name.?)) {
            util.outf(a, "  * {s}  (default)\n", .{p});
        } else {
            util.outf(a, "    {s}\n", .{p});
        }
    }
    util.out("\n");
    util.outf(a, "Location: {s}\n", .{paths.config_dir});

    if (default_name == null) {
        util.out("\n");
        util.out("No default profile set.\n");
        util.out("Set one with: claudeinjail profile set-default <name>\n");
    }
    std.process.exit(0);
}

pub fn cmdDelete(a: std.mem.Allocator, paths: config.Paths, name_arg: []const u8, confirm_flag: []const u8) noreturn {
    const name = util.sanitizeName(a, name_arg);

    if (name.len == 0) {
        util.out("Error: profile name not provided.\n");
        util.out("\n");
        util.out("Usage: claudeinjail profile delete <name>\n");
        util.out("\n");
        util.out("Deletion requires two confirmations to prevent accidental loss:\n");
        util.out("  1) The --confirm flag in the command\n");
        util.out("  2) An interactive confirmation\n");
        util.out("\n");
        util.out("Example: claudeinjail profile delete my-profile --confirm\n");
        std.process.exit(1);
    }

    const profile_dir = paths.profileDir(a, name);
    if (!util.dirExists(profile_dir)) {
        util.outf(a, "Error: profile '{s}' not found in {s}\n", .{ name, paths.config_dir });
        std.process.exit(1);
    }

    if (!util.eql(confirm_flag, "--confirm")) {
        util.out("To delete a profile, pass the --confirm flag as an extra\n");
        util.out("safety layer against accidental deletions.\n");
        util.out("\n");
        util.outf(a, "Usage: claudeinjail profile delete {s} --confirm\n", .{name});
        std.process.exit(1);
    }

    util.outf(a, "You are about to delete the profile '{s}'.\n", .{name});
    util.out("This will permanently remove all credentials and settings\n");
    util.outf(a, "stored in: {s}\n", .{profile_dir});
    util.out("\n");
    const answer = util.prompt(a, util.fmt(a, "Are you sure? Type '{s}' to confirm: ", .{name}));

    if (!util.eql(answer, name)) {
        util.out("Deletion cancelled. The text entered does not match the profile name.\n");
        std.process.exit(0);
    }

    if (getDefault(a, paths)) |dn| {
        if (util.eql(dn, name)) {
            util.removeFile(paths.default_file);
            util.outf(a, "The default profile pointer was removed (it pointed to '{s}').\n", .{name});
        }
    }

    util.removeTree(profile_dir);
    util.outf(a, "Profile '{s}' deleted successfully.\n", .{name});
    std.process.exit(0);
}

pub fn cmdSetDefault(a: std.mem.Allocator, paths: config.Paths, name_arg: []const u8) noreturn {
    const name = util.sanitizeName(a, name_arg);

    if (name.len == 0) {
        util.out("Error: profile name not provided.\n");
        util.out("\n");
        util.out("Usage: claudeinjail profile set-default <name>\n");
        std.process.exit(1);
    }

    if (!util.dirExists(paths.profileDir(a, name))) {
        util.outf(a, "Error: profile '{s}' not found in {s}\n", .{ name, paths.config_dir });
        util.out("\n");
        util.out("Available profiles:\n");
        for (list(a, paths)) |p| util.outf(a, "  - {s}\n", .{p});
        std.process.exit(1);
    }

    util.mkdirAll(paths.config_dir);
    util.writeOrDie(a, paths.default_file, util.fmt(a, "{s}\n", .{name}));
    util.outf(a, "Default profile set to '{s}'.\n", .{name});
    std.process.exit(0);
}

pub fn dispatch(a: std.mem.Allocator, paths: config.Paths, sub: []const u8, arg: []const u8, arg2: []const u8) noreturn {
    if (util.eql(sub, "create")) cmdCreate(a, paths, arg);
    if (util.eql(sub, "list") or util.eql(sub, "ls")) cmdList(a, paths);
    if (util.eql(sub, "delete") or util.eql(sub, "rm")) cmdDelete(a, paths, arg, arg2);
    if (util.eql(sub, "set-default")) cmdSetDefault(a, paths, arg);

    util.outf(a, "Unknown profile command: '{s}'\n", .{sub});
    util.out("\n");
    util.out("Available commands:\n");
    util.out("  profile create <name>\n");
    util.out("  profile list\n");
    util.out("  profile delete <name> --confirm\n");
    util.out("  profile set-default <name>\n");
    std.process.exit(1);
}
