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
    const Simple = struct {
        pub const manifest: Manifest = .{ .name = "simple" };
        pub fn onExecute(_: Context, _: *const OptionRecord) !void {}
    };
    const Parent = struct {
        pub const manifest: Manifest = .{ .name = "parent" };
        pub fn onExecute(_: Context, _: *const OptionRecord) !void {}
        pub fn querySubManifests(_: Context) ?[]const Manifest {
            return &.{.{ .name = "child" }};
        }
    };
    const ctx: Context = .{ .allocator = t.allocator, .args = &.{} };
    try t.expect(init(Simple).querySubManifests(ctx) == null);
    const manifests = init(Parent).querySubManifests(ctx).?;
    try t.expectEqual(@as(usize, 1), manifests.len);
    try t.expectEqualStrings("child", manifests[0].name);
}
