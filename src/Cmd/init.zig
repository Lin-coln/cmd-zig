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

const Cmd = Self;

const root_manifest: Cmd.Manifest = .{
    .name = "root",
    .options = &.{.{ .key = "help", .alias = 'h', .type = .boolean }},
};
const test_ctx: Context = .{
    .allocator = t.allocator,
    .args = &.{ "input", "--help" },
};

const StaticShit = struct {
    pub const manifest = root_manifest;
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try t.expectEqual(@as(usize, 1), context.args.len);
        try t.expectEqualStrings("input", context.args[0]);
        try t.expect((try opts.get(bool, "help")).?);
    }
};
test "comptime stateless command executes without optional handlers" {
    const cmd = comptime Cmd.init(StaticShit);
    try t.expect(cmd.ptr == null);
    try t.expect(cmd.vt.querySubCommand == null);
    try t.expect(cmd.vt.querySubManifests == null);
    try cmd.execute(test_ctx);
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

const StaticParent = struct {
    pub const manifest = root_manifest;
    pub fn onExecute(context: Context, opts: *const OptionRecord) !void {
        try t.expectEqual(@as(usize, 0), context.args.len);
        try t.expect((try opts.get(bool, "help")).?);
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

test "stateless adapter propagates handler errors" {
    const Failing = struct {
        pub const manifest = root_manifest;
        pub fn onExecute(_: Context, _: *const OptionRecord) error{StaticFailure}!void {
            return error.StaticFailure;
        }
    };
    const cmd = comptime init(Failing);
    try t.expectError(error.StaticFailure, cmd.execute(test_ctx));
}
