const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
argv: []const [:0]const u8,
args: std.ArrayList(*const []const u8),
options: std.StringHashMap(?[]const u8),

pub fn createFromProcess(init: std.process.Init) !*Self {
    const allocator: Allocator = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(allocator);
    return try .create(allocator, argv, null);
}

pub fn create(
    allocator: Allocator,
    argv: []const [:0]const u8,
    args_brw: ?std.ArrayList(*const []const u8),
) !*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);

    var args: std.ArrayList(*const []const u8) = .empty;
    errdefer args.deinit(allocator);
    if (args_brw) |brw| {
        try args.appendSlice(allocator, brw.items);
    } else {
        for (argv[1..]) |*arg| {
            try args.append(allocator, arg);
        }
    }

    const options = std.StringHashMap(?[]const u8).init(allocator);
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
    return try .create(self.allocator, self.argv, self.args);
}
