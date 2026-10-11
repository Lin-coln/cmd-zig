const std = @import("std");
const Args = @import("../Args/Self.zig");
const Allocator = std.mem.Allocator;

pub const Context = @import("Context.zig");
pub const Option = @import("Option.zig");
const Handler = @import("Handler/Self.zig").Handler;
const Self = @This();
name: []const u8,
desc: ?[]const u8 = null,
handler: Handler,
options: ?[]const Option = null,

pub fn init(
    comptime cfg: struct {
        name: []const u8,
        desc: ?[]const u8 = null,
        options: ?[]const Option = null,
    },
    handler: Handler,
) Self {
    return .{
        .name = cfg.name,
        .desc = cfg.desc,
        .options = cfg.options,
        .handler = handler,
    };
}

pub fn execute(self: Self, ctx: Context) !void {
    switch (self.handler) {
        .execute => |handler| {
            handler.vt.handleExecute(handler.ptr, ctx);
        },

        .subcommands => |handler| {
            var idx: usize = 0;
            while (idx < ctx.args.len) {
                const desc = Args.parseDescriptorFromArg(ctx.args[idx]);

                if (switch (desc) {
                    .unknown => |str| handler.vt.handleFindSubcommand(handler.ptr, str),
                    else => null,
                }) |subcommand| {
                    const ctx_cur: Context = .{
                        .allocator = ctx.allocator,
                        .args = ctx.args[0..idx],
                    };
                    const ctx_sub: Context = .{
                        .allocator = ctx.allocator,
                        .args = ctx.args[idx..],
                    };
                    handler.vt.handleBeforeExecuteSubcommand(handler.ptr, ctx_cur);
                    try subcommand.execute(ctx_sub);
                    return;
                }

                idx += 1;
            }

            // subcommand no found
            handler.vt.handleExecute(handler.ptr, ctx);
        },
    }
}
