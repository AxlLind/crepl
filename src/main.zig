const std = @import("std");

const SOURCE = @embedFile("./source.c");
const TMPFILE = "/tmp/crepl.c";
const BINFILE = "/tmp/crepl.bin";

fn c_source(
    includes: []const []const u8,
    exprs: []const []const u8,
    expr: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const include_str = try std.mem.join(allocator, "\n", includes);
    defer allocator.free(include_str);
    const expr_str = try std.mem.join(allocator, "\n  ", exprs);
    defer allocator.free(expr_str);
    return std.fmt.allocPrint(allocator, SOURCE, .{ .includes = include_str, .exprs = expr_str, .expr = expr });
}

fn sig_handler(sig: c_int) callconv(.C) void {
    if (sig != std.os.SIG.INT) {
        std.process.exit(1);
    }
    std.debug.print("Use Ctrl+D to exit...\n>> ", .{});
}

fn installSignalHandler() !void {
    const action = std.os.Sigaction{
        .handler = .{ .handler = sig_handler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.INT, &action, null);
}

pub fn main() anyerror!void {
    try installSignalHandler();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var cfile = try std.fs.createFileAbsolute(TMPFILE, .{});
    defer {
        cfile.close();
        std.fs.deleteFileAbsolute(TMPFILE) catch {};
        std.fs.deleteFileAbsolute(BINFILE) catch {};
    }

    var includes = std.ArrayList([]u8).init(arena.allocator());
    var exprs = std.ArrayList([]u8).init(arena.allocator());

    const in = std.io.getStdIn();
    var buf = std.io.bufferedReader(in.reader());
    var r = buf.reader();
    var msg_buf: [4096]u8 = undefined;
    while (true) {
        std.debug.print(">> ", .{});
        var msg = try r.readUntilDelimiterOrEof(&msg_buf, '\n') orelse break;

        var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer tmp_arena.deinit();

        try cfile.seekTo(0);
        try cfile.writeAll(try c_source(includes.items, exprs.items, msg, tmp_arena.allocator()));
        const compile_result = try std.ChildProcess.run(.{
            .allocator = tmp_arena.allocator(),
            .argv = &[_][]const u8{ "gcc", TMPFILE, "-o", BINFILE },
        });
        if (compile_result.term.Exited != 0) {
            std.debug.print("{s}", .{compile_result.stderr});
            continue;
        }

        const run_result = try std.ChildProcess.run(.{
            .allocator = tmp_arena.allocator(),
            .argv = &[_][]const u8{BINFILE},
        });
        if (run_result.term.Exited != 0) {
            std.debug.print("Exited with {}!\n{s}", .{ run_result.term.Exited, run_result.stderr });
            continue;
        }

        std.debug.print("{s}", .{run_result.stdout});
        try exprs.append(try arena.allocator().dupe(u8, msg));
    }
    std.debug.print("\n", .{});
}
