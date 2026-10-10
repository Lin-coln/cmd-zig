pub const Context = @import("Context.zig");
const Handlers = @import("Handlers.zig");
const Self = @This();
name: []const u8,
desc: ?[]const u8,
handlers: Handlers,

pub fn init(
    comptime cfg: struct {
        name: []const u8,
        desc: ?[]const u8 = null,
    },
    opts: struct {
        handlers: Handlers,
    },
) Self {
    return .{
        .name = cfg.name,
        .desc = cfg.desc,
        .handlers = opts.handlers,
    };
}
