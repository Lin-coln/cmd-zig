const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = @import("../Context/Self.zig");

pub fn initWithCtx(typed: anytype, comptime Impls: type) Self {
    const Ptr = @TypeOf(typed);
    switch (@typeInfo(Ptr)) {
        .pointer => |info| {
            if (info.size != .one or info.is_const) {
                @compileError("Cmd.initWithCtx requires a mutable single-item pointer");
            }
        },
        else => @compileError("Cmd.initWithCtx requires an instance pointer; use Cmd.init for stateless commands"),
    }
    if (!@hasDecl(Impls, "execute")) {
        @compileError(@typeName(Impls) ++ " needs execute");
    }

    return .{ .ptr = typed, .executeFn = struct {
        fn execute(raw: ?*anyopaque, ctx: Context) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(raw.?));
            return Impls.execute(self, ctx);
        }
    }.execute };
}

test "Cmd.initWithCtx: binds each command to its original instance" {
    const State = struct {
        calls: usize = 0,
        pub fn execute(self: *@This(), ctx: Context) !void {
            self.calls += 1;
            try t.expectEqualStrings("/bin/foo", ctx.args[0]);
            try t.expect(ctx.allocator.ptr == t.failing_allocator.ptr);
        }
    };
    var a: State = .{};
    var b: State = .{};
    const ca = initWithCtx(&a, State);
    const cb = initWithCtx(&b, State);
    try t.expect(ca.ptr == @as(?*anyopaque, &a));
    try t.expect(cb.ptr == @as(?*anyopaque, &b));
    try t.expect(ca.executeFn == cb.executeFn);
    const ctx: Context = .{ .allocator = t.failing_allocator, .args = &.{"/bin/foo"} };
    try ca.execute(ctx);
    try ca.execute(ctx);
    try cb.execute(ctx);
    try t.expectEqual(@as(usize, 2), a.calls);
    try t.expectEqual(@as(usize, 1), b.calls);
}

test "Cmd.initWithCtx: propagates the bound executor error" {
    var state = struct {
        attempted: bool = false,
        pub fn execute(self: *@This(), _: Context) error{ExecutionFailed}!void {
            self.attempted = true;
            return error.ExecutionFailed;
        }
    }{};
    const cmd = initWithCtx(&state, @TypeOf(state));
    try t.expectError(error.ExecutionFailed, cmd.execute(.{ .allocator = t.failing_allocator, .args = &.{"/bin/foo"} }));
    try t.expect(state.attempted);
}
