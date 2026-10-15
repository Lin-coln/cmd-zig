const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = @import("../Context/Self.zig");

pub fn init(comptime Impls: type) Self {
    if (!@hasDecl(Impls, "execute")) {
        @compileError(@typeName(Impls) ++ " needs execute");
    }

    return .{ .executeFn = struct {
        fn execute(_: ?*anyopaque, ctx: Context) anyerror!void {
            return Impls.execute(ctx);
        }
    }.execute };
}

test "Cmd.init: binds a stateless executor without instance state" {
    const cmd = comptime init(struct {
        pub fn execute(ctx: Context) !void {
            try t.expectEqualStrings("/bin/foo", ctx.args[0]);
            try t.expectEqualStrings("-h", ctx.args[1]);
            try t.expect(ctx.allocator.ptr == t.failing_allocator.ptr);
        }
    });
    try t.expect(cmd.ptr == null);
    try cmd.execute(.{ .allocator = t.failing_allocator, .args = &.{ "/bin/foo", "-h" } });
}

test "Cmd.init: propagates the executor error" {
    const cmd = init(struct {
        pub fn execute(_: Context) error{ExecutionFailed}!void {
            return error.ExecutionFailed;
        }
    });
    try t.expectError(error.ExecutionFailed, cmd.execute(.{ .allocator = t.failing_allocator, .args = &.{"/bin/foo"} }));
}
