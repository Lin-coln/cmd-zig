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

test "stateful adapter preserves the original instance and shares its vtable" {
    const Cmd = @import("Self.zig");
    var a = struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "root",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        executions: usize = 0,
        arg_count: usize = 0,
        help: bool = false,

        pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            self.executions += 1;
            self.arg_count = ctx.args.len;
            self.help = (try opts.get(bool, "help")) orelse false;
        }
    }{};
    var b: @TypeOf(a) = .{};
    const ca = Cmd.initWithCtx(&a, @TypeOf(a));
    const cb = Cmd.initWithCtx(&b, @TypeOf(b));
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{ "input", "--help" } };
    try t.expect(ca.vt == cb.vt);
    try t.expect(ca.ptr == @as(?*anyopaque, &a));
    try t.expect(ca.vt.querySubCommand == null);
    try t.expect(ca.vt.querySubManifests == null);
    try ca.execute(ctx);
    try ca.execute(ctx);
    try cb.execute(ctx);
    try t.expectEqual(@as(usize, 2), a.executions);
    try t.expectEqual(@as(usize, 1), b.executions);
    try t.expectEqual(@as(usize, 1), a.arg_count);
    try t.expect(a.help and b.help);
}

test "dynamic query handlers receive mutable instance state" {
    const Cmd = @import("Self.zig");
    const leaf = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "child",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        pub fn onExecute(ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            try t.expectEqual(@as(usize, 2), ctx.args.len);
            try t.expectEqualStrings("child", ctx.args[0]);
            try t.expectEqualStrings("payload", ctx.args[1]);
            try t.expect((try opts.get(bool, "help")).?);
        }
    });
    var parent = struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "root",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        executions: usize = 0,
        queries: usize = 0,
        manifest_queries: usize = 0,
        child: Cmd,
        manifests: [1]Cmd.Manifest,

        pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            self.executions += 1;
            try t.expectEqual(@as(usize, 0), ctx.args.len);
            try t.expect((try opts.get(bool, "help")).?);
        }
        pub fn querySubCommand(self: *@This(), _: Cmd.Context, name: []const u8) ?Cmd {
            self.queries += 1;
            return if (std.mem.eql(u8, name, self.child.manifest.name)) self.child else null;
        }
        pub fn querySubManifests(self: *@This(), _: Cmd.Context) ?[]const Cmd.Manifest {
            self.manifest_queries += 1;
            return &self.manifests;
        }
    }{ .child = leaf, .manifests = .{leaf.manifest} };
    const cmd = Cmd.initWithCtx(&parent, @TypeOf(parent));
    const context: Cmd.Context = .{ .allocator = t.allocator, .args = &.{ "--help", "child", "payload", "-h" } };
    try cmd.execute(context);
    try t.expect(parent.queries > 0);
    try t.expectEqual(@as(usize, 1), parent.executions);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, context).?[0].name);
    try t.expectEqual(@as(usize, 1), parent.manifest_queries);

    var child = struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "child",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        executions: usize = 0,
        pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            self.executions += 1;
            try t.expectEqual(@as(usize, 2), ctx.args.len);
            try t.expectEqualStrings("child", ctx.args[0]);
            try t.expectEqualStrings("payload", ctx.args[1]);
            try t.expect((try opts.get(bool, "help")).?);
        }
    }{};
    parent.child = Cmd.initWithCtx(&child, @TypeOf(child));
    try cmd.execute(context);
    try t.expectEqual(@as(usize, 2), parent.executions);
    try t.expectEqual(@as(usize, 1), child.executions);
}

test "stateful adapter propagates handler errors" {
    const Cmd = @import("Self.zig");
    var instance = struct {
        pub const manifest: Cmd.Manifest = .{ .name = "failing" };
        attempted: bool = false,
        pub fn onExecute(self: *@This(), _: Cmd.Context, _: *const Cmd.OptionRecord) error{DynamicFailure}!void {
            self.attempted = true;
            return error.DynamicFailure;
        }
    }{};
    const cmd = Cmd.initWithCtx(&instance, @TypeOf(instance));
    try t.expectError(error.DynamicFailure, cmd.execute(.{ .allocator = t.allocator, .args = &.{} }));
    try t.expect(instance.attempted);
}
