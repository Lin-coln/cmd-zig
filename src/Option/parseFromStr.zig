const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");
const Type = @import("Value.zig").Type;

pub fn parseFromStr(str: []const u8) struct { key: []const u8, alias: ?u8, type: Type } {
    const comma = std.mem.indexOfScalar(u8, str, ',');
    const long = std.mem.trim(u8, if (comma) |idx| str[idx + 1 ..] else str, " \t");
    if (std.mem.indexOfScalar(u8, long, ',') != null) @compileError("Invalid option format");

    const descriptor = Args.OptionDescriptor.parseFromArg(long) orelse @compileError("Invalid option format");
    const key = switch (descriptor.identity) {
        .key => |value| value,
        .alias => @compileError("Invalid option format"),
    };
    if (std.mem.indexOfAny(u8, key, " \t\r\n") != null) @compileError("Invalid option format");

    const kind: Type = if (descriptor.value) |placeholder| blk: {
        if (placeholder.len < 3 or placeholder[0] != '<' or placeholder[placeholder.len - 1] != '>')
            @compileError("Invalid option format");
        if (std.mem.indexOfAny(u8, placeholder[1 .. placeholder.len - 1], "<> \t\r\n") != null)
            @compileError("Invalid option format");
        break :blk .string;
    } else .boolean;

    const alias: ?u8 = if (comma) |idx| blk: {
        const short = std.mem.trim(u8, str[0..idx], " \t");
        const short_descriptor = Args.OptionDescriptor.parseFromArg(short) orelse @compileError("Invalid option format");
        if (short_descriptor.value != null) @compileError("Invalid option format");
        break :blk switch (short_descriptor.identity) {
            .alias => |value| value,
            .key => @compileError("Invalid option format"),
        };
    } else null;

    return .{ .key = key, .alias = alias, .type = kind };
}

test "parseFromStr: parses names, aliases, and value placeholders" {
    const cases = [_]struct { source: []const u8, key: []const u8, alias: ?u8, kind: Type }{
        .{ .source = "--help", .key = "help", .alias = null, .kind = .boolean },
        .{ .source = "-h, --help", .key = "help", .alias = 'h', .kind = .boolean },
        .{ .source = "-m, --mode=<val>", .key = "mode", .alias = 'm', .kind = .string },
        .{ .source = "-c, --count=<val>", .key = "count", .alias = 'c', .kind = .string },
    };
    inline for (cases) |case| {
        const parsed = comptime parseFromStr(case.source);
        try t.expectEqualStrings(case.key, parsed.key);
        try t.expectEqual(case.alias, parsed.alias);
        try t.expectEqual(case.kind, parsed.type);
    }
}
