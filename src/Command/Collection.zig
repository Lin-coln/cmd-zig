const std = @import("std");
const Command = @import("Self.zig");
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
ref_count: std.atomic.Value(usize) = .init(1),
items: std.ArrayList(Command) = .empty,

pub fn create(allocator: Allocator) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,
    };
    return self;
}

pub fn release(self: *Self) void {
    const prev = self.ref_count.fetchSub(1, .acq_rel);
    std.debug.assert(prev > 0);

    if (prev != 1) return;

    for (self.items.items) |*command| {
        command.deinit();
    }

    self.items.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn retain(self: *Self) *Self {
    const prev = self.ref_count.fetchAdd(1, .monotonic);
    std.debug.assert(prev > 0);
    return self;
}

pub fn addCommand(self: *Self, command: Command) !void {
    try self.items.append(self.allocator, command.clone());
}

pub fn findCommandByName(self: *const Self, name: []const u8) ?Command {
    for (self.items.items) |cmd| {
        if (std.mem.eql(u8, cmd.name, name)) {
            return cmd;
        }
    }
    return null;
}
