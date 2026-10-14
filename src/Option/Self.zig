const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");

pub const Value = @import("Value.zig").Value;
pub const Type = @import("Value.zig").Type;

const Self = @This();
key: []const u8,
alias: ?u8 = null,
desc: ?[]const u8 = null,
type: Type = .string,
required: bool = false,
default: ?Value = null,

pub const init = @import("init.zig").init;
pub const int = @import("init.zig").int;
pub const float = @import("init.zig").float;
pub const boolean = @import("init.zig").boolean;
pub const def = @import("init.zig").def;
pub const with = @import("init.zig").with;

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
