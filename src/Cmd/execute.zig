const std = @import("std");
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
    defer opts.deinit();

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

    try self.callExecute(
        .{ .allocator = allocator, .args = args },
        opts,
    );
    // try self.vt.onExecute(
    //     self.ptr,
    //     .{ .allocator = allocator, .args = args },
    //     opts,
    // );
}

fn resolveNextEntry(self: Self, ctx: Context) ?struct { cmd: Self, idx: usize } {
    for (ctx.args, 0..) |arg, idx| {
        if (std.mem.eql(u8, arg, "--")) break;
        const cmd = self.querySubCommand(ctx, arg) orelse continue;
        return .{ .cmd = cmd, .idx = idx };
    }
    return null;
}

// fn querySubCommand(self: Self, ctx: Context, name: []const u8) ?Self {
//     const f = self.vt.querySubCommand orelse return null;
//     return f(self.ptr, ctx, name);
// }
