const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
const OptionRecord = Self.OptionRecord;

const init = @import("init.zig").init;

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
    if (!@hasDecl(Impls, "onExecute")) {
        @compileError(@typeName(Impls) ++ " needs onExecute");
    }

    var cmd = init(struct {
        pub const manifest = Impls.manifest;
        pub const querySubCommand = if (@hasDecl(Impls, "querySubCommand")) querySubCommandFn else null;
        pub const querySubManifests = if (@hasDecl(Impls, "querySubManifests")) querySubManifestsFn else null;

        pub fn onExecute(raw: ?*anyopaque, ctx: Context, opts: *const OptionRecord) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(raw.?));
            return Impls.onExecute(self, ctx, opts);
        }

        fn querySubCommandFn(raw: ?*anyopaque, ctx: Context, name: []const u8) ?Self {
            const self: Ptr = @ptrCast(@alignCast(raw.?));
            return Impls.querySubCommand(self, ctx, name);
        }

        fn querySubManifestsFn(raw: ?*anyopaque, ctx: Context) ?[]const Manifest {
            const self: Ptr = @ptrCast(@alignCast(raw.?));
            return Impls.querySubManifests(self, ctx);
        }
    });
    cmd.ptr = typed;
    return cmd;
}

const Cmd = Self;

const root_manifest: Cmd.Manifest = .{
    .name = "root",
    .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
};
const test_ctx: Context = .{
    .allocator = t.allocator,
    .args = &.{ "input", "--help" },
};

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

test "stateful adapter preserves the original instance and shares its vtable" {
    var a: Dynamic = .{};
    var b: Dynamic = .{};
    const ca = initWithCtx(&a, Dynamic);
    const cb = initWithCtx(&b, Dynamic);
    try t.expect(ca.vt == cb.vt);
    try t.expect(ca.ptr == @as(?*anyopaque, &a));
    try t.expect(ca.vt.querySubCommand == null);
    try t.expect(ca.vt.querySubManifests == null);
    try ca.execute(test_ctx);
    try ca.execute(test_ctx);
    try cb.execute(test_ctx);
    try t.expectEqual(@as(usize, 2), a.executions);
    try t.expectEqual(@as(usize, 1), b.executions);
    try t.expectEqual(@as(usize, 1), a.arg_count);
    try t.expect(a.help and b.help);
}

const Leaf = struct {
    pub const manifest: Cmd.Manifest = .{ .name = "child", .options = root_manifest.options };
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try t.expectEqual(@as(usize, 2), context.args.len);
        try t.expectEqualStrings("child", context.args[0]);
        try t.expectEqualStrings("payload", context.args[1]);
        try t.expect((try opts.get(bool, "help")).?);
    }
};
const child_manifest = Leaf.manifest;
const leaf_cmd = Cmd.init(Leaf);
const child_ctx: Context = .{
    .allocator = t.allocator,
    .args = &.{ "--help", "child", "payload", "-h" },
};

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
    try t.expect(parent.queries > 0);
    try t.expectEqual(@as(usize, 1), parent.state.executions);
    try t.expectEqual(@as(usize, 0), parent.state.arg_count);
    try t.expect(parent.state.help);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, child_ctx).?[0].name);
    try t.expectEqual(@as(usize, 1), parent.manifest_queries);

    const DynamicChild = struct {
        pub const manifest = child_manifest;
        pub const onExecute = Dynamic.onExecute;
    };
    var child: Dynamic = .{};
    parent.child = Cmd.initWithCtx(&child, DynamicChild);
    try cmd.execute(child_ctx);
    try t.expectEqual(@as(usize, 1), child.executions);
    try t.expectEqual(@as(usize, 2), child.arg_count);
    try t.expect(child.help);
}

test "stateful adapter propagates handler errors" {
    const Failing = struct {
        pub const manifest = root_manifest;
        attempted: bool = false,
        pub fn onExecute(self: *@This(), _: Context, _: *const OptionRecord) error{DynamicFailure}!void {
            self.attempted = true;
            return error.DynamicFailure;
        }
    };
    var instance: Failing = .{};
    const cmd = initWithCtx(&instance, Failing);
    try t.expectError(error.DynamicFailure, cmd.execute(test_ctx));
    try t.expect(instance.attempted);
}
