const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");
const Self = @import("Self.zig");
const Value = Self.Value;
const Type = Self.Type;

pub fn init(comptime str: []const u8) Self {
    return comptime parse(str);
}

pub fn int(comptime str: []const u8) Self {
    return comptime init(str).with(.{ .type = .int });
}

pub fn float(comptime str: []const u8) Self {
    return comptime init(str).with(.{ .type = .float });
}

pub fn boolean(comptime str: []const u8) Self {
    return comptime init(str).with(.{ .type = .boolean });
}

fn parse(str: []const u8) Self {
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

pub fn def(self: Self, value: ?Value) Self {
    var option = self;
    if (value) |v| {
        if (std.meta.activeTag(v) != self.type) {
            if (@inComptime()) @compileError("Option default type does not match option type");
            @panic("Option default type does not match option type");
        }
    }
    option.default = value;
    return option;
}

pub fn with(self: Self, opts: struct { type: ?Type = null, required: ?bool = null, default: ?Value = null }) Self {
    var option = self;
    if (opts.type) |kind| option.type = kind;
    if (opts.required) |required| option.required = required;
    if (opts.default) |value| {
        option = option.def(value);
    } else {
        option = option.def(option.default);
    }
    return option;
}

test "init parses option names, aliases, and value placeholders" {
    const cases = [_]struct { source: []const u8, key: []const u8, alias: ?u8, kind: Type }{
        .{ .source = "--help", .key = "help", .alias = null, .kind = .boolean },
        .{ .source = "-h, --help", .key = "help", .alias = 'h', .kind = .boolean },
        .{ .source = "-m, --mode=<val>", .key = "mode", .alias = 'm', .kind = .string },
        .{ .source = "-c, --count=<val>", .key = "count", .alias = 'c', .kind = .string },
    };
    inline for (cases) |case| {
        const option = Self.init(case.source);
        try t.expectEqualStrings(case.key, option.key);
        try t.expectEqual(case.alias, option.alias);
        try t.expectEqual(case.kind, option.type);
    }
}

test "with applies optional settings while preserving the option type" {
    const base = Self.init("-c, --count=<val>");
    const configured = base.with(.{ .required = true, .default = .{ .string = "5" } });
    try t.expect(!base.required);
    try t.expect(base.default == null);
    try t.expectEqual(Type.string, base.type);
    try t.expect(configured.required);
    try t.expectEqual(Type.string, configured.type);
    try t.expectEqualDeep(Value{ .string = "5" }, configured.default.?);

    const relaxed = configured.with(.{ .required = false });
    try t.expect(!relaxed.required);
    try t.expectEqualDeep(configured.default.?, relaxed.default.?);
    try t.expectEqual(Type.string, relaxed.type);

    const typed = base.with(.{ .type = .int, .default = .{ .int = 5 } });
    try t.expectEqual(Type.int, typed.type);
    try t.expectEqualDeep(Value{ .int = 5 }, typed.default.?);
}

test "int float and boolean constructors parse names and set their types" {
    const count = Self.int("-c, --count=<val>");
    try t.expectEqualStrings("count", count.key);
    try t.expectEqual(@as(?u8, 'c'), count.alias);
    try t.expectEqual(Type.int, count.type);

    const ratio = Self.float("--ratio=<val>");
    try t.expectEqualStrings("ratio", ratio.key);
    try t.expectEqual(Type.float, ratio.type);

    const enabled = Self.boolean("--enabled=<val>");
    try t.expectEqualStrings("enabled", enabled.key);
    try t.expectEqual(Type.boolean, enabled.type);
}

test "def sets or clears a matching default without changing the type" {
    const base = Self.int("--count=<val>");
    const configured = base.def(.{ .int = 5 });
    try t.expectEqualDeep(Value{ .int = 5 }, configured.default.?);
    try t.expectEqual(Type.int, configured.type);

    const cleared = configured.def(null);
    try t.expect(cleared.default == null);
    try t.expectEqual(Type.int, cleared.type);
}
