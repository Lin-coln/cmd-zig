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
    _ = @import("Cmd/initWithCtx.zig");
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
        try t.expectEqualStrings("dest", (try opts.get([]const u8, "output")).?);
        try t.expect(!(try opts.get(bool, "force")).?);
        const output_arg = (try opts.getArg("output")).?;
        defer ctx.allocator.free(output_arg);
        try t.expectEqualStrings("--output=dest", output_arg);
        const force_arg = (try opts.getArg("force")).?;
        defer ctx.allocator.free(force_arg);
        try t.expectEqualStrings("--force=false", force_arg);
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
        try t.expect((try opts.get(bool, "trace")).?);
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

test "static and allocated dynamic commands share a collection and preserve instance state" {
    const Context = Cmd.Context;
    const OptionRecord = Cmd.OptionRecord;
    const root_manifest: Cmd.Manifest = .{
        .name = "root",
        .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
    };
    const test_ctx: Context = .{ .allocator = t.allocator, .args = &.{ "input", "--help" } };
    const Static = struct {
        pub const manifest = root_manifest;
        pub fn onExecute(ctx: Context, opts: *const OptionRecord) !void {
            try t.expectEqual(@as(usize, 1), ctx.args.len);
            try t.expectEqualStrings("input", ctx.args[0]);
            try t.expect((try opts.get(bool, "help")).?);
        }
    };
    const static_cmd = Cmd.init(Static);
    const Dynamic = struct {
        pub const manifest = root_manifest;
        executions: usize = 0,
        arg_count: usize = 0,
        help: bool = false,

        pub fn onExecute(self: *@This(), context: Context, opts: *const OptionRecord) !void {
            self.executions += 1;
            self.arg_count = context.args.len;
            self.help = (try opts.get(bool, "help")) orelse false;
        }
    };
    const a = try t.allocator.create(Dynamic);
    defer t.allocator.destroy(a);
    a.* = .{};
    const b = try t.allocator.create(Dynamic);
    defer t.allocator.destroy(b);
    b.* = .{};

    const ca = Cmd.initWithCtx(a, Dynamic);
    const cb = Cmd.initWithCtx(b, Dynamic);
    try t.expect(ca.vt == cb.vt);
    try t.expect(ca.ptr == @as(?*anyopaque, a));
    const commands: []const Cmd = &.{ static_cmd, ca, cb };
    for (commands) |cmd| try cmd.execute(test_ctx);
    try ca.execute(test_ctx);
    try t.expectEqual(@as(usize, 2), a.executions);
    try t.expectEqual(@as(usize, 1), b.executions);
    try t.expectEqual(@as(usize, 1), a.arg_count);
    try t.expect(a.help and b.help);
}
