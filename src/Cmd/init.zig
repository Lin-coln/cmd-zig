const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
const OptionRecord = Self.OptionRecord;

pub const VTable = struct {
    onExecute: *const fn (?*anyopaque, Context, *const OptionRecord) anyerror!void,
    querySubCommand: ?*const fn (?*anyopaque, Context, []const u8) ?Self = null,
    querySubManifests: ?*const fn (?*anyopaque, Context) ?[]const Manifest = null,
};

/// Borrow an instance that must outlive every use of the returned command.
/// Handlers receive the original pointer type as their first argument.
/// Impls declares pub const manifest and pub fn onExecute.
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

    const Impl = Adapter(Ptr, Impls);
    return .{
        .manifest = Impl.manifest,
        .ptr = typed,
        .vt = &Impl.vt,
    };
}

/// Construct a stateless command, including at comptime.
/// Handlers receive Context first, with no instance argument.
/// Impls declares pub const manifest and pub fn onExecute.
pub fn init(comptime Impls: type) Self {
    const Impl = Adapter(null, Impls);
    return .{
        .manifest = Impl.manifest,
        .ptr = null,
        .vt = &Impl.vt,
    };
}

fn Adapter(comptime Ptr: ?type, comptime Impls: type) type {
    if (!@hasDecl(Impls, "manifest")) {
        @compileError(@typeName(Impls) ++ " needs pub const manifest");
    }
    if (@TypeOf(Impls.manifest) != Manifest) {
        @compileError(@typeName(Impls) ++ ".manifest must be Cmd.Manifest, found " ++ @typeName(@TypeOf(Impls.manifest)));
    }
    if (!@hasDecl(Impls, "onExecute")) {
        @compileError(@typeName(Impls) ++ " needs onExecute");
    }

    return struct {
        const manifest: Manifest = Impls.manifest;
        const vt: VTable = .{
            .onExecute = onExecute,
            .querySubCommand = if (@hasDecl(Impls, "querySubCommand")) querySubCommand else null,
            .querySubManifests = if (@hasDecl(Impls, "querySubManifests")) querySubManifests else null,
        };

        fn onExecute(raw: ?*anyopaque, ctx: Context, opts: *const OptionRecord) anyerror!void {
            if (Ptr) |P| {
                const self: P = @ptrCast(@alignCast(raw.?));
                return Impls.onExecute(self, ctx, opts);
            }
            return Impls.onExecute(ctx, opts);
        }

        fn querySubCommand(raw: ?*anyopaque, ctx: Context, name: []const u8) ?Self {
            if (Ptr) |P| {
                const self: P = @ptrCast(@alignCast(raw.?));
                return Impls.querySubCommand(self, ctx, name);
            }
            return Impls.querySubCommand(ctx, name);
        }

        fn querySubManifests(raw: ?*anyopaque, ctx: Context) ?[]const Manifest {
            if (Ptr) |P| {
                const self: P = @ptrCast(@alignCast(raw.?));
                return Impls.querySubManifests(self, ctx);
            }
            return Impls.querySubManifests(ctx);
        }
    };
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

const Static = struct {
    pub const manifest = root_manifest;
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try t.expectEqual(@as(usize, 1), context.args.len);
        try t.expectEqualStrings("input", context.args[0]);
        try t.expect(opts.map.get("help").?.boolean);
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
    try t.expect(cmd.ptr == null);
    try t.expect(cmd.vt.querySubCommand == null);
    try t.expect(cmd.vt.querySubManifests == null);
    try cmd.execute(test_ctx);
}

test "static and allocated dynamic commands share a collection and preserve instance state" {
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

const Leaf = struct {
    pub const manifest: Cmd.Manifest = .{ .name = "child", .options = root_manifest.options };
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try t.expectEqual(@as(usize, 2), context.args.len);
        try t.expectEqualStrings("child", context.args[0]);
        try t.expectEqualStrings("payload", context.args[1]);
        try t.expect(opts.map.get("help").?.boolean);
    }
};
const child_manifest = Leaf.manifest;
const leaf_cmd = Cmd.init(Leaf);
const child_ctx: Context = .{
    .allocator = t.allocator,
    .args = &.{ "--help", "child", "payload", "-h" },
};

const StaticParent = struct {
    pub const manifest = root_manifest;
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try t.expectEqual(@as(usize, 0), context.args.len);
        try t.expect(opts.map.get("help").?.boolean);
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
    try t.expect(cmd.vt.querySubCommand.?(cmd.ptr, child_ctx, "missing") == null);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, child_ctx).?[0].name);
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
    try t.expect(parent.queries > 0);
    try t.expectEqual(@as(usize, 1), parent.state.executions);
    try t.expectEqual(@as(usize, 0), parent.state.arg_count);
    try t.expect(parent.state.help);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, child_ctx).?[0].name);
    try t.expectEqual(@as(usize, 1), parent.manifest_queries);

    // A runtime parent can also select a stateful child.
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
    try t.expectError(error.StaticFailure, failing_static.execute(test_ctx));
    var instance: FailingDynamic = .{};
    const failing_dynamic = Cmd.initWithCtx(&instance, FailingDynamic);
    try t.expectError(error.DynamicFailure, failing_dynamic.execute(test_ctx));
    try t.expect(instance.attempted);
}
