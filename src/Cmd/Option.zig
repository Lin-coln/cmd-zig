const std = @import("std");
const Allocator = std.mem.Allocator;
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
