const std = @import("std");
const util = @import("util.zig");

pub const desc_prefix = "# claudeinjail-description:";
pub const default_image_name = "claudeinjail-alpine";
pub const default_image_variant = "alpine";

/// Resolved host paths, computed once from $HOME.
pub const Paths = struct {
    home: []const u8,
    config_dir: []const u8, // ~/.config/claudeinjail
    cache_dir: []const u8, // ~/.cache/claudeinjail
    default_file: []const u8, // config_dir/default
    images_dir: []const u8, // config_dir/images

    pub fn init(a: std.mem.Allocator) !Paths {
        const home = std.process.getEnvVarOwned(a, "HOME") catch {
            util.err("Error: HOME environment variable is not set.\n");
            return error.NoHome;
        };
        const config_dir = util.join(a, &.{ home, ".config", "claudeinjail" });
        const cache_dir = util.join(a, &.{ home, ".cache", "claudeinjail" });
        return .{
            .home = home,
            .config_dir = config_dir,
            .cache_dir = cache_dir,
            .default_file = util.join(a, &.{ config_dir, "default" }),
            .images_dir = util.join(a, &.{ config_dir, "images" }),
        };
    }

    pub fn profileDir(self: Paths, a: std.mem.Allocator, name: []const u8) []const u8 {
        return util.join(a, &.{ self.config_dir, name });
    }

    pub fn imageDir(self: Paths, a: std.mem.Allocator, name: []const u8) []const u8 {
        return util.join(a, &.{ self.images_dir, name });
    }

    pub fn imageDockerfile(self: Paths, a: std.mem.Allocator, name: []const u8) []const u8 {
        return util.join(a, &.{ self.images_dir, name, "Dockerfile" });
    }
};
