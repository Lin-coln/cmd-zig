const std = @import("std");
const t = std.testing;
const Context = @import("Context/Self.zig");
const Option = @import("Option/Self.zig");
const OptionValues = @import("OptionValues/Self.zig");
const executeWithOptions = @import("executeWithOptions.zig").executeWithOptions;

pub fn WithOptions(
    comptime State: type,
    comptime options: []const Option,
    comptime run: *const fn (*State, Context, *const OptionValues) anyerror!void,
) type {
    return struct {
        pub fn execute(state: *State, ctx: Context) !void {
            return executeWithOptions(ctx, options, state, runFn);
        }

        fn runFn(raw: ?*anyopaque, ctx: Context, values: *const OptionValues) anyerror!void {
            const state: *State = @ptrCast(@alignCast(raw.?));
            return run(state, ctx, values);
        }
    };
}

test "WithOptions.execute: passes parsed options and remaining arguments to the typed handler" {
    const State = struct {
        calls: usize = 0,
        count: i64 = 0,

        fn run(self: *@This(), ctx: Context, values: *const OptionValues) !void {
            self.calls += 1;
            self.count = (try values.get(i64, "count")).?;
            try t.expectEqualDeep(@as([]const []const u8, &.{ "run", "input" }), ctx.args);
        }
    };
    const Impl = WithOptions(State, &.{Option.int("-c, --count=<val>")}, State.run);
    var state: State = .{};
    try Impl.execute(&state, .{
        .allocator = t.allocator,
        .args = &.{ "run", "-c=-2", "input" },
    });
    try t.expectEqual(@as(usize, 1), state.calls);
    try t.expectEqual(@as(i64, -2), state.count);
}

test "WithOptions.execute: propagates an error from the typed handler" {
    const State = struct {
        called: bool = false,

        fn run(self: *@This(), _: Context, _: *const OptionValues) error{HandlerFailure}!void {
            self.called = true;
            return error.HandlerFailure;
        }
    };
    const Impl = WithOptions(State, &.{Option.boolean("--verbose")}, State.run);
    var state: State = .{};
    try t.expectError(error.HandlerFailure, Impl.execute(&state, .{
        .allocator = t.allocator,
        .args = &.{ "run", "--verbose" },
    }));
    try t.expect(state.called);
}

test "WithOptions.execute: preserves the terminator across consecutive option parsers" {
    const State = struct {
        expected_args: []const []const u8,
        expected_count: ?i64,
        called: bool = false,

        const Outer = WithOptions(@This(), &.{Option.boolean("--verbose")}, parseNext);
        const Inner = WithOptions(@This(), &.{Option.int("--count=<n>")}, run);

        fn parseNext(self: *@This(), ctx: Context, values: *const OptionValues) !void {
            try t.expect((try values.get(bool, "verbose")).?);
            try Inner.execute(self, ctx);
        }

        fn run(self: *@This(), ctx: Context, values: *const OptionValues) !void {
            self.called = true;
            try t.expectEqualDeep(self.expected_args, ctx.args);
            try t.expectEqual(self.expected_count, try values.get(i64, "count"));
        }
    };
    const cases = .{
        .{
            .args = @as([]const []const u8, &.{ "/bin/foo", "--verbose", "--count=2" }),
            .remaining = @as([]const []const u8, &.{"/bin/foo"}),
            .count = @as(?i64, 2),
        },
        .{
            .args = @as([]const []const u8, &.{ "/bin/foo", "--verbose", "--", "--count=2", "--" }),
            .remaining = @as([]const []const u8, &.{ "/bin/foo", "--", "--count=2", "--" }),
            .count = @as(?i64, null),
        },
    };
    inline for (cases) |case| {
        var state: State = .{ .expected_args = case.remaining, .expected_count = case.count };
        try State.Outer.execute(&state, .{ .allocator = t.allocator, .args = case.args });
        try t.expect(state.called);
    }
}
