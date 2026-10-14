const std = @import("std");
const t = std.testing;

pub const Context = @import("Context.zig");
pub const Option = @import("Option.zig");
pub const OptionRecord = @import("OptionRecord.zig");

pub const Manifest = struct {
    name: []const u8,
    desc: ?[]const u8 = null,
    options: ?[]const Option = null,
};

const Self = @This();
manifest: Manifest,
/// Borrowed implementation state; null for stateless commands.
ptr: ?*anyopaque = null,
vt: *const VTable,

pub const VTable = @import("init.zig").VTable;
pub const init = @import("init.zig").init;
pub const initWithCtx = @import("initWithCtx.zig").initWithCtx;
pub const execute = @import("execute.zig").execute;

fn querySubManifests(self: Self, ctx: Context) ?[]const Manifest {
    const f = self.vt.querySubManifests orelse return null;
    return f(self.ptr, ctx);
}

test "query submanifests handles absent and present callbacks" {
    const Cmd = @import("Self.zig");
    const simple = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "simple" };
        pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
    });
    const parent = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "parent" };
        pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
        pub fn querySubManifests(_: Cmd.Context) ?[]const Cmd.Manifest {
            return &.{.{ .name = "child" }};
        }
    });
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{} };
    try t.expect(simple.querySubManifests(ctx) == null);
    const manifests = parent.querySubManifests(ctx).?;
    try t.expectEqual(@as(usize, 1), manifests.len);
    try t.expectEqualStrings("child", manifests[0].name);
}
