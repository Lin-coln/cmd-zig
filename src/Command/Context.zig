const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
args: []const []const u8,

pub fn slice(self: Self, idx: union(enum) { start: usize, end: usize }) Self {
    return .{
        .allocator = self.allocator,
        .args = switch (idx) {
            .start => |i| self.args[i..],
            .end => |i| self.args[0..i],
        },
    };
}
