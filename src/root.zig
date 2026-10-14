const std = @import("std");
const t = std.testing;

pub const Args = @import("Args/Self.zig");
pub const Cmd = @import("Cmd/Self.zig");

test {
    _ = @import("Args/OptionDescriptor.zig");
    _ = @import("Args/Self.zig");
    _ = @import("Cmd/Context.zig");
    _ = @import("Cmd/Option.zig");
    _ = @import("Cmd/OptionRecord.zig");
    _ = @import("Cmd/init.zig");
    _ = @import("Cmd/execute.zig");
}

const IntegrationChild = struct {
    pub const manifest: Cmd.Manifest = .{
        .name = "child",
        .options = &.{
            .{ .key = "output", .alias = 'o' },
            .{ .key = "force", .alias = 'f', .type = .boolean },
        },
    };
    executions: usize = 0,

    pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
        self.executions += 1;
        try t.expectEqual(@as(usize, 3), ctx.args.len);
        try t.expectEqualStrings("child", ctx.args[0]);
        try t.expectEqualStrings("payload", ctx.args[1]);
        try t.expectEqualStrings("--output=ignored", ctx.args[2]);
        try t.expectEqualStrings("dest", opts.map.get("output").?.string);
        try t.expect(!opts.map.get("force").?.boolean);
    }
};

const IntegrationParent = struct {
    pub const manifest: Cmd.Manifest = .{
        .name = "parent",
        .options = &.{.{ .key = "trace", .alias = 't', .type = .boolean }},
    };
    child: Cmd,
    executions: usize = 0,

    pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
        self.executions += 1;
        try t.expectEqual(@as(usize, 0), ctx.args.len);
        try t.expect(opts.map.get("trace").?.boolean);
    }

    pub fn querySubCommand(self: *@This(), _: Cmd.Context, name: []const u8) ?Cmd {
        return if (std.mem.eql(u8, name, "child")) self.child else null;
    }
};

test "public command API dispatches a child and parses options across both levels" {
    var child: IntegrationChild = .{};
    var parent: IntegrationParent = .{ .child = Cmd.initWithCtx(&child, IntegrationChild) };
    const cmd = Cmd.initWithCtx(&parent, IntegrationParent);

    try cmd.execute(.{
        .allocator = t.allocator,
        .args = &.{ "--trace", "child", "--output=dest", "-f=false", "payload", "--", "--output=ignored" },
    });
    try t.expectEqual(@as(usize, 1), parent.executions);
    try t.expectEqual(@as(usize, 1), child.executions);
}

test "public command API propagates a child option error after parent execution" {
    var child: IntegrationChild = .{};
    var parent: IntegrationParent = .{ .child = Cmd.initWithCtx(&child, IntegrationChild) };
    const cmd = Cmd.initWithCtx(&parent, IntegrationParent);

    try t.expectError(error.InvalidOptionValueFound, cmd.execute(.{
        .allocator = t.allocator,
        .args = &.{ "--trace", "child", "-f=maybe" },
    }));
    try t.expectEqual(@as(usize, 1), parent.executions);
    try t.expectEqual(@as(usize, 0), child.executions);
}
