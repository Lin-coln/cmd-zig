const std = @import("std");
const builtin = @import("builtin");
const mod = @import("mod");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Args = mod.Args;
const Cmd = mod.Cmd2;

extern "kernel32" fn SetConsoleOutputCP(code_page: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub fn main(init: std.process.Init) !void {
    if (builtin.os.tag == .windows) {
        _ = SetConsoleOutputCP(65001);
    }

    const allocator: Allocator = init.arena.allocator();

    const root = try Root.create(allocator);
    defer root.destroy();

    const args: []const []const u8 = try init.minimal.args.toSlice(allocator);

    root.asCommand().execute(
        .{
            .allocator = allocator,
            .args = args,
        },
    ) catch |err| {
        std.log.err("executeEntry failed: {}", .{err});
    };
}

const Root = struct {
    const Self = @This();
    allocator: Allocator,
    // options: []const Cmd.Option,

    pub fn create(allocator: Allocator) !*Self {
        const ptr = try allocator.create(Self);
        errdefer allocator.destroy(ptr);
        ptr.* = .{
            .allocator = allocator,
            // .options = &.{
            //     .{ .key = "help", .alias = 'h', .parser = .bool },
            // },
        };
        return ptr;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn asCommand(ptr: *Self) Cmd {
        return .init(ptr, .{
            .name = "root",
        }, struct {
            pub fn onExecute(self: *Self, ctx: Cmd.Context) !void {
                _ = self;
                for (ctx.args) |arg| {
                    std.log.info("{s}", .{arg});
                }
            }
        });
    }
};

// const RootCommand = struct {
//     const Self = @This();
//     allocator: Allocator,
//     init: std.process.Init,
//     handler: Cmd.Handler,
//     options: []const Cmd.Option,
//
//     pub fn create(init: std.process.Init) !*Self {
//         const allocator: Allocator = init.arena.allocator();
//         const ptr = try allocator.create(Self);
//         errdefer allocator.destroy(ptr);
//
//         ptr.* = .{
//             .allocator = allocator,
//             .init = init,
//             .handler = .init(ptr, struct {
//                 pub const onExecute = Self.handleExecute;
//             }),
//             .options = &.{
//                 .{ .key = "help", .alias = 'h', .parser = .bool },
//             },
//         };
//
//         return ptr;
//     }
//
//     pub fn destroy(self: *Self) void {
//         self.allocator.destroy(self);
//     }
//
//     pub fn handleExecute(self: *Self, ctx: Cmd.Context) !void {
//         const args, const opts = blk: {
//             var args: std.ArrayList([]const u8) = .empty;
//             defer args.deinit(self.allocator);
//             var options: std.ArrayList(Cmd.Option.Entry) = .empty;
//             defer options.deinit(self.allocator);
//
//             for (ctx.args) |arg| {
//                 const desc = Args.parseDescriptorFromArg(arg);
//                 if (Cmd.Option.parseEntry(self.options, desc)) |entry| {
//                     try options.append(self.allocator, entry);
//                     continue;
//                 }
//                 try args.append(self.allocator, arg);
//             }
//
//             const owned_args = try args.toOwnedSlice(self.allocator);
//             errdefer self.allocator.free(owned_args);
//             const owned_options = try options.toOwnedSlice(self.allocator);
//             errdefer self.allocator.free(owned_options);
//             break :blk .{ owned_args, owned_options };
//         };
//
//         for (args) |arg| {
//             std.log.info("{s}", .{arg});
//         }
//
//         for (opts) |opt| {
//             std.log.info("option: {s}={s}\n", .{
//                 opt.opt.key,
//                 opt.value orelse "(null)",
//             });
//         }
//     }
// };
