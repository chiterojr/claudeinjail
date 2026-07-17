const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");
const app = @import("app.zig");
const profile = @import("profile.zig");
const images = @import("images.zig");

fn createProfile(a: std.mem.Allocator, paths: config.Paths, state: *app.State) void {
    var name: []const u8 = "";
    while (true) {
        name = util.sanitizeName(a, util.prompt(a, "New profile name: "));
        if (name.len == 0) {
            util.err("Invalid name. Use only letters, numbers, hyphens, and underscores.\n");
            continue;
        }
        if (util.eql(name, "images")) {
            util.err("'images' is a reserved name (used for custom images).\n");
            continue;
        }
        break;
    }

    const dir = paths.profileDir(a, name);
    if (!util.dirExists(dir)) {
        util.mkdirAll(util.join(a, &.{ dir, ".claude" }));
        util.writeOrDie(a, util.join(a, &.{ dir, ".claude.json" }), "{}\n");
        util.outf(a, "Profile '{s}' created.\n", .{name});
    }
    state.profile = name;
}

fn pickProfile(a: std.mem.Allocator, paths: config.Paths, state: *app.State) void {
    if (state.profile.len > 0) return;

    util.mkdirAll(paths.config_dir);
    const default_name = profile.getDefault(a, paths);
    const profiles = profile.list(a, paths);

    util.out("\n");
    util.out("Profile — which account/credentials to use.\n");
    util.out("\n");

    if (profiles.len == 0) {
        util.out("No profiles found — let's create your first one.\n");
        createProfile(a, paths, state);
        return;
    }

    while (true) {
        for (profiles, 0..) |p, i| {
            if (default_name != null and util.eql(p, default_name.?)) {
                util.outf(a, "  {d}) {s}  (default)\n", .{ i + 1, p });
            } else {
                util.outf(a, "  {d}) {s}\n", .{ i + 1, p });
            }
        }
        util.out("  n) Create new profile\n");
        const label = if (default_name) |d| d else "1";
        const choice = util.prompt(a, util.fmt(a, "Choose [{s}]: ", .{label}));

        if (choice.len == 0) {
            state.profile = if (default_name) |d| d else profiles[0];
            return;
        }
        if (util.eql(choice, "n") or util.eql(choice, "N")) {
            createProfile(a, paths, state);
            return;
        }
        if (std.fmt.parseInt(usize, choice, 10)) |n| {
            if (n >= 1 and n <= profiles.len) {
                state.profile = profiles[n - 1];
                return;
            }
        } else |_| {}
        util.err("Invalid option, try again.\n");
        util.out("\n");
    }
}

fn pickContext(a: std.mem.Allocator, home: []const u8, state: *app.State) void {
    util.out("\n");
    util.out("Context directories — mounted read-only at /context/<name>.\n");
    util.out("Expose extra host directories to Claude. Press Enter (empty) to finish.\n");
    util.out("\n");
    while (true) {
        const dir = util.prompt(a, "Context directory (empty to finish): ");
        if (dir.len == 0) break;
        if (app.addContextDir(a, home, state, dir)) {
            const idx = state.context_names.items.len - 1;
            util.outf(a, "  mapped /context/{s}  <-  {s}\n", .{ state.context_names.items[idx], state.context_paths.items[idx] });
        }
    }
}

fn pickResume(a: std.mem.Allocator, state: *app.State) void {
    if (state.do_resume) return;
    util.out("\n");
    const ans = util.prompt(a, "Resume a previous Claude session? [y/N]: ");
    if (util.eql(ans, "y") or util.eql(ans, "Y")) state.do_resume = true;
}

fn pickTailscale(a: std.mem.Allocator, state: *app.State) void {
    if (state.tailscale) return;
    util.out("\n");
    const ans = util.prompt(a, "Connect to Tailscale? [y/N]: ");
    if (util.eql(ans, "y") or util.eql(ans, "Y")) {
        state.tailscale = true;
        const node = util.stripAllWs(a, util.prompt(a, "Exit node (machine name or IP; empty for none): "));
        if (node.len > 0) state.exit_node = node;
    }
}

pub fn run(a: std.mem.Allocator, paths: config.Paths, home: []const u8, state: *app.State) void {
    util.out("\n");
    util.out("claudeinjail wizard\n");
    util.out("Answer the prompts below. Press Enter to accept the default.\n");

    pickProfile(a, paths, state);
    state.image = images.selectImage(a, paths); // reuses the standard image picker
    state.select_image = false; // already handled; skip the later select_image call
    pickContext(a, home, state);
    pickResume(a, state);
    pickTailscale(a, state);
}

// ── Batch wizard (-ww / --wizard-batch) ──────────────────────────────────────
//
// Shows every wizard step at once, then reads all answers from a single line.
// Answers are positional and separated by ';'. Omitted fields (empty or dropped
// from the tail) fall back to their default; only the profile is required.
//
//   Order:   profile ; image ; contexts ; resume ; tailscale ; exit-node
//   Example: 1;3;~/dev/a,~/dev/b;n;y;my-server
//
// The step order mirrors run(). When adding a wizard step, update both.

/// Returns the Nth ';'-separated field of `line`, preserving empty fields.
fn nthField(line: []const u8, n: usize) []const u8 {
    var it = std.mem.splitScalar(u8, line, ';');
    var idx: usize = 0;
    while (it.next()) |part| : (idx += 1) {
        if (idx == n) return part;
    }
    return "";
}

fn isYes(s: []const u8) bool {
    return util.eql(s, "y") or util.eql(s, "Y") or util.eql(s, "yes");
}

pub fn runBatch(a: std.mem.Allocator, paths: config.Paths, home: []const u8, state: *app.State) void {
    util.mkdirAll(paths.config_dir);
    const default_name = profile.getDefault(a, paths);
    const profiles = profile.list(a, paths);
    const customs = images.listCustom(a, paths);

    if (profiles.len == 0) {
        util.errf(a, "Error: no profiles found in {s}\n", .{paths.config_dir});
        util.err("Create one first: claudeinjail profile create <name>\n");
        std.process.exit(1);
    }

    // Number of the default profile, used in the example line.
    var default_num: usize = 1;
    for (profiles, 0..) |p, i| {
        if (default_name != null and util.eql(p, default_name.?)) default_num = i + 1;
    }

    util.out("\n");
    util.out("claudeinjail — batch wizard (-ww)\n");
    util.out("=================================\n");
    util.out("\n");
    util.out("Answer every step in a single line, fields separated by ';' (positional).\n");
    util.out("Leave a field empty (or drop trailing fields) to accept its default.\n");
    util.out("Only the profile is required.\n");
    util.out("\n");
    util.out("  Order:   profile ; image ; contexts ; resume ; tailscale ; exit-node\n");
    util.outf(a, "  Example: {d};1;~/dev/a,~/dev/b;n;y;my-server\n", .{default_num});
    util.out("\n");

    util.out("[1] PROFILE  (required)\n");
    for (profiles, 0..) |p, i| {
        if (default_name != null and util.eql(p, default_name.?)) {
            util.outf(a, "    {d}) {s}  (default)\n", .{ i + 1, p });
        } else {
            util.outf(a, "    {d}) {s}\n", .{ i + 1, p });
        }
    }
    util.out("    -> a number from the list\n");
    util.out("\n");

    util.out("[2] IMAGE  (default: 1 — Alpine)\n");
    util.out("    1) Alpine (alpine:3)\n");
    util.out("    2) Debian (debian:12-slim)\n");
    util.out("    3) Alpine + Node.js + Bun (node:lts-alpine)\n");
    util.out("    4) Debian + Node.js + Bun (node:lts-slim)\n");
    var n: usize = 5;
    for (customs) |name| {
        const desc = images.readDescription(a, paths.imageDockerfile(a, name));
        if (desc != null and desc.?.len > 0) {
            util.outf(a, "    {d}) custom: {s} — {s}\n", .{ n, name, desc.? });
        } else {
            util.outf(a, "    {d}) custom: {s}\n", .{ n, name });
        }
        n += 1;
    }
    util.out("    -> a number from the list\n");
    util.out("\n");

    util.out("[3] CONTEXT DIRECTORIES  (default: none)\n");
    util.out("    Host dirs mounted read-only at /context/<name>, comma-separated.\n");
    util.out("    -> e.g. ~/dev/a,~/dev/b\n");
    util.out("\n");

    util.out("[4] RESUME  (default: n)\n");
    util.out("    Resume a previous Claude session.\n");
    util.out("    -> y / n\n");
    util.out("\n");

    util.out("[5] TAILSCALE  (default: n)\n");
    util.out("    Connect the container to your tailnet.\n");
    util.out("    -> y / n\n");
    util.out("\n");

    util.out("[6] EXIT NODE  (default: none — requires tailscale = y)\n");
    util.out("    Route all container traffic through a Tailscale exit node.\n");
    util.out("    -> machine name or IP\n");
    util.out("\n");

    const line = util.prompt(a, "Your answer: ");

    const f_profile = util.stripAllWs(a, nthField(line, 0));
    const f_image = util.stripAllWs(a, nthField(line, 1));
    const f_context = nthField(line, 2);
    const f_resume = util.stripAllWs(a, nthField(line, 3));
    const f_tailscale = util.stripAllWs(a, nthField(line, 4));
    const f_exitnode = util.stripAllWs(a, nthField(line, 5));

    // [1] Profile — required.
    if (f_profile.len == 0) {
        util.err("Error: profile (field 1) is required.\n");
        std.process.exit(1);
    }
    const pnum = std.fmt.parseInt(usize, f_profile, 10) catch {
        util.errf(a, "Error: invalid profile selection '{s}'. Choose 1-{d}.\n", .{ f_profile, profiles.len });
        std.process.exit(1);
    };
    if (pnum < 1 or pnum > profiles.len) {
        util.errf(a, "Error: invalid profile selection '{s}'. Choose 1-{d}.\n", .{ f_profile, profiles.len });
        std.process.exit(1);
    }
    state.profile = profiles[pnum - 1];

    // [2] Image — default Alpine when omitted.
    if (f_image.len > 0) {
        if (images.applyChoice(a, paths, f_image)) |img| {
            state.image = img;
        } else {
            util.errf(a, "Warning: invalid image selection '{s}'; using default (Alpine).\n", .{f_image});
            state.image = .{ .name = "claudeinjail-alpine", .variant = "alpine" };
        }
    }
    state.select_image = false; // handled here; skip the later select_image call

    // [3] Context — comma-separated list of host directories.
    if (f_context.len > 0) {
        var it = std.mem.splitScalar(u8, f_context, ',');
        while (it.next()) |raw| {
            const d = std.mem.trim(u8, raw, " \t\r\n");
            if (d.len == 0) continue;
            if (!app.addContextDir(a, home, state, d)) std.process.exit(1);
        }
    }

    // [4] Resume.
    if (isYes(f_resume)) state.do_resume = true;

    // [5] Tailscale.
    if (isYes(f_tailscale)) state.tailscale = true;

    // [6] Exit node — only meaningful with Tailscale enabled.
    if (f_exitnode.len > 0) {
        if (state.tailscale) {
            state.exit_node = f_exitnode;
        } else {
            util.err("Warning: exit node ignored — it requires tailscale = y (field 5).\n");
        }
    }
}
