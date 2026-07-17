const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");
const templates = @import("templates.zig");
const profile = @import("profile.zig");
const images = @import("images.zig");
const app = @import("app.zig");
const wizard = @import("wizard.zig");
const run = @import("run.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const paths = config.Paths.init(a) catch std.process.exit(1);
    const args = try std.process.argsAlloc(a);

    var state = app.State{};

    // ── Argument parsing (mirrors the bash while/case loop) ──────────────────
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (util.eql(arg, "help") or util.eql(arg, "--help") or util.eql(arg, "-h")) {
            util.out(templates.help_text);
            return;
        } else if (util.eql(arg, "eject")) {
            const name: ?[]const u8 = if (i + 1 < args.len) args[i + 1] else null;
            images.cmdEject(a, paths, name); // noreturn
        } else if (util.eql(arg, "profile")) {
            const sub = if (i + 1 < args.len) args[i + 1] else "";
            const sarg = if (i + 2 < args.len) args[i + 2] else "";
            const sarg2 = if (i + 3 < args.len) args[i + 3] else "";
            profile.dispatch(a, paths, sub, sarg, sarg2); // noreturn
        } else if (util.eql(arg, "list") or util.eql(arg, "ls")) {
            profile.cmdList(a, paths); // noreturn
        } else if (util.eql(arg, "--build-only") or util.eql(arg, "-b")) {
            state.build_only = true;
        } else if (util.eql(arg, "--profile") or util.eql(arg, "-p")) {
            if (i + 1 < args.len) {
                state.profile = args[i + 1];
                i += 1;
            }
        } else if (util.eql(arg, "--select-image") or util.eql(arg, "-i")) {
            state.select_image = true;
        } else if (util.eql(arg, "--wizard") or util.eql(arg, "-w")) {
            state.wizard = true;
        } else if (util.eql(arg, "--wizard-batch") or util.eql(arg, "-ww")) {
            state.wizard_batch = true;
        } else if (util.eql(arg, "--context") or util.eql(arg, "-c")) {
            const val = if (i + 1 < args.len) args[i + 1] else "";
            if (!app.addContextDir(a, paths.home, &state, val)) std.process.exit(1);
            i += 1;
        } else if (std.mem.startsWith(u8, arg, "--context=")) {
            if (!app.addContextDir(a, paths.home, &state, arg["--context=".len..])) std.process.exit(1);
        } else if (util.eql(arg, "--safe")) {
            state.safe_mode = true;
        } else if (util.eql(arg, "--resume") or util.eql(arg, "-r")) {
            state.do_resume = true;
        } else if (util.eql(arg, "--shell") or util.eql(arg, "-s")) {
            state.shell_only = true;
        } else if (util.eql(arg, "--tailscale") or util.eql(arg, "-t")) {
            state.tailscale = true;
        } else if (util.eql(arg, "--exit-node")) {
            if (i + 1 < args.len) {
                state.exit_node = args[i + 1];
                i += 1;
            }
        } else if (std.mem.startsWith(u8, arg, "--exit-node=")) {
            state.exit_node = arg["--exit-node=".len..];
        } else if (util.eql(arg, "--verbose") or util.eql(arg, "-v")) {
            state.verbose = true;
        }
        // Unknown args are ignored, matching the bash case default.
    }

    // ── Wizard ───────────────────────────────────────────────────────────────
    if (state.wizard_batch) {
        wizard.runBatch(a, paths, paths.home, &state);
    } else if (state.wizard) {
        wizard.run(a, paths, paths.home, &state);
    }

    // ── Validate --exit-node requires --tailscale ────────────────────────────
    if (state.exit_node.len > 0 and !state.tailscale) {
        util.out("Error: --exit-node requires --tailscale.\n");
        util.out("\n");
        util.out("Usage: claudeinjail --tailscale --exit-node=<node>\n");
        std.process.exit(1);
    }

    // ── Normal flow: validate + build + run ──────────────────────────────────
    run.validateProfile(a, paths, &state);
    if (state.select_image) state.image = images.selectImage(a, paths);
    run.buildImage(a, paths, state.image);

    if (state.build_only) {
        util.out("\n");
        util.out("Build complete.\n");
        std.process.exit(0);
    }

    run.resolveProfile(a, paths, &state);

    if (state.profile.len == 0) {
        util.out("Error: empty profile name.\n");
        std.process.exit(1);
    }

    const profile_dir = paths.profileDir(a, state.profile);
    util.mkdirAll(util.join(a, &.{ profile_dir, ".claude" }));
    const claude_json = util.join(a, &.{ profile_dir, ".claude.json" });
    if (!util.fileExists(claude_json)) util.writeOrDie(a, claude_json, "{}\n");

    util.out("\n");
    util.outf(a, "Profile:     {s}\n", .{state.profile});
    util.outf(a, "Configs at:  {s}\n", .{profile_dir});
    if (state.context_paths.items.len > 0) {
        util.out("Context:\n");
        for (state.context_names.items, state.context_paths.items) |name, path| {
            util.outf(a, "  /context/{s}  <-  {s}  (ro)\n", .{ name, path });
        }
    }
    util.out("\n");

    const instance = util.generateInstanceName(a);
    const gitconfig = run.generateGitconfig(a, instance);

    // ── Assemble docker run argv ─────────────────────────────────────────────
    const cwd = std.process.getCwdAlloc(a) catch ".";
    const api_key = std.process.getEnvVarOwned(a, "ANTHROPIC_API_KEY") catch "";

    // Mount the current directory under the claude user's home, preserving its
    // name, and start the container in it.
    const container_workdir = util.fmt(a, "/home/claude/{s}", .{std.fs.path.basename(cwd)});

    var argv = std.ArrayList([]const u8){};
    const add = struct {
        fn one(al: std.mem.Allocator, list: *std.ArrayList([]const u8), s: []const u8) void {
            util.push(al, list, s);
        }
    }.one;

    add(a, &argv, "docker");
    add(a, &argv, "run");
    add(a, &argv, "--rm");
    add(a, &argv, "-it");
    add(a, &argv, "--name");
    add(a, &argv, instance);
    add(a, &argv, "-e");
    add(a, &argv, util.fmt(a, "ANTHROPIC_API_KEY={s}", .{api_key}));
    add(a, &argv, "-v");
    add(a, &argv, util.fmt(a, "{s}:{s}", .{ cwd, container_workdir }));
    add(a, &argv, "-w");
    add(a, &argv, container_workdir);
    add(a, &argv, "-v");
    add(a, &argv, util.fmt(a, "{s}/.claude:/home/claude/.claude", .{profile_dir}));
    add(a, &argv, "-v");
    add(a, &argv, util.fmt(a, "{s}/.claude.json:/home/claude/.claude.json", .{profile_dir}));

    // git config + ssh keys
    if (util.fileExists(gitconfig)) {
        add(a, &argv, "-v");
        add(a, &argv, util.fmt(a, "{s}:/home/claude/.gitconfig:ro", .{gitconfig}));
    }
    const ssh_dir = util.join(a, &.{ paths.home, ".ssh" });
    if (util.dirExists(ssh_dir)) {
        add(a, &argv, "-v");
        add(a, &argv, util.fmt(a, "{s}:/home/claude/.ssh:ro", .{ssh_dir}));
    }

    // context mounts
    for (state.context_names.items, state.context_paths.items) |name, path| {
        add(a, &argv, "-v");
        add(a, &argv, util.fmt(a, "{s}:/context/{s}:ro", .{ path, name }));
    }

    // ── Tailscale ────────────────────────────────────────────────────────────
    if (state.tailscale) {
        const ts_dir = util.join(a, &.{ profile_dir, "tailscale" });
        util.mkdirAll(ts_dir);
        const authkey_file = util.join(a, &.{ ts_dir, "authkey" });

        var authkey: []const u8 = "";
        if (util.readFileTrimmed(a, authkey_file)) |k| authkey = k;

        if (authkey.len == 0) {
            util.out("\n");
            util.outf(a, "No Tailscale auth key found for profile '{s}'.\n", .{state.profile});
            util.out("\n");
            util.out("Generate a reusable auth key at:\n");
            util.out("  https://login.tailscale.com/admin/settings/keys\n");
            util.out("\n");
            util.out("Recommended settings:\n");
            util.out("  - Reusable: yes\n");
            util.out("  - Ephemeral: yes\n");
            util.out("\n");
            authkey = util.stripAllWs(a, util.prompt(a, "Paste your auth key: "));

            if (authkey.len == 0) {
                util.out("Error: auth key cannot be empty.\n");
                std.process.exit(1);
            }

            util.writeModeOrDie(a, authkey_file, util.fmt(a, "{s}\n", .{authkey}), 0o600);
            util.outf(a, "Auth key saved to {s}\n", .{authkey_file});
            util.out("\n");
        }

        util.mkdirAll(paths.cache_dir);
        const family = templates.detectImageFamily(a, paths, state.image.variant);
        const drop = if (util.eql(family, "alpine")) "su-exec claude" else "gosu claude";
        const entrypoint_path = util.join(a, &.{ paths.cache_dir, "entrypoint.sh" });
        util.writeModeOrDie(a, entrypoint_path, templates.entrypoint(a, drop), 0o755);

        add(a, &argv, "--cap-add=NET_ADMIN");
        add(a, &argv, "--cap-add=NET_RAW");
        add(a, &argv, "--device=/dev/net/tun:/dev/net/tun");
        add(a, &argv, "-v");
        add(a, &argv, util.fmt(a, "{s}:/entrypoint.sh:ro", .{entrypoint_path}));
        add(a, &argv, "-e");
        add(a, &argv, "TAILSCALE_ENABLED=true");
        add(a, &argv, "-e");
        add(a, &argv, util.fmt(a, "TS_AUTHKEY={s}", .{authkey}));
        add(a, &argv, "-e");
        add(a, &argv, util.fmt(a, "TS_HOSTNAME={s}", .{instance}));
        add(a, &argv, "--entrypoint");
        add(a, &argv, "/entrypoint.sh");

        if (state.exit_node.len > 0) {
            add(a, &argv, "-e");
            add(a, &argv, util.fmt(a, "TS_EXIT_NODE={s}", .{state.exit_node}));
        }
        if (state.verbose) {
            add(a, &argv, "-e");
            add(a, &argv, "TS_VERBOSE=true");
        }

        util.out("Tailscale:   enabled\n");
        util.outf(a, "Hostname:    {s}\n", .{instance});
        if (state.exit_node.len > 0) util.outf(a, "Exit node:   {s}\n", .{state.exit_node});
        util.out("\n");
    }

    // ── Drop-privileges command based on image family ────────────────────────
    const family = templates.detectImageFamily(a, paths, state.image.variant);
    const drop_privs = if (util.eql(family, "alpine")) "su-exec" else "gosu";

    // Flags forwarded to the Claude CLI inside the container
    var claude_flags = std.ArrayList([]const u8){};
    if (!state.safe_mode) util.push(a, &claude_flags, "--dangerously-skip-permissions");
    if (state.do_resume) util.push(a, &claude_flags, "--resume");

    // ── Image + container command ────────────────────────────────────────────
    add(a, &argv, state.image.name);

    if (state.shell_only) {
        add(a, &argv, "/bin/bash");
        util.outf(a, "Starting shell in container ({s})...\n", .{state.image.name});
        util.out("\n");
    } else if (state.tailscale) {
        add(a, &argv, "claude");
        for (claude_flags.items) |f| add(a, &argv, f);
    } else {
        add(a, &argv, drop_privs);
        add(a, &argv, "claude");
        add(a, &argv, "claude");
        for (claude_flags.items) |f| add(a, &argv, f);
    }

    // Debug hook: print the assembled command instead of executing it.
    if (std.process.hasEnvVarConstant("CLAUDEINJAIL_DRYRUN")) {
        for (argv.items, 0..) |t, idx| {
            if (idx != 0) util.out(" ");
            util.out(t);
        }
        util.out("\n");
        return;
    }

    util.execv(a, argv.items);
}
