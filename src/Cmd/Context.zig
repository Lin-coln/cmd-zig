const std = @import("std");
const t = std.testing;
const Allocator = std.mem.Allocator;

const Self = @This();
allocator: Allocator,
args: []const []const u8,

pub fn split(self: Self, idx: usize) struct { Self, Self } {
    return .{
        .{
            .allocator = self.allocator,
            .args = self.args[0..idx],
        },
        .{
            .allocator = self.allocator,
            .args = self.args[idx..],
        },
    };
}

test "split preserves allocator and partitions argument slices" {
    const ctx: Self = .{ .allocator = t.allocator, .args = &.{ "one", "two", "three" } };
    const left, const right = ctx.split(1);
    try t.expect(left.allocator.ptr == ctx.allocator.ptr);
    try t.expect(right.allocator.ptr == ctx.allocator.ptr);
    try t.expectEqual(@as(usize, 1), left.args.len);
    try t.expectEqual(@as(usize, 2), right.args.len);
    try t.expectEqualStrings("one", left.args[0]);
    try t.expectEqualStrings("two", right.args[0]);
    try t.expectEqualStrings("three", right.args[1]);

    const empty, const all = ctx.split(0);
    try t.expectEqual(@as(usize, 0), empty.args.len);
    try t.expectEqual(@as(usize, 3), all.args.len);
}
