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
callExecute: *const fn (Self, Context, *const OptionRecord) anyerror!void,
querySubCommand: *const fn (Self, Context, []const u8) ?Self,
querySubManifests: *const fn (Self, Context) ?[]const Manifest,

pub const init = @import("init.zig").init;
pub const execute = @import("execute.zig").execute;

// ptr: *anyopaque,
// vt: *const @import("init.zig").VTable,
// fn querySubManifests(self: Self, ctx: Context) ?[]const Manifest {
//     const f = self.vt.querySubManifests orelse return null;
//     return f(self.ptr, ctx);
// }
