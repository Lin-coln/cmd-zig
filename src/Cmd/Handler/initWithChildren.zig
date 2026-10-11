const Handler = @import("Self.zig");
const Context = @import("../Context.zig");
const Args = @import("../../Args/Self.zig");

const Input = struct {
    findItem: *const fn (ptr: *anyopaque, name: []const u8) ?Handler,
    callItem: *const fn (ptr: *anyopaque, ctx: Context, item: Handler, ctx_item: Context) anyerror!void,
    onExecute: *const fn (ptr: *anyopaque, ctx: Context) anyerror!void,
};

pub fn initWithChildren(context: anytype, comptime Impls: type) Handler {
    const Ctx = @typeInfo(@TypeOf(context)).pointer.child;

    return .init(context, struct {
        pub fn onExecute(self: *Ctx, ctx: Context) !void {
            for (ctx.args, 0..) |arg, idx| {
                const desc = Args.parseDescriptorFromArg(arg);

                const item = switch (desc) {
                    .unknown => |str| Impls.findItem(self, str),
                    else => null,
                } orelse continue;

                return try Impls.callItem(
                    self,
                    .{
                        .allocator = ctx.allocator,
                        .args = ctx.args[0..idx],
                    },
                    item,
                    .{
                        .allocator = ctx.allocator,
                        .args = ctx.args[idx..],
                    },
                );
            }

            // subcommand no found
            return try Impls.onExecute(self, ctx);
        }
    });
}
