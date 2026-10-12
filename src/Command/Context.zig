const std = @import("std");
const Option = @import("Option.zig");
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
args: []const []const u8,
opts: ?*Option.Record = null,

pub fn slice(self: Self, idx: union(enum) { start: usize, end: usize }) Self {
    return .{
        .allocator = self.allocator,
        .args = switch (idx) {
            .start => |i| self.args[i..],
            .end => |i| self.args[0..i],
        },
    };
}

pub fn toParsed(
    self: Self,
    args: []const []const u8,
    opts: *Option.Record,
) Self {
    return .{
        .allocator = self.allocator,
        .args = args,
        .opts = opts,
    };
}
