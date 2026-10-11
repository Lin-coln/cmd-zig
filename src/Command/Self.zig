const std = @import("std");
const Args = @import("../Args/Self.zig");
const Allocator = std.mem.Allocator;

pub const Context = @import("Context.zig");
pub const Option = @import("Option.zig");
pub const Collection = @import("Collection.zig");
const Handlers = @import("Handlers.zig");
const Self = @This();
allocator: Allocator,
name: []const u8,
desc: ?[]const u8 = null,
handlers: Handlers,
options: ?[]const Option = null,
subcommands: ?*Collection = null,

pub fn create(
    allocator: Allocator,
    comptime cfg: struct {
        name: []const u8,
        desc: ?[]const u8 = null,
        options: ?[]const Option = null,
    },
    opts: struct {
        handlers: Handlers,
        subcommands: ?*Collection = null,
    },
) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .allocator = allocator,
        .name = cfg.name,
        .desc = cfg.desc,
        .options = cfg.options,
        .handlers = opts.handlers,
        .subcommands = opts.subcommands,
    };

    return self;
}

pub fn destroy(self: *Self) void {
    if (self.subcommands) |collection| {
        collection.release();
    }

    self.allocator.destroy(self);
}

pub fn execute(self: *Self, ctx: *Context) !void {
    var idx: usize = 0;

    while (idx < ctx.args.items.len) {
        const desc = Args.parseDescriptorFromArg(ctx.args.items[idx].*);

        // update context options
        if (self.options) |opts| {
            if (Option.parseEntry(opts, desc)) |entry| {
                try ctx.options.put(entry.opt.key, entry);
                _ = ctx.args.orderedRemove(idx);
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

                // only args after command name belong to subcommand
                const rest = ctx_sub.args.items[idx + 1 ..];
                std.mem.copyForwards(
                    *const []const u8,
                    ctx_sub.args.items[0..rest.len],
                    rest,
                );
                ctx_sub.args.items.len = rest.len;

                // parent keeps args before subcommand
                ctx.args.items.len = idx;

                // todo: self.beforeCallSubcommand(ctx);
                try subcommand.execute(ctx_sub);
                return;
            }
        }

        idx += 1;
    }

    self.handlers.callExecute(ctx);
}
