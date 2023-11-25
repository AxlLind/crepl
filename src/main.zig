const std = @import("std");

const clang = @cImport(@cInclude("clang-c/Index.h"));
const SOURCE = @embedFile("./source.c");
const TMPFILE = "/tmp/crepl.c";
const BINFILE = "/tmp/crepl.bin";

const Command = enum {
    printSource,
    quit,

    const mapping = [_]struct { []const []const u8, Command }{
        .{ &.{"print_source"}, .printSource },
        .{ &.{ "q", "quit" }, .quit },
    };

    fn parse(s: []const u8) ?Command {
        for (mapping) |t| {
            for (t.@"0") |cmd| {
                if (std.mem.eql(u8, s, cmd))
                    return t.@"1";
            }
        }
        return null;
    }
};

fn expr_print_str(expr: []const u8, tpe: c_uint, allocator: std.mem.Allocator) !?[]const u8 {
    const fmt = switch (tpe) {
        clang.CXType_Bool => "d",
        clang.CXType_UChar => "hhu",
        clang.CXType_UShort => "hu",
        clang.CXType_UInt => "u",
        clang.CXType_ULong => "lu",
        clang.CXType_ULongLong => "llu",
        clang.CXType_SChar => "hhd",
        clang.CXType_Short => "hd",
        clang.CXType_Int => "d",
        clang.CXType_Long => "ld",
        clang.CXType_LongLong => "lld",
        clang.CXType_Float => "f",
        clang.CXType_Double => "f",
        clang.CXType_LongDouble => "Lf",
        clang.CXType_Pointer => "p",
        else => return null,
    };
    return try std.fmt.allocPrint(allocator, "printf(\"%{s}\\n\", {s});", .{ fmt, std.mem.trimRight(u8, expr, ";") });
}

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

fn write_and_compile(src: []const u8, allocator: std.mem.Allocator) !std.ChildProcess.RunResult {
    var cfile = try std.fs.createFileAbsolute(TMPFILE, .{ .truncate = true });
    defer cfile.close();
    try cfile.writeAll(src);
    return std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = &.{ "gcc", TMPFILE, "-o", BINFILE },
    });
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
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer {
        arena.deinit();
        std.fs.deleteFileAbsolute(TMPFILE) catch {};
        std.fs.deleteFileAbsolute(BINFILE) catch {};
    }

    var includes = std.ArrayList([]u8).init(arena.allocator());
    var exprs = std.ArrayList([]u8).init(arena.allocator());

    const in = std.io.getStdIn();
    var r = std.io.bufferedReader(in.reader());
    var msg_buf: [4096]u8 = undefined;
    while (true) {
        std.debug.print(">> ", .{});
        const expr = r.reader().readUntilDelimiterOrEof(&msg_buf, '\n') catch break orelse break;

        var tmp_arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        var tmp_alloc = tmp_arena.allocator();
        defer tmp_arena.deinit();

        if (expr.len > 1 and expr[0] == ':') {
            const cmdstr = std.mem.trim(u8, expr[1..], " \t");
            const cmd = Command.parse(cmdstr) orelse {
                std.debug.print("Unrecognized builtin command '{s}'\n", .{cmdstr});
                continue;
            };
            switch (cmd) {
                .printSource => {
                    const src = try c_source(includes.items, exprs.items, "// next expr", tmp_alloc);
                    std.debug.print("{s}", .{src});
                },
                .quit => break,
            }
            continue;
        }

        const compile_result = try write_and_compile(
            try c_source(includes.items, exprs.items, expr, tmp_alloc),
            tmp_alloc,
        );
        if (compile_result.term.Exited != 0) {
            std.debug.print("{s}", .{compile_result.stderr});
            continue;
        }

        const index = clang.clang_createIndex(0, 0);
        defer clang.clang_disposeIndex(index);
        const unit = clang.clang_parseTranslationUnit(index, TMPFILE, null, 0, null, 0, 0);
        defer clang.clang_disposeTranslationUnit(unit);
        const main_fn_cursor = get_last_child(clang.clang_getTranslationUnitCursor(unit)) orelse unreachable;
        const main_block_cursor = get_last_child(main_fn_cursor) orelse unreachable;
        const new_expr_cursor = get_last_child(main_block_cursor) orelse unreachable;

        const kind = clang.clang_getCursorKind(new_expr_cursor);
        const tpe = clang.clang_getCursorType(new_expr_cursor);
        if (clang.clang_isExpression(kind) != 0) {
            if (try expr_print_str(expr, tpe.kind, tmp_alloc)) |s| {
                const comp_result = try write_and_compile(
                    try c_source(includes.items, exprs.items, s, tmp_alloc),
                    tmp_alloc,
                );
                if (comp_result.term.Exited != 0) {
                    std.debug.print("{s}", .{comp_result.stderr});
                    continue;
                }
            }
        }

        const run_result = try std.ChildProcess.run(.{
            .allocator = tmp_alloc,
            .argv = &.{BINFILE},
        });
        if (run_result.term.Exited != 0) {
            std.debug.print("Exited with {}!\n{s}", .{ run_result.term.Exited, run_result.stderr });
            continue;
        }

        std.debug.print("{s}", .{run_result.stdout});
        try exprs.append(try arena.allocator().dupe(u8, expr));
    }
    std.debug.print("\n", .{});
}
