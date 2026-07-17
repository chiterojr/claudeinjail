const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");
const templates = @import("templates.zig");

pub const Image = struct {
    name: []const u8 = config.default_image_name,
    variant: []const u8 = config.default_image_variant,
};

/// Port of validate_image_name: ^[a-z0-9][a-z0-9-]{1,}[a-z0-9]$ (min 3 chars).
pub fn validImageName(name: []const u8) bool {
    if (name.len < 3) return false;
    const isBody = struct {
        fn f(c: u8) bool {
            return (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-';
        }
    }.f;
    const isEdge = struct {
        fn f(c: u8) bool {
            return (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9');
        }
    }.f;
    if (!isEdge(name[0])) return false;
    if (!isEdge(name[name.len - 1])) return false;
    for (name[1 .. name.len - 1]) |c| if (!isBody(c)) return false;
    return true;
}

/// Reads the description embedded in a custom Dockerfile's first line, or null.
pub fn readDescription(a: std.mem.Allocator, dockerfile_path: []const u8) ?[]const u8 {
    const content = util.readFile(a, dockerfile_path) orelse return null;
    var lines = std.mem.splitScalar(u8, content, '\n');
    const first = lines.first();
    if (!std.mem.startsWith(u8, first, config.desc_prefix)) return null;
    var desc = first[config.desc_prefix.len..];
    desc = std.mem.trimLeft(u8, desc, " ");
    desc = std.mem.trimRight(u8, desc, "\r");
    return a.dupe(u8, desc) catch null;
}

/// Lists custom image names: sub-dirs of images_dir that contain a Dockerfile.
pub fn listCustom(a: std.mem.Allocator, paths: config.Paths) [][]u8 {
    const dirs = util.listDirs(a, paths.images_dir, null);
    var out = std.ArrayList([]u8){};
    for (dirs) |d| {
        if (util.fileExists(paths.imageDockerfile(a, d))) util.push(a, &out, d);
    }
    return util.owned(a, &out);
}

fn writeCustomImage(a: std.mem.Allocator, paths: config.Paths, name: []const u8, variant: []const u8, desc: []const u8) void {
    const dir = paths.imageDir(a, name);
    util.mkdirAll(dir);
    const body = templates.dockerfileForVariant(variant) orelse templates.dockerfile_alpine;
    const first_line = if (desc.len > 0)
        util.fmt(a, "{s} {s}\n", .{ config.desc_prefix, desc })
    else
        util.fmt(a, "{s}\n", .{config.desc_prefix});
    const content = util.fmt(a, "{s}{s}", .{ first_line, body });
    util.writeOrDie(a, paths.imageDockerfile(a, name), content);
}

// ── interactive prompts ─────────────────────────────────────────────────────

fn promptBaseVariant(a: std.mem.Allocator) []const u8 {
    util.out("\n");
    util.out("Select the base image.\n");
    util.out("Alpine is smaller and lighter; Debian has better compatibility with\n");
    util.out("conventional Linux tools. The Node.js+Bun variants include both JS runtimes.\n");
    util.out("\n");
    util.out("  1) Alpine (alpine:3)  [default]\n");
    util.out("  2) Debian (debian:12-slim)\n");
    util.out("  3) Alpine + Node.js + Bun (node:lts-alpine)\n");
    util.out("  4) Debian + Node.js + Bun (node:lts-slim)\n");
    const choice = util.prompt(a, "Choose [1/2/3/4]: ");
    if (util.eql(choice, "2")) return "debian";
    if (util.eql(choice, "3")) return "alpine-node";
    if (util.eql(choice, "4")) return "debian-node";
    return "alpine";
}

fn promptImageName(a: std.mem.Allocator, paths: config.Paths) []const u8 {
    while (true) {
        const raw = util.prompt(a, "Image name (lowercase, digits, hyphens; min 3 chars): ");
        const name = util.stripAllWs(a, util.toLower(a, raw));
        if (validImageName(name)) {
            if (util.fileExists(paths.imageDockerfile(a, name))) {
                util.outf(a, "An image named '{s}' already exists at {s}/\n", .{ name, paths.imageDir(a, name) });
                const ans = util.prompt(a, "Overwrite? [y/N]: ");
                if (!util.eql(ans, "y") and !util.eql(ans, "Y")) continue;
            }
            return name;
        }
        util.out("Invalid name. Use only [a-z0-9-], no leading/trailing hyphen, min 3 chars.\n");
    }
}

fn promptImageDescription(a: std.mem.Allocator) []const u8 {
    while (true) {
        const raw = util.prompt(a, "Short description (max 60 chars, may be empty): ");
        // collapse internal whitespace runs to a single space and trim.
        var toks = std.mem.tokenizeAny(u8, raw, " \t\r\n");
        var list = std.ArrayList(u8){};
        var first = true;
        while (toks.next()) |t| {
            if (!first) util.push(a, &list, ' ');
            util.pushSlice(a, &list, t);
            first = false;
        }
        const desc = util.owned(a, &list);
        if (desc.len <= 60) return desc;
        util.outf(a, "Description too long ({d} chars). Limit is 60.\n", .{desc.len});
    }
}

/// Maps a numeric image choice (1-4 built-ins, 5+ customs) to an Image. Empty
/// or "1" selects Alpine. Returns null on an invalid choice so callers can
/// apply their own fallback.
pub fn applyChoice(a: std.mem.Allocator, paths: config.Paths, choice: []const u8) ?Image {
    if (choice.len == 0) return .{ .name = "claudeinjail-alpine", .variant = "alpine" };

    const customs = listCustom(a, paths);
    const last = 4 + customs.len;

    const n = std.fmt.parseInt(usize, choice, 10) catch return null;
    if (n >= 5 and n <= last) {
        const picked = customs[n - 5];
        return .{
            .name = util.fmt(a, "claudeinjail-custom-{s}", .{picked}),
            .variant = util.fmt(a, "custom:{s}", .{picked}),
        };
    }
    return switch (n) {
        1 => .{ .name = "claudeinjail-alpine", .variant = "alpine" },
        2 => .{ .name = "claudeinjail-debian", .variant = "debian" },
        3 => .{ .name = "claudeinjail-alpine-node", .variant = "alpine-node" },
        4 => .{ .name = "claudeinjail-debian-node", .variant = "debian-node" },
        else => null,
    };
}

/// Port of select_image: prompts for the image, returns the chosen Image.
pub fn selectImage(a: std.mem.Allocator, paths: config.Paths) Image {
    const customs = listCustom(a, paths);

    util.out("\n");
    util.out("Select the container image.\n");
    util.out("Built-in bases ship with Claude Code preinstalled. Custom images are\n");
    util.out("previously ejected Dockerfiles you have customized.\n");
    util.out("\n");
    util.out("  1) Alpine (alpine:3)  [default]\n");
    util.out("  2) Debian (debian:12-slim)\n");
    util.out("  3) Alpine + Node.js + Bun (node:lts-alpine)\n");
    util.out("  4) Debian + Node.js + Bun (node:lts-slim)\n");

    var i: usize = 5;
    for (customs) |name| {
        const desc = readDescription(a, paths.imageDockerfile(a, name));
        if (desc != null and desc.?.len > 0) {
            util.outf(a, "  {d}) custom: {s} — {s}\n", .{ i, name, desc.? });
        } else {
            util.outf(a, "  {d}) custom: {s}\n", .{ i, name });
        }
        i += 1;
    }

    const last = i - 1;
    const choice = util.prompt(a, util.fmt(a, "Choose [1-{d}]: ", .{last}));

    // Invalid or out-of-range input falls back to the Alpine default.
    return applyChoice(a, paths, choice) orelse .{ .name = "claudeinjail-alpine", .variant = "alpine" };
}

// ── eject command ───────────────────────────────────────────────────────────

pub fn cmdEject(a: std.mem.Allocator, paths: config.Paths, name_arg: ?[]const u8) noreturn {
    util.mkdirAll(paths.images_dir);

    const name: []const u8 = blk: {
        if (name_arg == null or name_arg.?.len == 0) break :blk promptImageName(a, paths);

        const n = util.stripAllWs(a, util.toLower(a, name_arg.?));
        if (!validImageName(n)) {
            util.outf(a, "Error: invalid image name '{s}'.\n", .{n});
            util.out("Use only [a-z0-9-], no leading/trailing hyphen, min 3 chars.\n");
            std.process.exit(1);
        }
        if (util.fileExists(paths.imageDockerfile(a, n))) {
            util.outf(a, "An image named '{s}' already exists at {s}/\n", .{ n, paths.imageDir(a, n) });
            const ans = util.prompt(a, "Overwrite? [y/N]: ");
            if (!util.eql(ans, "y") and !util.eql(ans, "Y")) {
                util.out("Eject cancelled.\n");
                std.process.exit(0);
            }
        }
        break :blk n;
    };

    const desc = promptImageDescription(a);
    const variant = promptBaseVariant(a);

    writeCustomImage(a, paths, name, variant, desc);

    const dockerfile = paths.imageDockerfile(a, name);
    util.out("\n");
    util.outf(a, "Image '{s}' ejected.\n", .{name});
    util.out("\n");
    util.out("Dockerfile location:\n");
    util.outf(a, "  {s}\n", .{dockerfile});
    util.out("\n");
    util.outf(a, "Base: {s}\n", .{templates.variantBaseLabel(variant)});
    if (desc.len > 0) util.outf(a, "Description: {s}\n", .{desc});
    util.out("\n");
    util.out("You can edit this Dockerfile freely — add packages, tools, runtimes, etc.\n");
    util.out("\n");
    util.outf(a, "IMPORTANT: keep the first line ('{s} ...') intact.\n", .{config.desc_prefix});
    util.out("It is parsed by 'claudeinjail -i' to show the image description.\n");
    util.out("If you remove it, the image still works but loses its description label.\n");
    util.out("\n");
    util.out("To use this image on the next run, pick it via:\n");
    util.out("  claudeinjail -i\n");
    util.out("\n");
    util.out("To remove this image, delete its directory:\n");
    util.outf(a, "  rm -rf {s}\n", .{paths.imageDir(a, name)});
    std.process.exit(0);
}
