const std = @import("std");
const t = std.testing;

pub const Context = @import("Context.zig");
const OptionRecord = @import("../Option/Record.zig");
const Manifest = @import("../Manifest/Self.zig");

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

test "Cmd.querySubManifests: returns null when the callback is absent" {
    const Cmd = @import("Self.zig");
    const simple = Cmd.init(.{ .name = "simple" }, struct {
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) !void {}
    });
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{} };
    try t.expect(simple.querySubManifests(ctx) == null);
}

test "Cmd.querySubManifests: returns the callback manifests when present" {
    const Cmd = @import("Self.zig");
    const parent = Cmd.init(.{ .name = "parent" }, struct {
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) !void {}
        pub fn querySubManifests(_: Cmd.Context) ?[]const Manifest {
            return &.{.{ .name = "child" }};
        }
    });
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{} };
    const manifests = parent.querySubManifests(ctx).?;
    try t.expectEqual(@as(usize, 1), manifests.len);
    try t.expectEqualStrings("child", manifests[0].name);
}
