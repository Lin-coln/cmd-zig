const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");

pub const Type = std.meta.Tag(Value);
pub const Value = union(enum) {
    boolean: bool,
    char: u8,
    string: []const u8,
};

const Self = @This();
key: []const u8,
alias: ?u8 = null,
desc: ?[]const u8 = null,
type: Type = .string,
required: bool = false,

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
    switch (self.type) {
        .string => return .{ .string = desc.value orelse "" },
        .boolean => {
            const val = desc.value orelse return .{ .boolean = true };
            if (std.mem.eql(u8, val, "false")) {
                return .{ .boolean = false };
            } else if (std.mem.eql(u8, val, "true")) {
                return .{ .boolean = true };
            } else {
                return error.InvalidOptionValueFound;
            }
        },
        .char => {
            const value = desc.value orelse return error.InvalidOptionValueFound;
            if (value.len != 1) return error.InvalidOptionValueFound;
            return .{ .char = value[0] };
        },
    }
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

test "parse returns the declared value type for valid arguments" {
    const cases = [_]struct { kind: Type, arg: []const u8, expected: Value }{
        .{ .kind = .string, .arg = "--output=file", .expected = .{ .string = "file" } },
        .{ .kind = .string, .arg = "--output", .expected = .{ .string = "" } },
        .{ .kind = .boolean, .arg = "--verbose", .expected = .{ .boolean = true } },
        .{ .kind = .boolean, .arg = "--verbose=true", .expected = .{ .boolean = true } },
        .{ .kind = .boolean, .arg = "--verbose=false", .expected = .{ .boolean = false } },
        .{ .kind = .char, .arg = "--delimiter=,", .expected = .{ .char = ',' } },
        .{ .kind = .char, .arg = "-d=:", .expected = .{ .char = ':' } },
    };
    comptime {
        for (@typeInfo(Type).@"enum".fields) |field| {
            var covered = false;
            for (cases) |case| {
                if (std.mem.eql(u8, @tagName(case.kind), field.name)) covered = true;
            }
            if (!covered) @compileError("parse cases need a " ++ field.name ++ " example");
        }
    }
    inline for (cases) |case| {
        const option: Self = .{ .key = "option", .type = case.kind };
        try t.expectEqualDeep(case.expected, try option.parse(Args.OptionDescriptor.parseFromArg(case.arg).?));
    }
}

test "parse rejects values invalid for the declared type" {
    const cases = [_]struct { kind: Type, arg: []const u8 }{
        .{ .kind = .boolean, .arg = "--verbose=yes" },
        .{ .kind = .boolean, .arg = "--verbose=" },
        .{ .kind = .char, .arg = "--delimiter" },
        .{ .kind = .char, .arg = "--delimiter=" },
        .{ .kind = .char, .arg = "--delimiter=ab" },
        .{ .kind = .char, .arg = "--delimiter=é" },
    };
    inline for (cases) |case| {
        const option: Self = .{ .key = "option", .type = case.kind };
        try t.expectError(error.InvalidOptionValueFound, option.parse(Args.OptionDescriptor.parseFromArg(case.arg).?));
    }
}
