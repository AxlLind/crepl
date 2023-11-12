const std = @import("std");

const clang = @cImport(@cInclude("clang-c/Index.h"));
const SOURCE = @embedFile("./source.c");
const TMPFILE = "/tmp/crepl.c";
const BINFILE = "/tmp/crepl.bin";

fn get_last_child(c: clang.CXCursor) ?clang.CXCursor {
    const f = struct {
        pub fn visit(cursor: clang.CXCursor, _: clang.CXCursor, data: clang.CXClientData) callconv(.C) clang.enum_CXChildVisitResult {
            @as(*?clang.CXCursor, @ptrCast(@alignCast(data orelse unreachable))).* = cursor;
            return clang.CXVisit_Continue;
        }
    }.visit;
    var res: ?clang.CXCursor = null;
    _ = clang.clang_visitChildren(c, f, &res);
    return res;
}

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

fn sig_handler(_: c_int) callconv(.C) void {
    std.os.close(std.os.STDIN_FILENO);
}

pub fn main() anyerror!void {
    try std.os.sigaction(std.os.SIG.INT, &.{
        .handler = .{ .handler = sig_handler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    }, null);
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
        var msg = r.readUntilDelimiterOrEof(&msg_buf, '\n') catch break orelse break;

        var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer tmp_arena.deinit();

        try cfile.seekTo(0);
        try cfile.writeAll(try c_source(includes.items, exprs.items, msg, tmp_arena.allocator()));
        const compile_result = try std.ChildProcess.run(.{
            .allocator = tmp_arena.allocator(),
            .argv = &.{ "gcc", TMPFILE, "-o", BINFILE },
        });
        if (compile_result.term.Exited != 0) {
            std.debug.print("{s}", .{compile_result.stderr});
            continue;
        }

        var index = clang.clang_createIndex(0, 0);
        defer clang.clang_disposeIndex(index);
        var unit = clang.clang_parseTranslationUnit(index, TMPFILE, null, 0, null, 0, 0);
        defer clang.clang_disposeTranslationUnit(unit);
        var main_fn_cursor = get_last_child(clang.clang_getTranslationUnitCursor(unit)) orelse unreachable;
        var main_block_cursor = get_last_child(main_fn_cursor) orelse unreachable;
        var new_expr_cursor = get_last_child(main_block_cursor) orelse unreachable;

        var name = std.mem.span(clang.clang_getCString(clang.clang_getCursorSpelling(new_expr_cursor)));
        var cursor_kind = clang.clang_getCString(clang.clang_getTypeKindSpelling(clang.clang_getCursorKind(new_expr_cursor)));
        var kind = if (cursor_kind == null) "" else std.mem.span(cursor_kind);
        var tpe = std.mem.span(clang.clang_getCString(clang.clang_getTypeKindSpelling(clang.clang_getCursorType(new_expr_cursor).kind)));
        std.debug.print("found '{s}': kind={s}, tpe={s}, is_expr={}\n", .{ name, kind, tpe, clang.clang_isExpression(clang.clang_getCursorKind(new_expr_cursor)) != 0 });

        const run_result = try std.ChildProcess.run(.{
            .allocator = tmp_arena.allocator(),
            .argv = &.{BINFILE},
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
