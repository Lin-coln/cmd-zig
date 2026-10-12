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
pub const execute = @import("execute.zig").execute;

fn querySubManifests(self: Self, ctx: Context) ?[]const Manifest {
    const f = self.vt.querySubManifests orelse return null;
    return f(self.ptr, ctx);
}
