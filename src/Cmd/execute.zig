const std = @import("std");
const t = std.testing;
const Args = @import("../Args/Self.zig");
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
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

    try checkOptions(self.manifest, opts);

    const args = try args_ls.toOwnedSlice(allocator);
    defer allocator.free(args);

    try self.vt.onExecute(
        self.ptr,
        .{ .allocator = allocator, .args = args },
        opts,
    );
}

fn checkOptions(manifest: Manifest, opts: *OptionRecord) !void {
    const options = manifest.options orelse return;
    for (options) |opt| {
        if (opts.map.contains(opt.key)) continue;
        if (opt.default) |value| {
            try opts.set(opt.key, value);
        } else if (opt.required) {
            return error.RequiredOptionNotFound;
        }
    }
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

test "execute parses declared options and passes through other arguments" {
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

test "execute returns an error for an invalid value of a declared option" {
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

test "checkOptions rejects a missing required option" {
    const manifest: Manifest = .{
        .name = "run",
        .options = &.{
            .{ .key = "verbose", .type = .boolean },
            .{ .key = "output", .required = true },
        },
    };
    const opts = try OptionRecord.create(t.allocator);
    defer opts.destroy();

    try t.expectError(error.RequiredOptionNotFound, checkOptions(manifest, opts));
    try opts.set("output", .{ .string = "file" });
    try checkOptions(manifest, opts);
    try t.expect((try opts.get(bool, "verbose")) == null);
}

test "checkOptions fills a default without replacing a stored option" {
    const manifest: Manifest = .{
        .name = "run",
        .options = &.{.{ .key = "count", .type = .int, .required = true, .default = .{ .int = 5 } }},
    };
    const opts = try OptionRecord.create(t.allocator);
    defer opts.destroy();

    try checkOptions(manifest, opts);
    try t.expectEqual(@as(i64, 5), (try opts.get(i64, "count")).?);

    try opts.set("count", .{ .int = -2 });
    try checkOptions(manifest, opts);
    try t.expectEqual(@as(i64, -2), (try opts.get(i64, "count")).?);
}

test "execute runs the parent before the child with their respective arguments" {
    const Cmd = @import("Self.zig");
    var stage: usize = 0;
    var child = struct {
        pub const manifest: Cmd.Manifest = .{ .name = "child" };
        stage: *usize,
        calls: usize = 0,
        saw_args: bool = false,
        pub fn onExecute(self: *@This(), ctx: Cmd.Context, _: *const Cmd.OptionRecord) !void {
            self.stage.* = if (self.stage.* == 1) 2 else 999;
            self.calls += 1;
            self.saw_args = ctx.args.len == 2 and
                std.mem.eql(u8, ctx.args[0], "child") and
                std.mem.eql(u8, ctx.args[1], "payload");
        }
    }{ .stage = &stage };
    var parent = struct {
        pub const manifest: Cmd.Manifest = .{ .name = "parent" };
        stage: *usize,
        child: Cmd,
        calls: usize = 0,
        saw_empty_args: bool = false,
        pub fn onExecute(self: *@This(), ctx: Cmd.Context, _: *const Cmd.OptionRecord) !void {
            self.stage.* = if (self.stage.* == 0) 1 else 999;
            self.calls += 1;
            self.saw_empty_args = ctx.args.len == 0;
        }
        pub fn querySubCommand(self: *@This(), _: Cmd.Context, name: []const u8) ?Cmd {
            return if (std.mem.eql(u8, name, "child")) self.child else null;
        }
    }{ .stage = &stage, .child = Cmd.initWithCtx(&child, @TypeOf(child)) };
    try Cmd.initWithCtx(&parent, @TypeOf(parent)).execute(.{
        .allocator = t.allocator,
        .args = &.{ "child", "payload" },
    });
    try t.expectEqual(@as(usize, 1), parent.calls);
    try t.expect(parent.saw_empty_args);
    try t.expectEqual(@as(usize, 1), child.calls);
    try t.expect(child.saw_args);
    try t.expectEqual(@as(usize, 2), stage);
}

test "querySubCommand returns null without a callback and forwards a lookup when present" {
    const Cmd = @import("Self.zig");
    const without_query = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "parent" };
        pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
    });
    const with_query = Cmd.init(struct {
        pub const manifest: Cmd.Manifest = .{ .name = "parent" };
        pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
        pub fn querySubCommand(_: Cmd.Context, name: []const u8) ?Cmd {
            if (!std.mem.eql(u8, name, "child")) return null;
            return Cmd.init(struct {
                pub const manifest: Cmd.Manifest = .{ .name = "child" };
                pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
            });
        }
    });
    const ctx: Cmd.Context = .{ .allocator = t.allocator, .args = &.{} };
    try t.expect(querySubCommand(without_query, ctx, "child") == null);
    try t.expect(querySubCommand(with_query, ctx, "missing") == null);
    try t.expectEqualStrings("child", querySubCommand(with_query, ctx, "child").?.manifest.name);
}

test "resolveNextEntry returns the first child before the terminator or null when none exists" {
    const Cmd = @import("Self.zig");
    var handler = struct {
        pub const manifest: Cmd.Manifest = .{ .name = "parent" };
        queries: usize = 0,
        pub fn onExecute(_: *@This(), _: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
        pub fn querySubCommand(self: *@This(), _: Cmd.Context, name: []const u8) ?Cmd {
            self.queries += 1;
            if (!std.mem.eql(u8, name, "child")) return null;
            return Cmd.init(struct {
                pub const manifest: Cmd.Manifest = .{ .name = "child" };
                pub fn onExecute(_: Cmd.Context, _: *const Cmd.OptionRecord) !void {}
            });
        }
    }{};
    const cmd = Cmd.initWithCtx(&handler, @TypeOf(handler));

    const found = resolveNextEntry(cmd, .{ .allocator = t.allocator, .args = &.{ "other", "child", "child" } }).?;
    try t.expectEqual(@as(usize, 1), found.idx);
    try t.expectEqualStrings("child", found.cmd.manifest.name);
    try t.expectEqual(@as(usize, 2), handler.queries);

    try t.expect(resolveNextEntry(cmd, .{ .allocator = t.allocator, .args = &.{ "other", "--", "child" } }) == null);
    try t.expectEqual(@as(usize, 3), handler.queries);
    try t.expect(resolveNextEntry(cmd, .{ .allocator = t.allocator, .args = &.{"missing"} }) == null);
    try t.expectEqual(@as(usize, 4), handler.queries);
    const first = resolveNextEntry(cmd, .{ .allocator = t.allocator, .args = &.{"child"} }).?;
    try t.expectEqual(@as(usize, 0), first.idx);
    try t.expectEqual(@as(usize, 5), handler.queries);
    try t.expect(resolveNextEntry(cmd, .{ .allocator = t.allocator, .args = &.{} }) == null);
    try t.expectEqual(@as(usize, 5), handler.queries);
}
