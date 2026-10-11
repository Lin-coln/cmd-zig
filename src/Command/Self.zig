const std = @import("std");
const Args = @import("../Args/Self.zig");

pub const Context = @import("Context.zig");
pub const Option = @import("Option.zig");
pub const Collection = @import("Collection.zig");
const Handlers = @import("Handlers.zig");
const Self = @This();
name: []const u8,
desc: ?[]const u8 = null,
handlers: Handlers,
options: ?[]const Option = null,
subcommands: ?*Collection = null,

pub fn init(
    comptime cfg: struct {
        name: []const u8,
        desc: ?[]const u8 = null,
        options: ?[]const Option = null,
    },
    opts: struct {
        handlers: Handlers,
        subcommands: ?*Collection = null,
    },
) Self {
    return .{
        .name = cfg.name,
        .desc = cfg.desc,
        .options = cfg.options,
        .handlers = opts.handlers,
        .subcommands = if (opts.subcommands) |collection|
            collection.retain()
        else
            null,
    };
}

pub fn deinit(self: *Self) void {
    if (self.subcommands) |collection| {
        self.subcommands = null;
        collection.release();
    }
}

pub fn clone(self: *const Self) Self {
    var next = self.*;
    if (self.subcommands) |collection| {
        next.subcommands = collection.retain();
    }
    return next;
}

pub fn execute(self: *Self, ctx: *Context) !void {
    var idx: usize = 0;
    while (idx < ctx.args.items.len) : (idx += 1) {
        const desc = Args.parseDescriptorFromArg(ctx.args.items[idx].*);

        // update context options
        if (self.options) |opts| {
            if (Option.parseEntry(opts, desc)) |entry| {
                _ = ctx.args.orderedRemove(idx);
                try ctx.options.put(entry.opt.key, entry);
                idx -= 1; // avoid idx out of range
                continue;
            }
        }

        // subcommands
        if (self.subcommands) |sub| {
            if (switch (desc) {
                .unknown => |str| sub.findCommandByName(str),
                else => null,
            }) |subcommand| {
                const ctx_sub = try ctx.clone();
                defer ctx_sub.destroy();
                // rm cmd name
                _ = ctx_sub.args.orderedRemove(idx);
                // rest args belongs to sub command
                ctx.args.items.len = idx;

                // todo: self.beforeCallSubcommand(ctx);
                // call sub command
                try subcommand.execute(ctx_sub);

                // skip others when subcommand found.
                return;
            }
        }
    }

    self.handlers.callExecute(ctx);
}
