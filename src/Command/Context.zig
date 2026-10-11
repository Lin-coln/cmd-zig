const std = @import("std");
const Allocator = std.mem.Allocator;

allocator: Allocator,
args: []const []const u8,
