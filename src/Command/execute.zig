const std = @import("std");
const VT = @import("../utils/VT.zig");
const Self = @import("Self.zig");
const Context = Self.Context;

pub fn execute(self: Self, ctx: Context) !void {
    const next = resolveNextEntry(self, ctx);
    if (next) |sub| {
        try self.execute(ctx.slice(.{ .end = sub.idx }));
        try sub.cmd.execute(ctx.slice(.{ .start = sub.idx }));
    } else {
        return try self.vt.onExecute(self.ptr, ctx);
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
