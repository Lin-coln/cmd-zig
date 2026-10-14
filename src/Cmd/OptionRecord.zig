const std = @import("std");
const t = std.testing;
const Option = @import("Option.zig");
const Args = @import("../Args/Self.zig");
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
map: std.StringHashMapUnmanaged(Option.Value) = .empty,

pub fn create(allocator: Allocator) !*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);
    ptr.* = .{
        .allocator = allocator,
    };
    return ptr;
}

pub fn destroy(self: *Self) void {
    self.map.deinit(self.allocator);
    self.allocator.destroy(self);
}

pub fn set(self: *Self, key: []const u8, val: Option.Value) !void {
    try self.map.put(self.allocator, key, val);
}

pub fn print(self: *const Self) void {
    var iter = self.map.iterator();
    while (iter.next()) |entry| {
        std.debug.print("{s}: {any}\n", .{
            entry.key_ptr.*,
            entry.value_ptr.*,
        });
    }
}

test "record stores and replaces typed option values" {
    const record = try Self.create(t.allocator);
    defer record.destroy();

    try t.expect(record.map.get("name") == null);
    try record.set("name", .{ .string = "first" });
    try t.expectEqualStrings("first", record.map.get("name").?.string);
    try record.set("name", .{ .boolean = true });
    try t.expect(record.map.get("name").?.boolean);
    try t.expectEqual(@as(usize, 1), record.map.count());
}
