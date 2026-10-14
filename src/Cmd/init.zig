const std = @import("std");
const t = std.testing;
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = @import("../Manifest/Self.zig");
const Option = @import("../Option/Self.zig");
const OptionRecord = @import("../Option/Record.zig");

pub const VTable = struct {
    onExecute: *const fn (?*anyopaque, Context, *const OptionRecord) anyerror!void,
    querySubCommand: ?*const fn (?*anyopaque, Context, []const u8) ?Self = null,
    querySubManifests: ?*const fn (?*anyopaque, Context) ?[]const Manifest = null,
};

pub fn init(manifest: Manifest, comptime Impls: type) Self {
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

    return .{ .manifest = manifest, .vt = &Static.vt };
}

test "Cmd.init: leaves the instance and undeclared callbacks null" {
    const Cmd = @import("Self.zig");
    const cmd = comptime Cmd.init(.{ .name = "root" }, struct {
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) !void {}
    });
    try t.expect(cmd.ptr == null);
    try t.expectEqualStrings("root", cmd.manifest.name);
    try t.expect(cmd.vt.querySubCommand == null);
    try t.expect(cmd.vt.querySubManifests == null);
}

test "Cmd.init: forwards onExecute to a stateless handler" {
    const Cmd = @import("Self.zig");
    const cmd = comptime Cmd.init(.{ .name = "root" }, struct {
        pub fn onExecute(ctx: Cmd.Context, opts: *const OptionRecord) !void {
            try t.expectEqual(@as(usize, 1), ctx.args.len);
            try t.expectEqualStrings("input", ctx.args[0]);
            try t.expect((try opts.get(bool, "help")).?);
        }
    });
    const opts = try OptionRecord.create(t.allocator);
    defer opts.destroy();
    try opts.set("help", .{ .boolean = true });
    try cmd.vt.onExecute(cmd.ptr, .{ .allocator = t.allocator, .args = &.{"input"} }, opts);
}

test "Cmd.init: forwards subcommand and manifest queries through the vtable" {
    const Cmd = @import("Self.zig");
    const child = comptime Cmd.init(.{
        .name = "child",
        .options = &.{Option.boolean("-h, --help")},
    }, struct {
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) !void {}
    });
    const cmd = comptime Cmd.init(.{
        .name = "root",
        .options = &.{Option.boolean("-h, --help")},
    }, struct {
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) !void {}
        pub fn querySubCommand(_: Cmd.Context, name: []const u8) ?Cmd {
            return if (std.mem.eql(u8, name, "child")) child else null;
        }
        pub fn querySubManifests(_: Cmd.Context) ?[]const Manifest {
            return &.{child.manifest};
        }
    });
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{ "--help", "child", "payload", "-h" } };
    try t.expect(cmd.vt.querySubCommand.?(cmd.ptr, ctx, "missing") == null);
    try t.expectEqualStrings("child", cmd.vt.querySubCommand.?(cmd.ptr, ctx, "child").?.manifest.name);
    try t.expectEqualStrings("child", cmd.vt.querySubManifests.?(cmd.ptr, ctx).?[0].name);
}

test "Cmd.init: forwards an onExecute error from a stateless handler" {
    const Cmd = @import("Self.zig");
    const cmd = comptime Cmd.init(.{ .name = "failing" }, struct {
        pub fn onExecute(_: Cmd.Context, _: *const OptionRecord) error{StaticFailure}!void {
            return error.StaticFailure;
        }
    });
    const opts = try OptionRecord.create(t.allocator);
    defer opts.destroy();
    try t.expectError(error.StaticFailure, cmd.vt.onExecute(cmd.ptr, .{ .allocator = t.allocator, .args = &.{} }, opts));
}
