const std = @import("std");

pub const Context = @import("Context.zig");
pub const Option = @import("Option.zig");
const Handlers = @import("Handlers.zig");
const Self = @This();
name: []const u8,
desc: ?[]const u8 = null,
options: ?[]const Option = null,
handlers: Handlers,

pub fn init(
    comptime cfg: struct {
        name: []const u8,
        desc: ?[]const u8 = null,
        options: ?[]const Option = null,
    },
    opts: struct {
        handlers: Handlers,
    },
) Self {
    return .{
        .name = cfg.name,
        .desc = cfg.desc,
        .options = cfg.options,
        .handlers = opts.handlers,
    };
}

pub fn callExecute(self: Self, ctx: *Context) void {
    return self.handlers.callExecute(ctx);
}
