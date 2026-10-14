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

pub fn get(self: *const Self, comptime T: type, key: []const u8) !?T {
    const value = self.map.get(key) orelse return null;
    return switch (value) {
        inline else => |payload| if (@TypeOf(payload) == T) payload else error.OptionTypeMismatch,
    };
}

pub fn getArg(self: *const Self, key: []const u8) !?[]u8 {
    const value = self.map.get(key) orelse return null;
    return switch (value) {
        .boolean => |boolean| try std.fmt.allocPrint(self.allocator, "--{s}={}", .{ key, boolean }),
        .char => |char| try std.fmt.allocPrint(self.allocator, "--{s}={c}", .{ key, char }),
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

const value_cases = .{
    .{ .key = "help", .value = Option.Value{ .boolean = true }, .expected = @as(bool, true), .arg = "--help=true" },
    .{ .key = "quiet", .value = Option.Value{ .boolean = false }, .expected = @as(bool, false), .arg = "--quiet=false" },
    .{ .key = "output", .value = Option.Value{ .string = "file.txt" }, .expected = @as([]const u8, "file.txt"), .arg = "--output=file.txt" },
    .{ .key = "empty", .value = Option.Value{ .string = "" }, .expected = @as([]const u8, ""), .arg = "--empty=" },
    .{ .key = "delimiter", .value = Option.Value{ .char = ',' }, .expected = @as(u8, ','), .arg = "--delimiter=," },
    .{ .key = "raw", .value = Option.Value{ .char = 0xe9 }, .expected = @as(u8, 0xe9), .arg = &[_]u8{ '-', '-', 'r', 'a', 'w', '=', 0xe9 } },
};

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
    try t.expectEqual(@as(usize, 1), record.map.count());
}

test "get returns OptionTypeMismatch when the requested type differs" {
    const record = try Self.create(t.allocator);
    defer record.destroy();

    try record.set("name", .{ .string = "first" });
    try t.expectError(error.OptionTypeMismatch, record.get(bool, "name"));
}

test "get returns the stored payload for each value type" {
    comptime {
        for (@typeInfo(Option.Type).@"enum".fields) |field| {
            var covered = false;
            for (value_cases) |case| {
                if (std.mem.eql(u8, @tagName(std.meta.activeTag(case.value)), field.name)) covered = true;
            }
            if (!covered) @compileError("value_cases needs a " ++ field.name ++ " example");
        }
    }
    const record = try Self.create(t.allocator);
    defer record.destroy();

    inline for (value_cases) |case| {
        try record.set(case.key, case.value);
        try t.expectEqualDeep(case.expected, (try record.get(@TypeOf(case.expected), case.key)).?);
    }
}

test "getArg formats stored values as long option arguments" {
    const record = try Self.create(t.allocator);
    defer record.destroy();

    inline for (value_cases) |case| {
        try record.set(case.key, case.value);
        const arg = (try record.getArg(case.key)).?;
        defer t.allocator.free(arg);
        try t.expectEqualStrings(case.arg, arg);
    }
}

test "getArg returns null for a missing key" {
    const record = try Self.create(t.allocator);
    defer record.destroy();
    try t.expect((try record.getArg("missing")) == null);
}
