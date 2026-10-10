const std = @import("std");
const builtin = @import("builtin");
const mod = @import("mod");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Command = mod.Command;
const Args = mod.Args;

extern "kernel32" fn SetConsoleOutputCP(code_page: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
    }

    const arena: Allocator = init.arena.allocator();

    const ctx: *Command.Context = try .createFromProcess(init);
    defer ctx.destroy();

    const root = try RootCommand.create(arena);
    defer root.destroy();

    root.cmd.callExecute(ctx);
}

const RootCommand = struct {
    const Self = @This();
    allocator: Allocator,
    cmd: Command,

    pub fn create(allocator: Allocator) !*Self {
        const ptr = try allocator.create(Self);
        errdefer allocator.destroy(ptr);

        ptr.* = .{
            .allocator = allocator,
            .cmd = .init(.{
                .name = "cli",
                .desc =
                \\this is my awesome multiline description.
                \\This is already line 2.
                \\And this is line 3.
                ,
                .options = &.{
                    .{ .key = "help", .alias = 'h', .parser = .bool },
                },
            }, .{
                .handlers = .init(ptr, struct {
                    pub fn handleExecute(c: *Self, ctx: *Command.Context) void {
                        c.handleExecute(ctx) catch |err| {
                            std.log.err("handleExecute failed: {}", .{err});
                        };
                    }
                }),
            }),
        };

        return ptr;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn handleExecute(self: *Self, ctx: *Command.Context) !void {
        for (ctx.args.items, 0..) |arg, idx| {
            switch (Args.Descriptor.initFromSlice(arg.*)) {
                .option => |desc| {
                    const opts = self.cmd.options orelse continue;
                    const opt = desc.findOption(opts) orelse continue;
                    _ = ctx.args.orderedRemove(idx);
                    try ctx.options.put(opt.key, desc.value);
                },
                else => continue,
            }
        }

        var iter = ctx.options.iterator();
        for (ctx.args.items) |arg| {
            std.log.info("{s}", .{arg.*});
        }

        while (iter.next()) |entry| {
            std.log.info("option: {s}={s}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.* orelse "(null)",
            });
        }
    }
};
