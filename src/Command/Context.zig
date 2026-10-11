const std = @import("std");
const Command = @import("Self.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
argv: []const [:0]const u8,
args: std.ArrayList(*const []const u8),
options: std.StringHashMap(Command.Option.Entry),

pub fn create(
    allocator: Allocator,
    argv: []const [:0]const u8,
    extra: struct {
        args: ?[]*const []const u8 = null,
    },
) !*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);

    var args: std.ArrayList(*const []const u8) = .empty;
    errdefer args.deinit(allocator);
    if (extra.args) |slice| {
        try args.appendSlice(allocator, slice);
    } else {
        for (argv[1..]) |*arg| {
            try args.append(allocator, arg);
        }
    }

    const options = std.StringHashMap(Command.Option.Entry).init(allocator);
    errdefer options.deinit();

    ptr.* = .{
        .allocator = allocator,
        .argv = argv,
        .args = args,
        .options = options,
    };

    return ptr;
}

pub fn destroy(self: *Self) void {
    self.options.deinit();
    self.args.deinit(self.allocator);
}

pub fn clone(self: *const Self) !*Self {
    return try .create(self.allocator, self.argv, .{ .args = self.args.items });
}
