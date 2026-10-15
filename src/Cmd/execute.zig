const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = @import("../Context/Self.zig");

pub fn execute(self: Self, ctx: Context) anyerror!void {
    return self.executeFn(self.ptr, ctx);
}

test "Cmd.execute: forwards state and the unchanged context without allocating" {
    var state = struct {
        args: []const []const u8,
        called: bool = false,
        fn run(raw: ?*anyopaque, ctx: Context) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.called = true;
            try t.expect(ctx.args.ptr == self.args.ptr);
            try t.expectEqual(self.args.len, ctx.args.len);
            try t.expect(ctx.allocator.ptr == t.failing_allocator.ptr);
            try t.expect(ctx.allocator.vtable == t.failing_allocator.vtable);
        }
    }{ .args = &.{ "/bin/foo", "1323", "-h", "child", "--" } };
    const cmd: Self = .{ .ptr = &state, .executeFn = @TypeOf(state).run };
    try cmd.execute(.{ .allocator = t.failing_allocator, .args = state.args });
    try t.expect(state.called);
}
