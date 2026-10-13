const std = @import("std");
const builtin = @import("builtin");
const mod = @import("mod");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Cmd = mod.Cmd;

extern "kernel32" fn SetConsoleOutputCP(code_page: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
    }

    const allocator: Allocator = init.arena.allocator();

    const args: []const []const u8 = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    const root = try Root.create(allocator);
    defer root.destroy();

    root.asCommand().execute(.{
        .allocator = allocator,
        .args = args,
    }) catch |err| {
        std.log.err("executeEntry failed: {}", .{err});
    };
}

const Root = struct {
    const Self = @This();
    allocator: Allocator,

    pub fn create(allocator: Allocator) !*Self {
        const ptr = try allocator.create(Self);
        errdefer allocator.destroy(ptr);
        ptr.* = .{
            .allocator = allocator,
        };
        return ptr;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn asCommand(ptr: *Self) Cmd {
        return .init(ptr, .{
            .name = "root",
            .options = &.{
                .{ .key = "help", .alias = 'h', .type = .boolean },
            },
        }, struct {
            pub fn onExecute(self: *Self, ctx: Cmd.Context, opts: *const Cmd.Option.Record) !void {
                _ = self;
                for (ctx.args) |arg| {
                    std.log.info("{s}", .{arg});
                }

                opts.print();
            }
        });
    }
};
