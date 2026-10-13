const std = @import("std");
const Option = @import("Option.zig");
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
args: []const []const u8,

pub fn split(self: Self, idx: usize) struct { Self, Self } {
    return .{
        .{
            .allocator = self.allocator,
            .args = self.args[0..idx],
        },
        .{
            .allocator = self.allocator,
            .args = self.args[idx..],
        },
    };
}
