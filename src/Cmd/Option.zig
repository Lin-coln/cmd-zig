const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");

pub const Type = std.meta.Tag(Value);
pub const Value = union(enum) {
    boolean: bool,
    int: i64,
    float: f64,
    string: []const u8,

    pub fn parse(kind: Type, raw: []const u8) !Value {
        switch (kind) {
            .string => return .{ .string = raw },
            .boolean => {
                if (std.mem.eql(u8, raw, "false")) {
                    return .{ .boolean = false };
                } else if (std.mem.eql(u8, raw, "true")) {
                    return .{ .boolean = true };
                } else {
                    return error.InvalidOptionValueFound;
                }
            },
            .int => {
                return .{ .int = std.fmt.parseInt(i64, raw, 10) catch return error.InvalidOptionValueFound };
            },
            .float => {
                return .{ .float = std.fmt.parseFloat(f64, raw) catch return error.InvalidOptionValueFound };
            },
        }
    }
};

const Self = @This();
key: []const u8,
alias: ?u8 = null,
desc: ?[]const u8 = null,
type: Type = .string,
required: bool = false,
default: ?Value = null,

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

pub fn match(self: *const Self, desc: Args.OptionDescriptor) bool {
    switch (desc.identity) {
        .key => |x| return std.mem.eql(u8, self.key, x),
        .alias => |x| {
            const alias = self.alias orelse return false;
            return alias == x;
        },
    }
}

pub fn parse(self: *const Self, desc: Args.OptionDescriptor) !Value {
    const raw = desc.value orelse switch (self.type) {
        .boolean => "true",
        .string => "",
        .int, .float => return error.InvalidOptionValueFound,
    };
    return Value.parse(self.type, raw);
}

test "match accepts matching keys and aliases and rejects other identities" {
    const option: Self = .{ .key = "verbose", .alias = 'v' };
    try t.expect(option.match(Args.OptionDescriptor.parseFromArg("--verbose").?));
    try t.expect(option.match(Args.OptionDescriptor.parseFromArg("-v").?));
    try t.expect(!option.match(Args.OptionDescriptor.parseFromArg("--other").?));
    try t.expect(!option.match(Args.OptionDescriptor.parseFromArg("-x").?));
    const without_alias: Self = .{ .key = "verbose" };
    try t.expect(!without_alias.match(Args.OptionDescriptor.parseFromArg("-v").?));
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

test "Value.parse returns the declared value type for valid raw values" {
    const cases = [_]struct { kind: Type, raw: []const u8, expected: Value }{
        .{ .kind = .string, .raw = "file", .expected = .{ .string = "file" } },
        .{ .kind = .string, .raw = "", .expected = .{ .string = "" } },
        .{ .kind = .boolean, .raw = "true", .expected = .{ .boolean = true } },
        .{ .kind = .boolean, .raw = "false", .expected = .{ .boolean = false } },
        .{ .kind = .int, .raw = "42", .expected = .{ .int = 42 } },
        .{ .kind = .int, .raw = "0", .expected = .{ .int = 0 } },
        .{ .kind = .int, .raw = "-1", .expected = .{ .int = -1 } },
        .{ .kind = .float, .raw = "1.5", .expected = .{ .float = 1.5 } },
        .{ .kind = .float, .raw = "-0.25", .expected = .{ .float = -0.25 } },
    };
    comptime {
        for (@typeInfo(Type).@"enum".fields) |field| {
            var covered = false;
            for (cases) |case| {
                if (std.mem.eql(u8, @tagName(case.kind), field.name)) covered = true;
            }
            if (!covered) @compileError("Value.parse cases need a " ++ field.name ++ " example");
        }
    }
    inline for (cases) |case| {
        try t.expectEqualDeep(case.expected, try Value.parse(case.kind, case.raw));
    }
}

test "Value.parse rejects invalid raw values" {
    const cases = [_]struct { kind: Type, raw: []const u8 }{
        .{ .kind = .boolean, .raw = "yes" },
        .{ .kind = .boolean, .raw = "" },
        .{ .kind = .int, .raw = "" },
        .{ .kind = .int, .raw = "abc" },
        .{ .kind = .int, .raw = "9223372036854775808" },
        .{ .kind = .int, .raw = "-9223372036854775809" },
        .{ .kind = .float, .raw = "" },
        .{ .kind = .float, .raw = "abc" },
        .{ .kind = .float, .raw = "1.2.3" },
    };
    inline for (cases) |case| {
        try t.expectError(error.InvalidOptionValueFound, Value.parse(case.kind, case.raw));
    }
}

test "Option.parse handles absent values and delegates present values to Value.parse" {
    const flag: Self = .{ .key = "verbose", .type = .boolean };
    try t.expectEqualDeep(Value{ .boolean = true }, try flag.parse(Args.OptionDescriptor.parseFromArg("--verbose").?));
    try t.expectError(error.InvalidOptionValueFound, flag.parse(Args.OptionDescriptor.parseFromArg("--verbose=").?));

    const output: Self = .{ .key = "output" };
    try t.expectEqualDeep(Value{ .string = "" }, try output.parse(Args.OptionDescriptor.parseFromArg("--output").?));

    const count: Self = .{ .key = "count", .type = .int };
    try t.expectEqualDeep(Value{ .int = -2 }, try count.parse(Args.OptionDescriptor.parseFromArg("--count=-2").?));
    try t.expectError(error.InvalidOptionValueFound, count.parse(Args.OptionDescriptor.parseFromArg("--count").?));
}
