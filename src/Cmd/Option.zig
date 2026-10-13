const std = @import("std");
const Allocator = std.mem.Allocator;
const Args = @import("../Args/Self.zig");

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

pub const Type = enum {
    boolean,
    string,
};

pub const Value = union(Type) {
    boolean: bool,
    string: []const u8,
};

pub const Record = struct {
    allocator: Allocator,
    map: std.StringHashMapUnmanaged(Value) = .empty,

    pub fn create(allocator: Allocator) !*Record {
        const ptr = try allocator.create(Record);
        errdefer allocator.destroy(ptr);
        ptr.* = .{
            .allocator = allocator,
        };
        return ptr;
    }

    pub fn deinit(self: *Record) void {
        self.map.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn set(
        self: *Record,
        key: []const u8,
        val: Value,
    ) !void {
        try self.map.put(self.allocator, key, val);
    }

    pub fn print(self: *const Record) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            std.debug.print("{s}: {any}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.*,
            });
        }
    }
};
