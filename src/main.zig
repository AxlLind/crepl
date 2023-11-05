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

fn compile_cfile(path: []const u8, binpath: []const u8, allocator: std.mem.Allocator) anyerror!std.process.Child.RunResult {
    return try std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "gcc", path, "-o", binpath },
    });
}

fn run_binary(path: []const u8, allocator: std.mem.Allocator) anyerror!std.process.Child.RunResult {
    return try std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{path},
    });
}

fn installSignalHandler() !void {
    const internal_handler = struct {
        fn handle(sig: c_int) callconv(.C) void {
            if (sig != std.os.SIG.INT) {
                std.process.exit(1);
            }
            std.debug.print("Use Ctrl+D to exit...\n>> ", .{});
        }
    };
    const action = std.os.Sigaction{
        .handler = .{ .handler = internal_handler.handle },
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
        for ([_][]const u8{ TMPFILE, BINFILE }) |file| {
            std.fs.deleteFileAbsolute(file) catch {};
        }
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

        const csrc = try c_source(includes.items, exprs.items, msg, std.heap.page_allocator);
        defer std.heap.page_allocator.free(csrc);

        try cfile.seekTo(0);
        try cfile.writeAll(csrc);
        const compile_result = try compile_cfile(TMPFILE, BINFILE, std.heap.page_allocator);
        defer std.heap.page_allocator.free(compile_result.stderr);
        defer std.heap.page_allocator.free(compile_result.stdout);

        if (compile_result.term.Exited != 0) {
            std.debug.print("{s}\n", .{compile_result.stderr});
            continue;
        }

        const run_result = try run_binary(BINFILE, std.heap.page_allocator);
        defer std.heap.page_allocator.free(run_result.stderr);
        defer std.heap.page_allocator.free(run_result.stdout);
        if (run_result.term.Exited != 0) {
            std.debug.print("Exited with {}!\n", .{run_result.term.Exited});
            if (run_result.stderr.len > 0) {
                std.debug.print("{s}\n", .{run_result.stderr});
            }
            continue;
        }

        std.debug.print("{s}", .{run_result.stdout});
        try exprs.append(try arena.allocator().dupe(u8, msg));
    }

    std.debug.print("\n", .{});
}
