const std = @import("std");
const util = @import("util.zig");
const config = @import("config.zig");

pub const help_text = @embedFile("templates/help.txt");

pub const dockerfile_alpine = @embedFile("templates/alpine.dockerfile");
pub const dockerfile_debian = @embedFile("templates/debian.dockerfile");
pub const dockerfile_alpine_node = @embedFile("templates/alpine-node.dockerfile");
pub const dockerfile_debian_node = @embedFile("templates/debian-node.dockerfile");

pub const entrypoint_head = @embedFile("templates/entrypoint-head.sh");

/// Returns the built-in Dockerfile body for a variant, or null if not built-in.
pub fn dockerfileForVariant(variant: []const u8) ?[]const u8 {
    if (util.eql(variant, "alpine")) return dockerfile_alpine;
    if (util.eql(variant, "debian")) return dockerfile_debian;
    if (util.eql(variant, "alpine-node")) return dockerfile_alpine_node;
    if (util.eql(variant, "debian-node")) return dockerfile_debian_node;
    return null;
}

pub fn variantBaseLabel(variant: []const u8) []const u8 {
    if (util.eql(variant, "alpine")) return "Alpine (alpine:3)";
    if (util.eql(variant, "debian")) return "Debian (debian:12-slim)";
    if (util.eql(variant, "alpine-node")) return "Alpine + Node.js + Bun (node:lts-alpine)";
    if (util.eql(variant, "debian-node")) return "Debian + Node.js + Bun (node:lts-slim)";
    return variant;
}

/// Mirrors detect_image_family: returns "alpine" or "debian".
/// For custom:<name>, inspects the FROM line of the custom Dockerfile.
pub fn detectImageFamily(a: std.mem.Allocator, paths: config.Paths, variant: []const u8) []const u8 {
    if (util.eql(variant, "alpine") or util.eql(variant, "alpine-node")) return "alpine";
    if (util.eql(variant, "debian") or util.eql(variant, "debian-node")) return "debian";
    if (!std.mem.startsWith(u8, variant, "custom:")) return "debian";

    const cname = variant["custom:".len..];
    const content = util.readFile(a, paths.imageDockerfile(a, cname)) orelse return "debian";

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const t = util.trimWs(line);
        if (!std.ascii.startsWithIgnoreCase(t, "from ")) continue;
        if (std.ascii.indexOfIgnoreCase(t, "alpine") != null) return "alpine";
        return "debian";
    }
    return "debian";
}

/// Builds the entrypoint script for a drop-privileges command
/// (e.g. "su-exec claude" or "gosu claude").
pub fn entrypoint(a: std.mem.Allocator, drop_privs: []const u8) []u8 {
    return util.fmt(a, "{s}exec {s} \"$@\"\n", .{ entrypoint_head, drop_privs });
}
