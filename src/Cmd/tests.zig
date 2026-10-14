const std = @import("std");
const Cmd = @import("Self.zig");
const Context = Cmd.Context;
const OptionRecord = Cmd.OptionRecord;

const root_manifest: Cmd.Manifest = .{
    .name = "root",
    .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
};
const ctx: Context = .{
    .allocator = std.testing.allocator,
    .args = &.{ "input", "--help" },
};

const Static = struct {
    pub const manifest = root_manifest;
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try std.testing.expectEqual(@as(usize, 1), context.args.len);
        try std.testing.expectEqualStrings("input", context.args[0]);
        try std.testing.expect(opts.map.get("help").?.boolean);
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
        self.help = if (opts.map.get("help")) |value| value.boolean else false;
    }
};

test "comptime stateless command executes without optional handlers" {
    const cmd = comptime Cmd.init(Static);
    try std.testing.expect(cmd.ptr == null);
    try std.testing.expect(cmd.vt.querySubCommand == null);
    try std.testing.expect(cmd.vt.querySubManifests == null);
    try cmd.execute(ctx);
}

test "static and allocated dynamic commands share a collection and preserve instance state" {
    const a = try std.testing.allocator.create(Dynamic);
    defer std.testing.allocator.destroy(a);
    a.* = .{};
    const b = try std.testing.allocator.create(Dynamic);
    defer std.testing.allocator.destroy(b);
    b.* = .{};

    const ca = Cmd.initWithCtx(a, Dynamic);
    const cb = Cmd.initWithCtx(b, Dynamic);
    try std.testing.expect(ca.vt == cb.vt);
    try std.testing.expect(ca.ptr == @as(?*anyopaque, a));
    const commands: []const Cmd = &.{ static_cmd, ca, cb };
    for (commands) |cmd| try cmd.execute(ctx);
    try ca.execute(ctx);
    try std.testing.expectEqual(@as(usize, 2), a.executions);
    try std.testing.expectEqual(@as(usize, 1), b.executions);
    try std.testing.expectEqual(@as(usize, 1), a.arg_count);
    try std.testing.expect(a.help and b.help);
}

const Leaf = struct {
    pub const manifest: Cmd.Manifest = .{ .name = "child", .options = root_manifest.options };
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try std.testing.expectEqual(@as(usize, 2), context.args.len);
        try std.testing.expectEqualStrings("child", context.args[0]);
        try std.testing.expectEqualStrings("payload", context.args[1]);
        try std.testing.expect(opts.map.get("help").?.boolean);
    }
};
const child_manifest = Leaf.manifest;
const leaf_cmd = Cmd.init(Leaf);
const child_ctx: Context = .{
    .allocator = std.testing.allocator,
    .args = &.{ "--help", "child", "payload", "-h" },
};

const StaticParent = struct {
    pub const manifest = root_manifest;
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try std.testing.expectEqual(@as(usize, 0), context.args.len);
        try std.testing.expect(opts.map.get("help").?.boolean);
    }
    pub fn querySubCommand(_: Context, name: []const u8) ?Cmd {
        return if (std.mem.eql(u8, name, "child")) leaf_cmd else null;
    }
    pub fn querySubManifests(_: Context) ?[]const Cmd.Manifest {
        return &.{child_manifest};
    }
};

test "stateless query handlers enumerate and dispatch subcommands" {
    const cmd = comptime Cmd.init(StaticParent);
    try std.testing.expect(cmd.vt.querySubCommand.?(cmd.ptr, child_ctx, "missing") == null);
    try std.testing.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, child_ctx).?[0].name);
    try cmd.execute(child_ctx);
}

test "dynamic query handlers receive mutable instance state" {
    const Parent = struct {
        pub const manifest = root_manifest;
        state: Dynamic = .{},
        queries: usize = 0,
        manifest_queries: usize = 0,
        child: Cmd,
        manifests: [1]Cmd.Manifest,

        pub fn onExecute(self: *@This(), context: Context, opts: *const OptionRecord) !void {
            return Dynamic.onExecute(&self.state, context, opts);
        }
        pub fn querySubCommand(self: *@This(), _: Context, name: []const u8) ?Cmd {
            self.queries += 1;
            return if (std.mem.eql(u8, name, self.child.manifest.name)) self.child else null;
        }
        pub fn querySubManifests(self: *@This(), _: Context) ?[]const Cmd.Manifest {
            self.manifest_queries += 1;
            return &self.manifests;
        }
    };
    var parent: Parent = .{ .child = leaf_cmd, .manifests = .{child_manifest} };
    const cmd = Cmd.initWithCtx(&parent, Parent);
    try cmd.execute(child_ctx);
    try std.testing.expect(parent.queries > 0);
    try std.testing.expectEqual(@as(usize, 1), parent.state.executions);
    try std.testing.expectEqual(@as(usize, 0), parent.state.arg_count);
    try std.testing.expect(parent.state.help);
    try std.testing.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, child_ctx).?[0].name);
    try std.testing.expectEqual(@as(usize, 1), parent.manifest_queries);

    // A runtime parent can also select a stateful child.
    const DynamicChild = struct {
        pub const manifest = child_manifest;
        pub const onExecute = Dynamic.onExecute;
    };
    var child: Dynamic = .{};
    parent.child = Cmd.initWithCtx(&child, DynamicChild);
    try cmd.execute(child_ctx);
    try std.testing.expectEqual(@as(usize, 1), child.executions);
    try std.testing.expectEqual(@as(usize, 2), child.arg_count);
    try std.testing.expect(child.help);
}

test "static and dynamic adapters propagate handler errors" {
    const FailingStatic = struct {
        pub const manifest = root_manifest;
        pub fn onExecute(_: Context, _: *const OptionRecord) error{StaticFailure}!void {
            return error.StaticFailure;
        }
    };
    const FailingDynamic = struct {
        pub const manifest = root_manifest;
        attempted: bool = false,
        pub fn onExecute(self: *@This(), _: Context, _: *const OptionRecord) error{DynamicFailure}!void {
            self.attempted = true;
            return error.DynamicFailure;
        }
    };
    const failing_static = comptime Cmd.init(FailingStatic);
    try std.testing.expectError(error.StaticFailure, failing_static.execute(ctx));
    var instance: FailingDynamic = .{};
    const failing_dynamic = Cmd.initWithCtx(&instance, FailingDynamic);
    try std.testing.expectError(error.DynamicFailure, failing_dynamic.execute(ctx));
    try std.testing.expect(instance.attempted);
}
