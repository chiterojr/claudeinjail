const std = @import("std");

// ── allocation helpers ──────────────────────────────────────────────────────
//
// Everything runs on a process-lifetime arena, so the only possible allocation
// error is OOM, which is fatal. These helpers make that explicit with a clean
// `@panic` (defined behavior in every optimize mode) instead of `unreachable`
// (which is UB in release builds) or a silent `catch {}`.

pub fn fmt(a: std.mem.Allocator, comptime f: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(a, f, args) catch @panic("out of memory");
}

pub fn join(a: std.mem.Allocator, parts: []const []const u8) []u8 {
    return std.fs.path.join(a, parts) catch @panic("out of memory");
}

pub fn dupe(a: std.mem.Allocator, s: []const u8) []u8 {
    return a.dupe(u8, s) catch @panic("out of memory");
}

/// Appends to a `*std.ArrayList(T)`, panicking on OOM.
pub fn push(a: std.mem.Allocator, list: anytype, item: anytype) void {
    list.append(a, item) catch @panic("out of memory");
}

/// Appends a slice to a `*std.ArrayList(T)`, panicking on OOM.
pub fn pushSlice(a: std.mem.Allocator, list: anytype, items: anytype) void {
    list.appendSlice(a, items) catch @panic("out of memory");
}

/// Takes ownership of the backing slice of a `*std.ArrayList(T)`, panicking on OOM.
pub fn owned(a: std.mem.Allocator, list: anytype) @TypeOf(list.items) {
    return list.toOwnedSlice(a) catch @panic("out of memory");
}

// ── stdout / stderr ─────────────────────────────────────────────────────────

pub fn out(bytes: []const u8) void {
    // best-effort: a closed stdout (broken pipe) is not worth aborting over.
    // zlint-disable-next-line suppressed-errors
    std.fs.File.stdout().writeAll(bytes) catch {};
}

pub fn outf(a: std.mem.Allocator, comptime f: []const u8, args: anytype) void {
    out(fmt(a, f, args));
}

pub fn err(bytes: []const u8) void {
    // best-effort, same rationale as `out`.
    // zlint-disable-next-line suppressed-errors
    std.fs.File.stderr().writeAll(bytes) catch {};
}

pub fn errf(a: std.mem.Allocator, comptime f: []const u8, args: anytype) void {
    err(fmt(a, f, args));
}

// ── stdin (single shared reader to avoid dropping buffered input) ────────────

var stdin_buf: [8192]u8 = undefined;
var stdin_reader: ?std.fs.File.Reader = null;

fn stdinInterface() *std.Io.Reader {
    if (stdin_reader == null) {
        stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    }
    return &stdin_reader.?.interface;
}

/// Reads one line from stdin (without the trailing newline). Returns null on EOF.
/// The returned slice is owned by the caller-provided allocator.
pub fn readLine(a: std.mem.Allocator) ?[]u8 {
    const r = stdinInterface();
    const line = (r.takeDelimiter('\n') catch return null) orelse return null;
    const trimmed = std.mem.trimRight(u8, line, "\r");
    return dupe(a, trimmed);
}

/// Prints a prompt to stdout and reads a line. Returns "" on EOF.
pub fn prompt(a: std.mem.Allocator, text: []const u8) []u8 {
    out(text);
    return readLine(a) orelse dupe(a, "");
}

// ── subprocess ──────────────────────────────────────────────────────────────

pub const CaptureResult = struct {
    stdout: []u8,
    stderr: []u8,
    code: u8, // 255 if it did not exit normally
};

/// Runs a command capturing stdout/stderr. Returns null if it could not spawn.
pub fn capture(a: std.mem.Allocator, argv: []const []const u8) ?CaptureResult {
    const res = std.process.Child.run(.{ .allocator = a, .argv = argv }) catch return null;
    const code: u8 = switch (res.term) {
        .Exited => |c| c,
        else => 255,
    };
    return .{ .stdout = res.stdout, .stderr = res.stderr, .code = code };
}

/// Runs a command with inherited stdio (interactive). Returns the exit code,
/// or 255 if it could not spawn / did not exit normally.
pub fn run(a: std.mem.Allocator, argv: []const []const u8) u8 {
    var child = std.process.Child.init(argv, a);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = child.spawnAndWait() catch return 255;
    return switch (term) {
        .Exited => |c| c,
        else => 255,
    };
}

/// Replaces the current process with the given command (like exec).
pub fn execv(a: std.mem.Allocator, argv: []const []const u8) noreturn {
    const e = std.process.execv(a, argv);
    errf(a, "Error: failed to exec {s}: {s}\n", .{ argv[0], @errorName(e) });
    std.process.exit(1);
}

/// Returns true if `name` is found as an executable in PATH.
pub fn commandExists(a: std.mem.Allocator, name: []const u8) bool {
    const path = std.process.getEnvVarOwned(a, "PATH") catch return false;
    defer a.free(path);
    var it = std.mem.tokenizeScalar(u8, path, ':');
    while (it.next()) |dir| {
        const full = std.fs.path.join(a, &.{ dir, name }) catch continue;
        defer a.free(full);
        const st = std.fs.cwd().statFile(full) catch continue;
        if (st.kind == .file or st.kind == .sym_link) return true;
    }
    return false;
}

// ── filesystem ──────────────────────────────────────────────────────────────

pub fn fileExists(path: []const u8) bool {
    const st = std.fs.cwd().statFile(path) catch return false;
    return st.kind == .file or st.kind == .sym_link;
}

pub fn dirExists(path: []const u8) bool {
    const st = std.fs.cwd().statFile(path) catch return false;
    return st.kind == .directory;
}

fn warnFsOp(op: []const u8, path: []const u8, e: anyerror) void {
    // stderr warning without an allocator (formatted into a stack buffer).
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "warning: failed to {s} {s}: {s}\n", .{ op, path, @errorName(e) }) catch {
        err("warning: a filesystem operation failed\n");
        return;
    };
    err(msg);
}

pub fn mkdirAll(path: []const u8) void {
    // makePath treats an existing dir as success; any other error is worth a warning
    // (a subsequent write to the same location will fail loudly anyway).
    std.fs.cwd().makePath(path) catch |e| warnFsOp("create directory", path, e);
}

pub fn removeTree(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch |e| warnFsOp("remove", path, e);
}

pub fn removeFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch |e| {
        if (e == error.FileNotFound) return; // mirrors `rm -f`
        warnFsOp("remove", path, e);
    };
}

/// Writes bytes to a file (creating/truncating), with the given mode.
pub fn writeFileMode(path: []const u8, bytes: []const u8, mode: std.fs.File.Mode) !void {
    var f = try std.fs.cwd().createFile(path, .{ .mode = mode });
    defer f.close();
    try f.writeAll(bytes);
}

/// Writes a file, aborting the program with an error message on failure.
pub fn writeOrDie(a: std.mem.Allocator, path: []const u8, bytes: []const u8) void {
    writeModeOrDie(a, path, bytes, 0o644);
}

/// Writes a file with an explicit mode, aborting with an error message on failure.
pub fn writeModeOrDie(a: std.mem.Allocator, path: []const u8, bytes: []const u8, mode: std.fs.File.Mode) void {
    writeFileMode(path, bytes, mode) catch |e| {
        errf(a, "Error: failed to write {s}: {s}\n", .{ path, @errorName(e) });
        std.process.exit(1);
    };
}

/// Reads a whole file. Returns null on error (missing, etc.).
pub fn readFile(a: std.mem.Allocator, path: []const u8) ?[]u8 {
    return std.fs.cwd().readFileAlloc(a, path, 16 * 1024 * 1024) catch null;
}

/// Reads a file and returns it trimmed of surrounding whitespace, or null.
pub fn readFileTrimmed(a: std.mem.Allocator, path: []const u8) ?[]u8 {
    const raw = readFile(a, path) orelse return null;
    return dupe(a, std.mem.trim(u8, raw, " \t\r\n"));
}

/// Returns the sorted list of immediate sub-directory names of `path`,
/// optionally excluding one name. Empty list if the dir cannot be opened.
pub fn listDirs(a: std.mem.Allocator, path: []const u8, exclude: ?[]const u8) [][]u8 {
    var names = std.ArrayList([]u8){};
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return &.{};
    defer dir.close();
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        if (exclude) |ex| if (std.mem.eql(u8, entry.name, ex)) continue;
        push(a, &names, dupe(a, entry.name));
    }
    const slice = owned(a, &names);
    std.mem.sort([]u8, slice, {}, lessThanStr);
    return slice;
}

fn lessThanStr(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}

// ── string helpers ──────────────────────────────────────────────────────────

pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn trimWs(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

/// Removes all whitespace characters from `s` (like `tr -d '[:space:]'`).
pub fn stripAllWs(a: std.mem.Allocator, s: []const u8) []u8 {
    var list = std.ArrayList(u8){};
    for (s) |c| {
        if (!std.ascii.isWhitespace(c)) push(a, &list, c);
    }
    return owned(a, &list);
}

pub fn toLower(a: std.mem.Allocator, s: []const u8) []u8 {
    const buf = dupe(a, s);
    for (buf) |*c| c.* = std.ascii.toLower(c.*);
    return buf;
}

// ── name helpers (ports of sanitize_name / generate_instance_name) ──────────

/// Keeps only [a-zA-Z0-9_-] (like `tr -cd 'a-zA-Z0-9_-'`).
pub fn sanitizeName(a: std.mem.Allocator, s: []const u8) []u8 {
    var list = std.ArrayList(u8){};
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') push(a, &list, c);
    }
    return owned(a, &list);
}

/// Port of generate_instance_name: "claudeinjail-<cwd-basename>-<pid>",
/// lowercased, non [a-z0-9-] collapsed to '-', squeezed, trimmed, max 63 chars.
pub fn generateInstanceName(a: std.mem.Allocator) []u8 {
    const cwd = std.process.getCwdAlloc(a) catch dupe(a, "workspace");
    const base = std.fs.path.basename(cwd);
    const pid = std.os.linux.getpid();
    const raw = fmt(a, "claudeinjail-{s}-{d}", .{ base, pid });

    var list = std.ArrayList(u8){};
    var prev_dash = false;
    for (raw) |c| {
        const lc = std.ascii.toLower(c);
        const keep = (lc >= 'a' and lc <= 'z') or (lc >= '0' and lc <= '9') or lc == '-';
        const out_c: u8 = if (keep) lc else '-';
        if (out_c == '-') {
            if (prev_dash) continue; // squeeze consecutive dashes
            prev_dash = true;
        } else {
            prev_dash = false;
        }
        push(a, &list, out_c);
    }
    var result = owned(a, &list);
    // strip leading/trailing dashes
    result = @constCast(std.mem.trim(u8, result, "-"));
    if (result.len > 63) result = result[0..63];
    return result;
}
