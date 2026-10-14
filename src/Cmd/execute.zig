const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");
const Self = @import("Self.zig");
const Context = Self.Context;
const OptionRecord = Self.OptionRecord;

pub fn execute(self: Self, ctx: Context) !void {
    const next = resolveNextEntry(self, ctx);
    if (next) |sub| {
        const ctx1, const ctx2 = ctx.split(sub.idx);
        try self.execute(ctx1);
        try sub.cmd.execute(ctx2);
        return;
    }

    const allocator = ctx.allocator;

    var opts: *OptionRecord = try .create(allocator);
    defer opts.destroy();

    var args_ls: std.ArrayList([]const u8) = .empty;
    defer args_ls.deinit(allocator);

    var after_double_dash: bool = false;
    for (ctx.args) |arg| {
        const desc: Args.Descriptor = if (after_double_dash)
            .{ .unknown = arg }
        else
            Args.parseDescriptorFromArg(arg);
        switch (desc) {
            .doubleDash => {
                after_double_dash = true;
                continue;
            },
            .option => |d| {
                const option = blk: {
                    const options = self.manifest.options orelse break :blk null;
                    for (options) |*opt| if (opt.match(d)) break :blk opt;
                    break :blk null;
                };
                if (option) |opt| {
                    try opts.set(opt.key, try opt.parse(d));
                    continue;
                }
            },
            .unknown => |str| {
                try args_ls.append(allocator, str);
                continue;
            },
        }

        // cannot be parsed, as arg
        try args_ls.append(allocator, arg);
    }

    const args = try args_ls.toOwnedSlice(allocator);
    defer allocator.free(args);

    try self.vt.onExecute(
        self.ptr,
        .{ .allocator = allocator, .args = args },
        opts,
    );
}

fn resolveNextEntry(self: Self, ctx: Context) ?struct { cmd: Self, idx: usize } {
    for (ctx.args, 0..) |arg, idx| {
        if (std.mem.eql(u8, arg, "--")) break;
        const cmd = querySubCommand(self, ctx, arg) orelse continue;
        return .{ .cmd = cmd, .idx = idx };
    }
    return null;
}

fn querySubCommand(self: Self, ctx: Context, name: []const u8) ?Self {
    const f = self.vt.querySubCommand orelse return null;
    return f(self.ptr, ctx, name);
}

test "execute passes positional and unknown options through after parsing known options" {
    const Cmd = @import("Self.zig");
    var handler = struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "run",
            .options = &.{.{ .key = "verbose", .alias = 'v', .type = .boolean }},
        };
        calls: usize = 0,
        pub fn onExecute(self: *@This(), ctx: Cmd.Context, opts: *const Cmd.OptionRecord) !void {
            self.calls += 1;
            try t.expectEqual(@as(usize, 4), ctx.args.len);
            try t.expectEqualStrings("file", ctx.args[0]);
            try t.expectEqualStrings("--unknown", ctx.args[1]);
            try t.expectEqualStrings("-v", ctx.args[2]);
            try t.expectEqualStrings("--verbose=false", ctx.args[3]);
            try t.expect((try opts.get(bool, "verbose")).?);
        }
    }{};
    const cmd = Cmd.initWithCtx(&handler, @TypeOf(handler));
    try cmd.execute(.{
        .allocator = t.allocator,
        .args = &.{ "file", "--unknown", "-v", "--", "-v", "--verbose=false" },
    });
    try t.expectEqual(@as(usize, 1), handler.calls);
}

test "execute propagates invalid known option value" {
    const Cmd = @import("Self.zig");
    const cmd = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{
            .name = "run",
            .options = &.{.{ .key = "verbose", .type = .boolean }},
        };
        pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {
            return error.UnexpectedExecution;
        }
    });
    try t.expectError(error.InvalidOptionValueFound, cmd.execute(.{
        .allocator = t.allocator,
        .args = &.{"--verbose=yes"},
    }));
}

test "double dash prevents subcommand lookup" {
    const Cmd = @import("Self.zig");
    const cmd = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "parent" };
        pub fn onExecute(ctx: Cmd.Context, _: *const Cmd.OptionRecord) !void {
            try t.expectEqual(@as(usize, 1), ctx.args.len);
            try t.expectEqualStrings("child", ctx.args[0]);
        }
        pub fn querySubCommand(_: Cmd.Context, _: []const u8) ?Cmd {
            return Cmd.init(struct {
                pub const manifest: Cmd.Manifest = .{ .name = "child" };
                pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {
                    return error.UnexpectedSubcommand;
                }
            });
        }
    });
    try cmd.execute(.{ .allocator = t.allocator, .args = &.{ "--", "child" } });
}
