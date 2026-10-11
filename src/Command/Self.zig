const std = @import("std");
const Args = @import("../Args/Self.zig");

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

pub fn execute(self: Self, ctx: *Context) !void {
    for (ctx.args.items, 0..) |arg, idx| {
        const desc = Args.parseDescriptorFromArg(arg.*);

        const opts = self.options orelse continue;
        const entry = Option.parseEntry(opts, desc) orelse continue;
        _ = ctx.args.orderedRemove(idx);
        try ctx.options.put(entry.opt.key, entry);
    }

    self.handlers.callExecute(ctx);
}
