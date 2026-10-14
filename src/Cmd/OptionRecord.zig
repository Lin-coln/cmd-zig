const std = @import("std");
const t = std.testing;
const Option = @import("Option.zig");
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

pub fn get(self: *const Self, comptime T: type, key: []const u8) error{OptionTypeMismatch}!?T {
    const value = self.map.get(key) orelse return null;
    const actual = std.meta.activeTag(value);
    if (T == bool) {
        if (actual != .boolean) return error.OptionTypeMismatch;
        return value.boolean;
    }
    if (T == []const u8) {
        if (actual != .string) return error.OptionTypeMismatch;
        return value.string;
    }
    @compileError("OptionRecord.get supports bool and []const u8");
}

pub fn getArg(self: *const Self, key: []const u8) Allocator.Error!?[]u8 {
    const value = self.map.get(key) orelse return null;
    return switch (value) {
        .boolean => |boolean| try std.fmt.allocPrint(self.allocator, "--{s}={}", .{ key, boolean }),
        .string => |string| try std.fmt.allocPrint(self.allocator, "--{s}={s}", .{ key, string }),
    };
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

test "get returns null for a missing key" {
    const record = try Self.create(t.allocator);
    defer record.destroy();
    try t.expect((try record.get([]const u8, "name")) == null);
}

test "set replaces the value at an existing key" {
    const record = try Self.create(t.allocator);
    defer record.destroy();

    try record.set("name", .{ .string = "first" });
    try t.expectEqualStrings("first", (try record.get([]const u8, "name")).?);
    try record.set("name", .{ .boolean = true });
    try t.expect((try record.get(bool, "name")).?);
    try record.set("name", .{ .boolean = false });
    try t.expect(!(try record.get(bool, "name")).?);
    try t.expectEqual(@as(usize, 1), record.map.count());
}

test "get returns OptionTypeMismatch when the requested type differs" {
    const record = try Self.create(t.allocator);
    defer record.destroy();

    try record.set("name", .{ .string = "first" });
    try t.expectError(error.OptionTypeMismatch, record.get(bool, "name"));
    try record.set("name", .{ .boolean = true });
    try t.expectError(error.OptionTypeMismatch, record.get([]const u8, "name"));
}

test "getArg formats stored strings and booleans as long option arguments" {
    const record = try Self.create(t.allocator);
    defer record.destroy();

    const cases = [_]struct { key: []const u8, value: Option.Value, expected: []const u8 }{
        .{ .key = "output", .value = .{ .string = "file.txt" }, .expected = "--output=file.txt" },
        .{ .key = "output", .value = .{ .string = "" }, .expected = "--output=" },
        .{ .key = "help", .value = .{ .boolean = true }, .expected = "--help=true" },
        .{ .key = "help", .value = .{ .boolean = false }, .expected = "--help=false" },
    };
    for (cases) |case| {
        try record.set(case.key, case.value);
        const arg = (try record.getArg(case.key)).?;
        defer t.allocator.free(arg);
        try t.expectEqualStrings(case.expected, arg);
    }
}

test "getArg returns null for a missing key" {
    const record = try Self.create(t.allocator);
    defer record.destroy();
    try t.expect((try record.getArg("missing")) == null);
}
