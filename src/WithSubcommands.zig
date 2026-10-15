const std = @import("std");
const t = std.testing;
const Context = @import("Context/Self.zig");
const Cmd = @import("Cmd/Self.zig");
const executeNested = @import("executeNested.zig").executeNested;

/// Binds a typed parent executor and subcommand queries to the same state.
/// Queries provides querySubCommand(state, ctx, name) returning !?Cmd.
pub fn WithSubcommands(
    comptime State: type,
    comptime current: *const fn (*State, Context) anyerror!void,
    comptime Queries: type,
) type {
    return struct {
        const Current = struct {
            pub const execute = current;
        };
        const BoundQueries = struct {
            state: *State,

            pub fn querySubCommand(self: @This(), ctx: Context, name: []const u8) anyerror!?Cmd {
                return Queries.querySubCommand(self.state, ctx, name);
            }
        };

        pub fn execute(state: *State, ctx: Context) anyerror!void {
            try executeNested(ctx, Cmd.initWithCtx(state, Current), BoundQueries{ .state = state });
        }
    };
}

test "WithSubcommands.execute: binds parent execution and queries to each instance" {
    const State = struct {
        const Self = @This();
        executions: usize = 0,
        queries: usize = 0,
        child_executions: usize = 0,

        pub fn execute(self: *@This(), ctx: Context) !void {
            self.executions += 1;
            try t.expectEqual(@as(usize, 1), ctx.args.len);
            try t.expectEqualStrings("tool", ctx.args[0]);
        }
        pub fn querySubCommand(self: *@This(), _: Context, name: []const u8) !?Cmd {
            self.queries += 1;
            if (!std.mem.eql(u8, name, "child")) return null;
            return Cmd.initWithCtx(self, struct {
                pub fn execute(state: *Self, ctx: Context) !void {
                    state.child_executions += 1;
                    try t.expectEqual(@as(usize, 2), ctx.args.len);
                    try t.expectEqualStrings("child", ctx.args[0]);
                    try t.expectEqualStrings("payload", ctx.args[1]);
                }
            });
        }
    };
    const Nested = WithSubcommands(State, State.execute, State);
    var first: State = .{};
    var second: State = .{};
    const ctx: Context = .{ .allocator = t.allocator, .args = &.{ "tool", "child", "payload" } };
    try Cmd.initWithCtx(&first, Nested).execute(ctx);
    try Nested.execute(&first, ctx);
    try Nested.execute(&second, ctx);
    try t.expectEqual(@as(usize, 2), first.executions);
    try t.expectEqual(@as(usize, 2), first.queries);
    try t.expectEqual(@as(usize, 2), first.child_executions);
    try t.expectEqual(@as(usize, 1), second.executions);
    try t.expectEqual(@as(usize, 1), second.queries);
    try t.expectEqual(@as(usize, 1), second.child_executions);
}

test "WithSubcommands.execute: forwards an error from the typed query" {
    const State = struct {
        pub fn execute(_: *@This(), _: Context) !void {}
        pub fn querySubCommand(_: *@This(), _: Context, _: []const u8) error{Unavailable}!?Cmd {
            return error.Unavailable;
        }
    };
    var state: State = .{};
    const Nested = WithSubcommands(State, State.execute, State);
    try t.expectError(error.Unavailable, Nested.execute(&state, .{
        .allocator = t.allocator,
        .args = &.{ "tool", "child" },
    }));
}

test "WithSubcommands.execute: composes independent parent and child options with lazy resource cleanup" {
    const Option = @import("Option/Self.zig");
    const OptionValues = @import("OptionValues/Self.zig");
    const WithOptions = @import("WithOptions.zig").WithOptions;
    const State = struct {
        const Self = @This();
        const Parent = WithOptions(Self, &.{Option.init("--count=<n>", .{ .type = .int, .required = true })}, parentRun);
        const Child = WithOptions(Self, &.{Option.float("--count=<n>")}, childRun);

        parent_calls: usize = 0,
        child_calls: usize = 0,
        acquired: usize = 0,
        released: usize = 0,
        fail_child: bool,

        fn parentRun(self: *Self, ctx: Context, values: *const OptionValues) !void {
            self.parent_calls += 1;
            try t.expectEqualDeep(@as([]const []const u8, &.{"/usr/bin/tool"}), ctx.args);
            try t.expectEqual(@as(i64, 3), (try values.get(i64, "count")).?);
        }
        fn childRun(self: *Self, ctx: Context, values: *const OptionValues) !void {
            const resource = try ctx.allocator.create(u8);
            self.acquired += 1;
            defer {
                ctx.allocator.destroy(resource);
                self.released += 1;
            }
            self.child_calls += 1;
            try t.expectEqualDeep(@as([]const []const u8, &.{ "child", "payload" }), ctx.args);
            try t.expectEqual(@as(f64, 2.5), (try values.get(f64, "count")).?);
            if (self.fail_child) return error.ChildFailed;
        }
        pub fn querySubCommand(self: *Self, _: Context, name: []const u8) !?Cmd {
            return if (std.mem.eql(u8, name, "child")) Cmd.initWithCtx(self, Child) else null;
        }
    };
    const Nested = WithSubcommands(State, State.Parent.execute, State);
    inline for (.{ false, true }) |fail_child| {
        var state: State = .{ .fail_child = fail_child };
        const result = Nested.execute(&state, .{
            .allocator = t.allocator,
            .args = &.{ "/usr/bin/tool", "--count=3", "child", "--count=2.5", "payload" },
        });
        if (fail_child) {
            try t.expectError(error.ChildFailed, result);
        } else {
            try result;
        }
        try t.expectEqual(@as(usize, 1), state.parent_calls);
        try t.expectEqual(@as(usize, 1), state.child_calls);
        try t.expectEqual(@as(usize, 1), state.acquired);
        try t.expectEqual(@as(usize, 1), state.released);
    }

    var missing_parent_option: State = .{ .fail_child = false };
    try t.expectError(error.RequiredOptionNotFound, Nested.execute(&missing_parent_option, .{
        .allocator = t.allocator,
        .args = &.{ "/usr/bin/tool", "child", "--count=2.5", "payload" },
    }));
    try t.expectEqual(@as(usize, 0), missing_parent_option.parent_calls);
    try t.expectEqual(@as(usize, 0), missing_parent_option.child_calls);
    try t.expectEqual(@as(usize, 0), missing_parent_option.acquired);
    try t.expectEqual(@as(usize, 0), missing_parent_option.released);
}
