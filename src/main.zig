const std = @import("std");

pub fn main() anyerror!void {
    const child = try std.ChildProcess.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "echo", "hello", "world" },
    });
    std.debug.print("Child output: {s}", .{child.stdout});

    const in = std.io.getStdIn();
    var buf = std.io.bufferedReader(in.reader());
    var r = buf.reader();

    var msg_buf: [4096]u8 = undefined;
    while (true) {
        std.debug.print(">> ", .{});
        var msg = try r.readUntilDelimiterOrEof(&msg_buf, '\n');
        if (msg) |m| {
            std.debug.print("Got: {s}\n", .{m});
        }
    }
}
