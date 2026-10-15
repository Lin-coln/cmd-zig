const std = @import("std");
const builtin = @import("builtin");
const cmd = @import("cmd");
const Allocator = std.mem.Allocator;
const Cmd = cmd.Cmd;
const Context = cmd.Context;
const Option = cmd.Option;
const OptionValues = cmd.OptionValues;

extern "kernel32" fn SetConsoleOutputCP(code_page: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
    }

    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    // Keep the binary path supplied by the process as args[0].
    var app: App = .{};
    try app.command().execute(.{ .allocator = allocator, .args = args });
}

const foo_spec: cmd.CmdSpec = .{
    .name = "foo",
    .desc = "Options and lazy nested execution",
    .options = &.{Option.boolean("-h, --help")},
};

const child_spec: cmd.CmdSpec = .{
    .name = "child",
    .desc = "Create command state only when executing the child",
    .options = &.{Option.int("-c, --count=<val>")},
};

const App = struct {
    executions: usize = 0,

    const Parsed = cmd.WithOptions(App, foo_spec.options, run);
    const Routed = cmd.WithSubcommands(App, Parsed.execute, App);

    fn command(self: *App) Cmd {
        return Cmd.initWithCtx(self, Routed);
    }

    fn run(self: *App, ctx: Context, opts: *const OptionValues) !void {
        self.executions += 1;
        std.log.info("foo execution #{d}", .{self.executions});
        for (ctx.args) |arg| std.log.info("{s}", .{arg});
        opts.print();

        if ((try opts.get(bool, "help")) orelse false) {
            for ((try self.querySubSpecs(ctx)).?) |spec| {
                std.log.info("{s}: {s}", .{ spec.name, spec.desc orelse "" });
            }
        }
    }

    pub fn querySubCommand(_: *App, _: Context, name: []const u8) !?Cmd {
        if (std.mem.eql(u8, name, child_spec.name)) return Cmd.init(LazyChild);
        return null;
    }

    // Metadata is available without creating Child.
    pub fn querySubSpecs(_: *App, _: Context) !?[]const cmd.CmdSpec {
        return &.{child_spec};
    }
};

const LazyChild = struct {
    pub fn execute(ctx: Context) !void {
        const child = try Child.create(ctx.allocator);
        defer child.destroy();

        const Parsed = cmd.WithOptions(Child, child_spec.options, Child.run);
        try Cmd.initWithCtx(child, Parsed).execute(ctx);
    }
};

const Child = struct {
    allocator: Allocator,
    executions: usize = 0,

    fn create(allocator: Allocator) !*Child {
        const self = try allocator.create(Child);
        self.* = .{ .allocator = allocator };
        return self;
    }

    fn destroy(self: *Child) void {
        self.allocator.destroy(self);
    }

    fn run(self: *Child, ctx: Context, opts: *const OptionValues) !void {
        self.executions += 1;
        std.log.info("child execution #{d}", .{self.executions});
        for (ctx.args) |arg| std.log.info("{s}", .{arg});
        opts.print();
    }
};

test "App.querySubSpecs: returns child metadata without loading resources" {
    const t = std.testing;
    var app: App = .{};
    const specs = (try app.querySubSpecs(.{
        .allocator = t.failing_allocator,
        .args = &.{"foo"},
    })).?;
    try t.expectEqualDeep(@as([]const cmd.CmdSpec, &.{child_spec}), specs);
}

test "App.querySubCommand: returns child commands without loading resources" {
    const t = std.testing;
    var app: App = .{};
    const ctx: Context = .{ .allocator = t.failing_allocator, .args = &.{ "/bin/foo", "child" } };
    try t.expect((try app.querySubCommand(ctx, "child")) != null);
    try t.expect((try app.querySubCommand(ctx, "unknown")) == null);
    try t.expectEqual(@as(usize, 0), app.executions);
}

test "App.command: routes child execution and propagates option parsing failure" {
    const t = std.testing;
    var app: App = .{};
    try t.expectError(error.InvalidOptionValueFound, app.command().execute(.{
        .allocator = t.allocator,
        .args = &.{ "/bin/foo", "child", "--count=invalid" },
    }));
    try t.expectEqual(@as(usize, 1), app.executions);
}

test "LazyChild.execute: releases child resources on success and option parsing failure" {
    const t = std.testing;
    const cases = [_]struct {
        args: []const []const u8,
        expected_error: ?anyerror = null,
    }{
        .{ .args = &.{ "child", "--count=3", "payload" } },
        .{ .args = &.{ "child", "--count=invalid" }, .expected_error = error.InvalidOptionValueFound },
    };
    inline for (cases) |case| {
        const result = LazyChild.execute(.{ .allocator = t.allocator, .args = case.args });
        if (case.expected_error) |err| {
            try t.expectError(err, result);
        } else {
            try result;
        }
    }
}
