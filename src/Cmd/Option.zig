const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");

pub const Type = std.meta.Tag(Value);
pub const Value = union(enum) {
    boolean: bool,
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
    }
}

test "match uses key and optional alias" {
    const option: Self = .{ .key = "verbose", .alias = 'v' };
    try t.expect(option.match(Args.OptionDescriptor.parseFromArg("--verbose").?));
    try t.expect(option.match(Args.OptionDescriptor.parseFromArg("-v").?));
    try t.expect(!option.match(Args.OptionDescriptor.parseFromArg("--other").?));
    try t.expect(!option.match(Args.OptionDescriptor.parseFromArg("-x").?));
    const without_alias: Self = .{ .key = "verbose" };
    try t.expect(!without_alias.match(Args.OptionDescriptor.parseFromArg("-v").?));
}

test "parse string and boolean option values" {
    const string: Self = .{ .key = "output" };
    try t.expectEqualStrings("file", (try string.parse(Args.OptionDescriptor.parseFromArg("--output=file").?)).string);
    try t.expectEqualStrings("", (try string.parse(Args.OptionDescriptor.parseFromArg("--output").?)).string);

    const boolean: Self = .{ .key = "verbose", .type = .boolean };
    try t.expect((try boolean.parse(Args.OptionDescriptor.parseFromArg("--verbose").?)).boolean);
    try t.expect((try boolean.parse(Args.OptionDescriptor.parseFromArg("--verbose=true").?)).boolean);
    try t.expect(!(try boolean.parse(Args.OptionDescriptor.parseFromArg("--verbose=false").?)).boolean);
    try t.expectError(error.InvalidOptionValueFound, boolean.parse(Args.OptionDescriptor.parseFromArg("--verbose=yes").?));
    try t.expectError(error.InvalidOptionValueFound, boolean.parse(Args.OptionDescriptor.parseFromArg("--verbose=").?));
}
