pub const Context = @import("Context.zig");
pub const Option = @import("Option.zig");
pub const OptionRecord = @import("OptionRecord.zig");

pub const Manifest = struct {
    name: []const u8,
    desc: ?[]const u8 = null,
    options: ?[]const Option = null,
};

const Self = @This();
manifest: Manifest,
/// Borrowed implementation state; null for stateless commands.
ptr: ?*anyopaque = null,
vt: *const VTable,

pub const VTable = @import("init.zig").VTable;
pub const init = @import("init.zig").init;
pub const initWithCtx = @import("init.zig").initWithCtx;
pub const execute = @import("execute.zig").execute;

fn querySubManifests(self: Self, ctx: Context) ?[]const Manifest {
    const f = self.vt.querySubManifests orelse return null;
    return f(self.ptr, ctx);
}
