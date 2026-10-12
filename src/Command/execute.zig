const std = @import("std");
const VT = @import("../utils/VT.zig");
const Args = @import("../Args/Self.zig");
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
const Option = Self.Option;

pub fn execute(self: Self, ctx: Context) !void {
    const next = resolveNextEntry(self, ctx);
    if (next) |sub| {
        try self.execute(ctx.slice(.{ .end = sub.idx }));
        try sub.cmd.execute(ctx.slice(.{ .start = sub.idx }));
        return;
    }

    const parsed = try parseContext(ctx, self.manifest);
    defer parsed.allocator.free(parsed.args);
    defer if (parsed.opts) |opts| opts.deinit();

    try self.vt.onExecute(self.ptr, parsed);
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

fn parseContext(
    ctx: Context,
    manifest: Manifest,
) !Context {
    const allocator = ctx.allocator;

    var opts: *Option.Record = try .create(allocator);
    errdefer opts.deinit();

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
                if (manifest.queryOption(d)) |opt| {
                    try opts.set(
                        opt.key,
                        switch (opt.type) {
                            .string => .{ .string = d.value orelse "" },
                            .boolean => .{ .boolean = true },
                        },
                    );
                } else {
                    try args_ls.append(allocator, arg);
                }
            },
            .unknown => |str| {
                try args_ls.append(allocator, str);
            },
        }
    }

    const args = try args_ls.toOwnedSlice(allocator);
    errdefer allocator.free(args);

    return ctx.toParsed(args, opts);
}
