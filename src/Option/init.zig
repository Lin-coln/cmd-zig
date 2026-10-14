const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Value = Self.Value;
const Type = Self.Type;
const parseFromStr = @import("parseFromStr.zig").parseFromStr;

pub fn init(comptime str: []const u8, comptime opts: struct {
    desc: ?[]const u8 = null,
    type: ?Type = null,
    required: bool = false,
    default: ?Value = null,
}) Self {
    return comptime blk: {
        const parsed = parseFromStr(str);
        const kind = opts.type orelse parsed.type;
        if (opts.default) |value| {
            if (std.meta.activeTag(value) != kind) @compileError("Option default type does not match option type");
        }
        break :blk Self{
            .key = parsed.key,
            .alias = parsed.alias,
            .desc = opts.desc,
            .type = kind,
            .required = opts.required,
            .default = opts.default,
        };
    };
}

pub fn string(comptime str: []const u8) Self {
    return init(str, .{ .type = .string });
}

pub fn int(comptime str: []const u8) Self {
    return init(str, .{ .type = .int });
}

pub fn float(comptime str: []const u8) Self {
    return init(str, .{ .type = .float });
}

pub fn boolean(comptime str: []const u8) Self {
    return init(str, .{ .type = .boolean });
}

test "Option.init: uses the parsed type when no type is supplied" {
    const flag = Self.init("-h, --help", .{});
    try t.expectEqualStrings("help", flag.key);
    try t.expectEqual(@as(?u8, 'h'), flag.alias);
    try t.expectEqual(Type.boolean, flag.type);
    try t.expect(flag.desc == null);
    try t.expect(!flag.required);
    try t.expect(flag.default == null);

    const output = Self.init("--output=<val>", .{});
    try t.expectEqual(Type.string, output.type);
}

test "Option.init: applies explicit type, description, requirement, and default" {
    const count = Self.init("-c, --count=<val>", .{
        .desc = "Number of items",
        .type = .int,
        .required = true,
        .default = .{ .int = 5 },
    });
    try t.expectEqualStrings("count", count.key);
    try t.expectEqual(@as(?u8, 'c'), count.alias);
    try t.expectEqualStrings("Number of items", count.desc.?);
    try t.expectEqual(Type.int, count.type);
    try t.expect(count.required);
    try t.expectEqualDeep(Value{ .int = 5 }, count.default.?);
}

test "Option.string: parses a declaration and sets the string type" {
    const output = Self.string("-o, --output=<val>");
    try t.expectEqualStrings("output", output.key);
    try t.expectEqual(@as(?u8, 'o'), output.alias);
    try t.expectEqual(Type.string, output.type);

    const name = Self.string("--name");
    try t.expectEqual(Type.string, name.type);
}

test "Option.int: parses a declaration and sets the int type" {
    const count = Self.int("-c, --count=<val>");
    try t.expectEqualStrings("count", count.key);
    try t.expectEqual(@as(?u8, 'c'), count.alias);
    try t.expectEqual(Type.int, count.type);
}

test "Option.float: parses a declaration and sets the float type" {
    const ratio = Self.float("--ratio=<val>");
    try t.expectEqualStrings("ratio", ratio.key);
    try t.expectEqual(Type.float, ratio.type);
}

test "Option.boolean: parses a declaration and sets the boolean type" {
    const enabled = Self.boolean("--enabled=<val>");
    try t.expectEqualStrings("enabled", enabled.key);
    try t.expectEqual(Type.boolean, enabled.type);
}
