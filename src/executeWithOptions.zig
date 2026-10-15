const std = @import("std");
const t = std.testing;
const Args = @import("Args/Self.zig");
const Context = @import("Context/Self.zig");
const Option = @import("Option/Self.zig");
const OptionValues = @import("OptionValues/Self.zig");

/// The handler borrows the filtered arguments and parsed values until it returns.
pub fn executeWithOptions(
    ctx: Context,
    options: []const Option,
    ptr: ?*anyopaque,
    runFn: *const fn (?*anyopaque, Context, *const OptionValues) anyerror!void,
) !void {
    var values = OptionValues.init(ctx.allocator);
    defer values.deinit();

    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(ctx.allocator);

    if (ctx.args.len > 0) try args.append(ctx.allocator, ctx.args[0]);
    const inputs = if (ctx.args.len > 0) ctx.args[1..] else ctx.args;
    var after_double_dash = false;
    for (inputs) |arg| {
        const descriptor: Args.Descriptor = if (after_double_dash)
            .{ .unknown = arg }
        else
            Args.parseDescriptorFromArg(arg);
        switch (descriptor) {
            .doubleDash => {
                after_double_dash = true;
                continue;
            },
            .option => |desc| {
                const option = blk: {
                    for (options) |*candidate| {
                        if (candidate.match(desc)) break :blk candidate;
                    }
                    break :blk null;
                };
                if (option) |opt| {
                    try values.set(opt.key, try opt.parse(desc));
                    continue;
                }
            },
            .unknown => {},
        }
        try args.append(ctx.allocator, arg);
    }

    try checkOptions(options, &values);
    try runFn(ptr, .{ .allocator = ctx.allocator, .args = args.items }, &values);
}

fn checkOptions(options: []const Option, values: *OptionValues) !void {
    for (options) |option| {
        if (values.map.contains(option.key)) continue;
        if (option.default) |value| {
            try values.set(option.key, value);
        } else if (option.required) {
            return error.RequiredOptionNotFound;
        }
    }
}

test "executeWithOptions: parses declared options and passes through other arguments" {
    var called = false;
    const Handler = struct {
        fn run(raw: ?*anyopaque, ctx: Context, values: *const OptionValues) !void {
            const called_ptr: *bool = @ptrCast(@alignCast(raw.?));
            called_ptr.* = true;
            try t.expectEqualDeep(
                @as([]const []const u8, &.{ "run", "file", "--unknown", "-v", "--verbose=false" }),
                ctx.args,
            );
            try t.expect(ctx.allocator.ptr == t.allocator.ptr);
            try t.expect((try values.get(bool, "verbose")).?);
        }
    };
    try executeWithOptions(.{
        .allocator = t.allocator,
        .args = &.{ "run", "file", "--unknown", "-v", "--", "-v", "--verbose=false" },
    }, &.{Option.boolean("-v, --verbose")}, &called, Handler.run);
    try t.expect(called);
}

test "executeWithOptions: rejects an invalid option value before calling the handler" {
    const Handler = struct {
        fn run(_: ?*anyopaque, _: Context, _: *const OptionValues) !void {
            return error.UnexpectedExecution;
        }
    };
    try t.expectError(error.InvalidOptionValueFound, executeWithOptions(.{
        .allocator = t.allocator,
        .args = &.{ "run", "--verbose=yes" },
    }, &.{Option.boolean("--verbose")}, null, Handler.run));
}

test "executeWithOptions: preserves argv0 and accepts empty arguments" {
    const cases = .{
        @as([]const []const u8, &.{}),
        @as([]const []const u8, &.{"--verbose"}),
    };
    const Handler = struct {
        expected: []const []const u8,
        called: bool = false,

        fn run(raw: ?*anyopaque, ctx: Context, values: *const OptionValues) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.called = true;
            try t.expectEqualDeep(self.expected, ctx.args);
            try t.expect((try values.get(bool, "verbose")) == null);
        }
    };
    inline for (cases) |args| {
        var handler: Handler = .{ .expected = args };
        try executeWithOptions(.{ .allocator = t.allocator, .args = args }, &.{
            Option.boolean("--verbose"),
        }, &handler, Handler.run);
        try t.expect(handler.called);
    }
}

test "executeWithOptions: propagates a handler error" {
    var called = false;
    const Handler = struct {
        fn run(raw: ?*anyopaque, _: Context, _: *const OptionValues) error{HandlerFailure}!void {
            const called_ptr: *bool = @ptrCast(@alignCast(raw.?));
            called_ptr.* = true;
            return error.HandlerFailure;
        }
    };
    try t.expectError(error.HandlerFailure, executeWithOptions(.{
        .allocator = t.allocator,
        .args = &.{ "run", "--verbose" },
    }, &.{Option.boolean("--verbose")}, &called, Handler.run));
    try t.expect(called);
}

test "executeWithOptions: frees temporary storage when an allocation fails" {
    const Handler = struct {
        fn run(allocator: std.mem.Allocator) !void {
            try executeWithOptions(.{
                .allocator = allocator,
                .args = &.{ "bin_path", "--verbose", "1", "2", "3", "4", "5", "6", "7", "8", "9" },
            }, &.{Option.boolean("--verbose")}, null, execute);
            try executeWithOptions(.{
                .allocator = allocator,
                .args = &.{"bin_path"},
            }, &.{Option.init("--count=<val>", .{ .type = .int, .default = .{ .int = 5 } })}, null, execute);
        }

        fn execute(_: ?*anyopaque, _: Context, _: *const OptionValues) !void {}
    };
    try t.checkAllAllocationFailures(t.allocator, Handler.run, .{});
}

test "checkOptions: rejects a missing required option" {
    const options = &.{
        Option.boolean("--verbose"),
        Option.init("--output=<val>", .{ .required = true }),
    };
    var values = OptionValues.init(t.allocator);
    defer values.deinit();

    try t.expectError(error.RequiredOptionNotFound, checkOptions(options, &values));
    try values.set("output", .{ .string = "file" });
    try checkOptions(options, &values);
    try t.expect((try values.get(bool, "verbose")) == null);
}

test "checkOptions: fills a default without replacing a stored value" {
    const options = &.{Option.init("--count=<val>", .{
        .type = .int,
        .required = true,
        .default = .{ .int = 5 },
    })};
    var values = OptionValues.init(t.allocator);
    defer values.deinit();

    try checkOptions(options, &values);
    try t.expectEqual(@as(i64, 5), (try values.get(i64, "count")).?);

    try values.set("count", .{ .int = -2 });
    try checkOptions(options, &values);
    try t.expectEqual(@as(i64, -2), (try values.get(i64, "count")).?);
}
