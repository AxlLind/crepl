const std = @import("std");

const SOURCE = @embedFile("./source.c");

fn c_source(
    includes: []const []const u8,
    exprs: []const []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    const include_str = try std.mem.join(allocator, "\n", includes);
    defer allocator.free(include_str);
    const expr_str = try std.mem.join(allocator, "\n  ", exprs);
    defer allocator.free(expr_str);
    return std.fmt.allocPrint(allocator, SOURCE, .{ include_str, expr_str });
}

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;
    const child = try std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "echo", "hello", "world" },
    });
    std.debug.print("Child output: {s}", .{child.stdout});
    allocator.free(child.stdout);
    allocator.free(child.stderr);

    const in = std.io.getStdIn();
    var buf = std.io.bufferedReader(in.reader());
    var r = buf.reader();

    var includes = std.ArrayList([]u8).init(allocator);
    defer {
        for (includes.items) |include| {
            allocator.free(include);
        }
        includes.deinit();
    }
    var exprs = std.ArrayList([]u8).init(allocator);
    defer {
        for (exprs.items) |expr| {
            allocator.free(expr);
        }
        exprs.deinit();
    }

    var msg_buf: [4096]u8 = undefined;
    while (true) {
        std.debug.print(">> ", .{});
        var msg = try r.readUntilDelimiterOrEof(&msg_buf, '\n') orelse break;
        std.debug.print("Got: {s}\n", .{msg});
        try exprs.append(try allocator.dupe(u8, msg));
    }
    std.debug.print("\n", .{});
    std.debug.print("includes:\n", .{});
    for (includes.items) |include| {
        std.debug.print("{s}\n", .{include});
    }
    std.debug.print("exprs:\n", .{});
    for (exprs.items) |expr| {
        std.debug.print("{s}\n", .{expr});
    }
}
