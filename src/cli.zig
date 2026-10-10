const std = @import("std");
const mod = @import("mod");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Command = mod.Command;

const Dummy = struct {};

pub fn main(init: std.process.Init) !void {
    const arena: Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    const context: Command.Context = .{
        .args = args[1..],
    };

    const dummy = try arena.create(Dummy);
    errdefer arena.destroy(dummy);

    const cmd: Command = .init(.{ .name = "main" }, .{
        .handlers = .init(dummy, struct {
            pub fn handleExecute(_: *Dummy, ctx: Command.Context) void {
                for (ctx.args) |arg| {
                    std.log.info("arg: {s}", .{arg});
                }
            }
        }),
    });

    cmd.handlers.callExecute(context);
}
