const std = @import("std");
const t = std.testing;
const Context = @import("Context/Self.zig");
const Cmd = @import("Cmd/Self.zig");

/// Resolves children from argv[1..], preserving each command's argv[0].
/// queries provides querySubCommand(ctx, name) returning !?Cmd.
/// Returned commands must remain valid through parent and child execution.
pub fn executeNested(ctx: Context, current: Cmd, queries: anytype) anyerror!void {
    if (try resolveNextEntry(ctx, queries)) |next| {
        const prefix, const suffix = ctx.split(next.idx);
        try executeNested(prefix, current, queries);
        try next.cmd.execute(suffix);
        return;
    }
    try current.execute(ctx);
}

fn resolveNextEntry(ctx: Context, queries: anytype) !?struct { cmd: Cmd, idx: usize } {
    if (ctx.args.len <= 1) return null;
    for (ctx.args[1..], 1..) |arg, idx| {
        if (std.mem.eql(u8, arg, "--")) break;
        const cmd = try queries.querySubCommand(ctx, arg) orelse continue;
        return .{ .cmd = cmd, .idx = idx };
    }
    return null;
}

test "resolveNextEntry: finds the first child after argv0 and before the terminator" {
    const child = Cmd.init(struct {
        pub fn execute(_: Context) !void {}
    });
    const Queries = struct {
        child: Cmd,
        calls: usize = 0,

        pub fn querySubCommand(self: *@This(), _: Context, name: []const u8) !?Cmd {
            self.calls += 1;
            return if (std.mem.eql(u8, name, "child")) self.child else null;
        }
    };
    const cases = [_]struct {
        args: []const []const u8,
        idx: ?usize,
        calls: usize,
    }{
        .{ .args = &.{}, .idx = null, .calls = 0 },
        .{ .args = &.{"child"}, .idx = null, .calls = 0 },
        .{ .args = &.{ "child", "missing" }, .idx = null, .calls = 1 },
        .{ .args = &.{ "tool", "missing", "child", "child" }, .idx = 2, .calls = 2 },
        .{ .args = &.{ "tool", "child", "--" }, .idx = 1, .calls = 1 },
        .{ .args = &.{ "tool", "missing", "--", "child" }, .idx = null, .calls = 1 },
        .{ .args = &.{ "tool", "--", "child" }, .idx = null, .calls = 0 },
    };
    inline for (cases) |case| {
        var queries: Queries = .{ .child = child };
        const result = try resolveNextEntry(.{ .allocator = t.allocator, .args = case.args }, &queries);
        try t.expectEqual(case.calls, queries.calls);
        if (case.idx) |idx| {
            try t.expectEqual(idx, result.?.idx);
            try t.expectEqual(child.ptr, result.?.cmd.ptr);
            try t.expectEqual(child.executeFn, result.?.cmd.executeFn);
        } else {
            try t.expect(result == null);
        }
    }
}

test "resolveNextEntry: propagates a query error" {
    const Queries = struct {
        pub fn querySubCommand(_: Context, _: []const u8) error{LookupFailed}!?Cmd {
            return error.LookupFailed;
        }
    };
    try t.expectError(error.LookupFailed, resolveNextEntry(.{
        .allocator = t.allocator,
        .args = &.{ "tool", "child" },
    }, Queries));
}

test "executeNested: passes unmatched arguments and the terminator to the current command" {
    const State = struct {
        expected: []const []const u8,
        calls: usize = 0,

        pub fn execute(self: *@This(), ctx: Context) !void {
            self.calls += 1;
            try t.expectEqual(t.allocator, ctx.allocator);
            try expectArgs(self.expected, ctx.args);
        }
    };
    const Queries = struct {
        pub fn querySubCommand(_: Context, _: []const u8) !?Cmd {
            return null;
        }
    };
    var state: State = .{ .expected = &.{ "/usr/bin/tool", "input", "--", "child" } };
    try executeNested(.{
        .allocator = t.allocator,
        .args = state.expected,
    }, Cmd.initWithCtx(&state, State), Queries);
    try t.expectEqual(@as(usize, 1), state.calls);
}

test "executeNested: runs the parent prefix before the child suffix" {
    const Handler = struct {
        stage: *usize,
        expected_stage: usize,
        expected_args: []const []const u8,

        pub fn execute(self: *@This(), ctx: Context) !void {
            try t.expectEqual(self.expected_stage, self.stage.*);
            try expectArgs(self.expected_args, ctx.args);
            self.stage.* += 1;
        }
    };
    const Queries = struct {
        child: Cmd,

        pub fn querySubCommand(self: @This(), _: Context, name: []const u8) !?Cmd {
            return if (std.mem.eql(u8, name, "child")) self.child else null;
        }
        pub fn querySubSpecs(_: @This(), _: Context) !?[]const @import("CmdSpec/Self.zig") {
            return error.MetadataMustNotBeQueriedDuringExecution;
        }
    };
    var stage: usize = 0;
    var parent: Handler = .{ .stage = &stage, .expected_stage = 0, .expected_args = &.{ "/usr/bin/tool", "input" } };
    var child: Handler = .{ .stage = &stage, .expected_stage = 1, .expected_args = &.{ "child", "payload" } };
    try executeNested(.{
        .allocator = t.allocator,
        .args = &.{ "/usr/bin/tool", "input", "child", "payload" },
    }, Cmd.initWithCtx(&parent, Handler), Queries{ .child = Cmd.initWithCtx(&child, Handler) });
    try t.expectEqual(@as(usize, 2), stage);
}

test "executeNested: resolves the parent prefix again with its shorter context" {
    const Handler = struct {
        order: *[3]u8,
        count: *usize,
        id: u8,
        argv0: []const u8,

        pub fn execute(self: *@This(), ctx: Context) !void {
            try expectArgs(&.{self.argv0}, ctx.args);
            self.order[self.count.*] = self.id;
            self.count.* += 1;
        }
    };
    const Queries = struct {
        early: Cmd,
        late: Cmd,
        calls: usize = 0,

        pub fn querySubCommand(self: *@This(), ctx: Context, name: []const u8) !?Cmd {
            self.calls += 1;
            if (ctx.args.len == 3 and std.mem.eql(u8, name, "late")) return self.late;
            if (ctx.args.len == 2 and std.mem.eql(u8, name, "early")) return self.early;
            return null;
        }
    };
    var order: [3]u8 = undefined;
    var count: usize = 0;
    var parent: Handler = .{ .order = &order, .count = &count, .id = 0, .argv0 = "tool" };
    var early: Handler = .{ .order = &order, .count = &count, .id = 1, .argv0 = "early" };
    var late: Handler = .{ .order = &order, .count = &count, .id = 2, .argv0 = "late" };
    var queries: Queries = .{ .early = Cmd.initWithCtx(&early, Handler), .late = Cmd.initWithCtx(&late, Handler) };
    try executeNested(.{
        .allocator = t.allocator,
        .args = &.{ "tool", "early", "late" },
    }, Cmd.initWithCtx(&parent, Handler), &queries);
    try t.expectEqual(@as(usize, 3), count);
    try t.expectEqualSlices(u8, &.{ 0, 1, 2 }, &order);
    try t.expectEqual(@as(usize, 3), queries.calls);
}

test "executeNested: dispatches repeated command names at different depths" {
    const Level = struct {
        const Self = @This();
        stage: *usize,
        expected_stage: usize,
        next: ?*@This() = null,

        const Current = struct {
            pub fn execute(self: *Self, ctx: Context) !void {
                try t.expectEqual(self.expected_stage, self.stage.*);
                try expectArgs(&.{if (self.expected_stage == 0) "tool" else "same"}, ctx.args);
                self.stage.* += 1;
            }
        };

        pub fn execute(self: *@This(), ctx: Context) !void {
            try executeNested(ctx, Cmd.initWithCtx(self, Current), self);
        }
        pub fn querySubCommand(self: *@This(), _: Context, name: []const u8) !?Cmd {
            if (!std.mem.eql(u8, name, "same")) return null;
            return if (self.next) |next| Cmd.initWithCtx(next, @This()) else null;
        }
    };
    var stage: usize = 0;
    var leaf: Level = .{ .stage = &stage, .expected_stage = 2 };
    var child: Level = .{ .stage = &stage, .expected_stage = 1, .next = &leaf };
    var root: Level = .{ .stage = &stage, .expected_stage = 0, .next = &child };
    try root.execute(.{ .allocator = t.allocator, .args = &.{ "tool", "same", "same" } });
    try t.expectEqual(@as(usize, 3), stage);
}

test "executeNested: leaves the child unexecuted when its parent fails" {
    const Parent = struct {
        pub fn execute(_: Context) error{ParentFailed}!void {
            return error.ParentFailed;
        }
    };
    const Child = struct {
        calls: usize = 0,

        pub fn execute(self: *@This(), _: Context) !void {
            self.calls += 1;
        }
        pub fn querySubCommand(self: *@This(), _: Context, _: []const u8) !?Cmd {
            return Cmd.initWithCtx(self, @This());
        }
    };
    var child: Child = .{};
    try t.expectError(error.ParentFailed, executeNested(.{
        .allocator = t.allocator,
        .args = &.{ "tool", "child" },
    }, Cmd.init(Parent), &child));
    try t.expectEqual(@as(usize, 0), child.calls);
}

test "executeNested: returns a query error before executing either command" {
    const State = struct {
        calls: usize = 0,

        pub fn execute(self: *@This(), _: Context) !void {
            self.calls += 1;
        }
        pub fn querySubCommand(_: *@This(), _: Context, _: []const u8) error{LookupFailed}!?Cmd {
            return error.LookupFailed;
        }
    };
    var state: State = .{};
    try t.expectError(error.LookupFailed, executeNested(.{
        .allocator = t.allocator,
        .args = &.{ "tool", "child" },
    }, Cmd.initWithCtx(&state, State), &state));
    try t.expectEqual(@as(usize, 0), state.calls);
}

fn expectArgs(expected: []const []const u8, actual: []const []const u8) !void {
    try t.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try t.expectEqualStrings(want, got);
}
