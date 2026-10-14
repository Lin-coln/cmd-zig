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

pub fn init(comptime Impls: type) Self {
    if (!@hasDecl(Impls, "manifest")) {
        @compileError(@typeName(Impls) ++ " needs pub const manifest");
    }
    if (@TypeOf(Impls.manifest) != Manifest) {
        @compileError(@typeName(Impls) ++ ".manifest must be Cmd.Manifest, found " ++ @typeName(@TypeOf(Impls.manifest)));
    }
    if (!@hasDecl(Impls, "onExecute")) {
        @compileError(@typeName(Impls) ++ " needs onExecute");
    }

    const Static = struct {
        const vt: VTable = .{
            .onExecute = onExecute,
            .querySubCommand = if (@hasDecl(Impls, "querySubCommand") and @TypeOf(Impls.querySubCommand) != @TypeOf(null)) querySubCommand else null,
            .querySubManifests = if (@hasDecl(Impls, "querySubManifests") and @TypeOf(Impls.querySubManifests) != @TypeOf(null)) querySubManifests else null,
        };

        fn onExecute(raw: ?*anyopaque, ctx: Context, opts: *const OptionRecord) anyerror!void {
            if (@typeInfo(@TypeOf(Impls.onExecute)).@"fn".params.len == 3) {
                return Impls.onExecute(raw, ctx, opts);
            }
            return Impls.onExecute(ctx, opts);
        }

        fn querySubCommand(raw: ?*anyopaque, ctx: Context, name: []const u8) ?Self {
            if (@typeInfo(@TypeOf(Impls.querySubCommand)).@"fn".params.len == 3) {
                return Impls.querySubCommand(raw, ctx, name);
            }
            return Impls.querySubCommand(ctx, name);
        }

        fn querySubManifests(raw: ?*anyopaque, ctx: Context) ?[]const Manifest {
            if (@typeInfo(@TypeOf(Impls.querySubManifests)).@"fn".params.len == 2) {
                return Impls.querySubManifests(raw, ctx);
            }
            return Impls.querySubManifests(ctx);
        }
    };

    return .{ .manifest = Impls.manifest, .vt = &Static.vt };
}

test "comptime stateless command executes without optional handlers" {
    const Cmd = @import("Self.zig");
    const cmd = comptime Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "root",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        pub fn onExecute(ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            try t.expectEqual(@as(usize, 1), ctx.args.len);
            try t.expectEqualStrings("input", ctx.args[0]);
            try t.expect((try opts.get(bool, "help")).?);
        }
    });
    try t.expect(cmd.ptr == null);
    try t.expect(cmd.vt.querySubCommand == null);
    try t.expect(cmd.vt.querySubManifests == null);
    try cmd.execute(.{ .allocator = t.allocator, .args = &.{ "input", "--help" } });
}

test "stateless query handlers enumerate and dispatch subcommands" {
    const Cmd = @import("Self.zig");
    const child = comptime Cmd.init(struct {
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
    const cmd = comptime Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "root",
            .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
        };
        pub fn onExecute(ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            try t.expectEqual(@as(usize, 0), ctx.args.len);
            try t.expect((try opts.get(bool, "help")).?);
        }
        pub fn querySubCommand(_: Cmd.Context, name: []const u8) ?Cmd {
            return if (std.mem.eql(u8, name, "child")) child else null;
        }
        pub fn querySubManifests(_: Cmd.Context) ?[]const Cmd.Manifest {
            return &.{child.manifest};
        }
    });
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{ "--help", "child", "payload", "-h" } };
    try t.expect(cmd.vt.querySubCommand.?(cmd.ptr, ctx, "missing") == null);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, ctx).?[0].name);
    try cmd.execute(ctx);
}

test "stateless adapter propagates handler errors" {
    const Cmd = @import("Self.zig");
    const cmd = comptime Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "failing" };
        pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) error{StaticFailure}!void {
            return error.StaticFailure;
        }
    });
    try t.expectError(error.StaticFailure, cmd.execute(.{ .allocator = t.allocator, .args = &.{} }));
}
