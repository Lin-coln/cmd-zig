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

    const root = try RootCommand.create(init);
    defer root.destroy();

    const allocator: Allocator = init.arena.allocator();
    const args: []const []const u8 = try init.minimal.args.toSlice(allocator);

    try root.cmd.execute(.{
        .allocator = allocator,
        .args = args,
    });
}

const RootCommand = struct {
    const Self = @This();
    allocator: Allocator,
    init: std.process.Init,
    cmd: Command,

    pub fn create(init: std.process.Init) !*Self {
        const allocator: Allocator = init.arena.allocator();
        const ptr = try allocator.create(Self);
        errdefer allocator.destroy(ptr);

        const cmd = Command.init(
            .{
                .name = "cli",
                .desc =
                \\this is my awesome multiline description.
                \\This is already line 2.
                \\And this is line 3.
                ,
                .options = &.{
                    .{ .key = "help", .alias = 'h', .parser = .bool },
                },
            },
            .{
                .execute = .init(ptr, struct {
                    pub fn handleExecute(c: *Self, ctx: Command.Context) void {
                        c.handleExecute(ctx) catch |err| {
                            std.log.err("handleExecute failed: {}", .{err});
                        };
                    }
                }),
            },
        );

        ptr.* = .{
            .allocator = allocator,
            .init = init,
            .cmd = cmd,
        };

        return ptr;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn handleExecute(_: *Self, ctx: Command.Context) !void {
        for (ctx.args) |arg| {
            std.log.info("{s}", .{arg});
        }

        // var iter = ctx.options.iterator();
        // while (iter.next()) |entry| {
        //     std.log.info("option: {s}={s}\n", .{
        //         entry.key_ptr.*,
        //         entry.value_ptr.*.value orelse "(null)",
        //     });
        // }
    }
};
