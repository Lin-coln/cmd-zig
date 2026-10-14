const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
const OptionRecord = @import("../Option/Record.zig");

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

test "initWithCtx binds each instance to its own state and shares the vtable" {
    const Cmd = @import("Self.zig");
    var a = struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "root",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        executions: usize = 0,
        arg_count: usize = 0,
        help: bool = false,

        pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const OptionRecord) !void {
            self.executions += 1;
            self.arg_count = ctx.args.len;
            self.help = (try opts.get(bool, "help")) orelse false;
        }
    }{};
    var b: @TypeOf(a) = .{};
    const ca = Cmd.initWithCtx(&a, @TypeOf(a));
    const cb = Cmd.initWithCtx(&b, @TypeOf(b));
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{"input"} };
    const opts = try OptionRecord.create(t.allocator);
    defer opts.destroy();
    try opts.set("help", .{ .boolean = true });
    try t.expect(ca.vt == cb.vt);
    try t.expect(ca.ptr == @as(?*anyopaque, &a));
    try t.expect(ca.vt.querySubCommand == null);
    try t.expect(ca.vt.querySubManifests == null);
    try ca.vt.onExecute(ca.ptr, ctx, opts);
    try ca.vt.onExecute(ca.ptr, ctx, opts);
    try cb.vt.onExecute(cb.ptr, ctx, opts);
    try t.expectEqual(@as(usize, 2), a.executions);
    try t.expectEqual(@as(usize, 1), b.executions);
    try t.expectEqual(@as(usize, 1), a.arg_count);
    try t.expect(a.help and b.help);
}

test "initWithCtx forwards subcommand and manifest queries to the bound instance" {
    const Cmd = @import("Self.zig");
    const leaf = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "child" };
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) !void {}
    });
    var parent = struct {
        pub const manifest: Cmd.Manifest = .{ .name = "root" };
        queries: usize = 0,
        manifest_queries: usize = 0,
        child: Cmd,
        manifests: [1]Cmd.Manifest,

        pub fn onExecute(_: *@This(), _: Cmd.Context, _: *const OptionRecord) !void {}
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
    const context: Cmd.Context = .{ .allocator = t.allocator, .args = &.{} };
    try t.expect(cmd.vt.querySubCommand.?(cmd.ptr, context, "missing") == null);
    try t.expectEqualStrings("child", cmd.vt.querySubCommand.?(cmd.ptr, context, "child").?.manifest.name);
    try t.expectEqual(@as(usize, 2), parent.queries);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, context).?[0].name);
    try t.expectEqual(@as(usize, 1), parent.manifest_queries);
}

test "initWithCtx forwards an onExecute error from the bound instance" {
    const Cmd = @import("Self.zig");
    var instance = struct {
        pub const manifest: Cmd.Manifest = .{ .name = "failing" };
        attempted: bool = false,
        pub fn onExecute(self: *@This(), _: Cmd.Context, _: *const OptionRecord) error{DynamicFailure}!void {
            self.attempted = true;
            return error.DynamicFailure;
        }
    }{};
    const cmd = Cmd.initWithCtx(&instance, @TypeOf(instance));
    const opts = try OptionRecord.create(t.allocator);
    defer opts.destroy();
    try t.expectError(error.DynamicFailure, cmd.vt.onExecute(cmd.ptr, .{ .allocator = t.allocator, .args = &.{} }, opts));
    try t.expect(instance.attempted);
}
