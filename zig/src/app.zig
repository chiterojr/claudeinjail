const std = @import("std");
const util = @import("util.zig");
const images = @import("images.zig");

/// All mutable CLI state, mirroring the bash global variables.
pub const State = struct {
    build_only: bool = false,
    profile: []const u8 = "",
    select_image: bool = false,
    shell_only: bool = false,
    safe_mode: bool = false,
    do_resume: bool = false,
    tailscale: bool = false,
    exit_node: []const u8 = "",
    verbose: bool = false,
    wizard: bool = false,
    wizard_batch: bool = false,
    context_paths: std.ArrayList([]const u8) = .empty,
    context_names: std.ArrayList([]const u8) = .empty,
    image: images.Image = .{},
};

/// Port of add_context_dir. Resolves `input` to an absolute directory, checks
/// it exists, rejects /context/<name> collisions, and on success appends to the
/// state's context lists. Returns true on success, false (with a stderr error)
/// otherwise.
pub fn addContextDir(a: std.mem.Allocator, home: []const u8, state: *State, input_raw: []const u8) bool {
    if (input_raw.len == 0) {
        util.err("Error: empty context directory path.\n");
        return false;
    }

    // Expand a leading ~ to $HOME.
    var input = input_raw;
    if (std.mem.startsWith(u8, input, "~")) {
        input = std.fmt.allocPrint(a, "{s}{s}", .{ home, input_raw[1..] }) catch input_raw;
    }

    const abs = std.fs.cwd().realpathAlloc(a, input) catch {
        util.errf(a, "Error: context directory not found (or not a directory): {s}\n", .{input_raw});
        return false;
    };
    if (!util.dirExists(abs)) {
        util.errf(a, "Error: context directory not found (or not a directory): {s}\n", .{input_raw});
        return false;
    }

    const name = std.fs.path.basename(abs);
    if (name.len == 0 or util.eql(name, "/")) {
        util.errf(a, "Error: cannot derive a /context name from: {s}\n", .{abs});
        return false;
    }

    for (state.context_names.items) |existing| {
        if (util.eql(existing, name)) {
            util.errf(a, "Error: '/context/{s}' is already mapped — directory names must be unique.\n", .{name});
            return false;
        }
    }

    state.context_paths.append(a, abs) catch return false;
    state.context_names.append(a, a.dupe(u8, name) catch return false) catch return false;
    return true;
}
