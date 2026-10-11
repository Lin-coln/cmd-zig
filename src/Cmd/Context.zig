const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
args: []const []const u8,

pub fn initFromProcess(init: std.process.Init) Self {
    const allocator: Allocator = init.arena.allocator();
    const args: []const []const u8 = try init.minimal.args.toSlice(allocator);
    return .{
        .allocator = allocator,
        .args = args,
    };
}
