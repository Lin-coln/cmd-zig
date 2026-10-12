const std = @import("std");

pub const Context = @import("Context.zig");

pub const Manifest = struct {
    name: []const u8,
    desc: ?[]const u8 = null,
};

const Self = @This();
ptr: *anyopaque,
vt: *const @import("init.zig").VTable,
manifest: Manifest,

pub const init = @import("init.zig").init;

pub fn execute(self: Self, ctx: Context) !void {
    const next = self.resolveNextEntry(ctx);
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
        const cmd = self.querySubCommand(ctx, arg) orelse continue;
        return .{ .cmd = cmd, .idx = idx };
    }
    return null;
}

fn querySubManifests(self: Self, ctx: Context) ?[]const Manifest {
    const f = self.vt.querySubManifests orelse return null;
    return f(self.ptr, ctx);
}

fn querySubCommand(self: Self, ctx: Context, name: []const u8) ?Self {
    const f = self.vt.querySubCommand orelse return null;
    return f(self.ptr, ctx, name);
}
