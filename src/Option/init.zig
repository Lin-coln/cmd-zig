const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");
const Self = @import("Self.zig");
const Value = Self.Value;
const Type = Self.Type;

pub fn init(str: []const u8) !Self {
    const comma = std.mem.indexOfScalar(u8, str, ',');
    const long = std.mem.trim(u8, if (comma) |idx| str[idx + 1 ..] else str, " \t");
    if (std.mem.indexOfScalar(u8, long, ',') != null) return error.InvalidOptionFormat;

    const descriptor = Args.OptionDescriptor.parseFromArg(long) orelse return error.InvalidOptionFormat;
    const key = switch (descriptor.identity) {
        .key => |value| value,
        .alias => return error.InvalidOptionFormat,
    };
    if (std.mem.indexOfAny(u8, key, " \t\r\n") != null) return error.InvalidOptionFormat;

    const kind: Type = if (descriptor.value) |placeholder| blk: {
        if (placeholder.len < 3 or placeholder[0] != '<' or placeholder[placeholder.len - 1] != '>')
            return error.InvalidOptionFormat;
        if (std.mem.indexOfAny(u8, placeholder[1 .. placeholder.len - 1], "<> \t\r\n") != null)
            return error.InvalidOptionFormat;
        break :blk .string;
    } else .boolean;

    const alias: ?u8 = if (comma) |idx| blk: {
        const short = std.mem.trim(u8, str[0..idx], " \t");
        const short_descriptor = Args.OptionDescriptor.parseFromArg(short) orelse return error.InvalidOptionFormat;
        if (short_descriptor.value != null) return error.InvalidOptionFormat;
        break :blk switch (short_descriptor.identity) {
            .alias => |value| value,
            .key => return error.InvalidOptionFormat,
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

pub fn with(self: Self, opts: struct { required: ?bool = null, default: ?Value = null }) Self {
    var option = self;
    if (opts.required) |required| option.required = required;
    if (opts.default) |value| option = option.def(value);
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
        const option = try Self.init(case.source);
        try t.expectEqualStrings(case.key, option.key);
        try t.expectEqual(case.alias, option.alias);
        try t.expectEqual(case.kind, option.type);
    }
}

test "init rejects malformed option declarations" {
    const cases = [_][]const u8{
        "",
        "-h",
        "--",
        "--help=",
        "--mode=value",
        "--mode=<>",
        "-ab, --help",
        "-h=1, --help",
        "--help, --other",
        "-h, --help, --other",
    };
    inline for (cases) |case| {
        try t.expectError(error.InvalidOptionFormat, Self.init(case));
    }
}

test "with applies optional settings while preserving the option type" {
    const base = try Self.init("-c, --count=<val>");
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
}

test "def sets or clears a matching default without changing the type" {
    var base = try Self.init("--count=<val>");
    base.type = .int;
    const configured = base.def(.{ .int = 5 });
    try t.expectEqualDeep(Value{ .int = 5 }, configured.default.?);
    try t.expectEqual(Type.int, configured.type);

    const cleared = configured.def(null);
    try t.expect(cleared.default == null);
    try t.expectEqual(Type.int, cleared.type);
}
