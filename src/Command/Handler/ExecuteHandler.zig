const VT = @import("../../utils/VT.zig");
const Context = @import("../Context.zig");

pub const VTable = struct {
    handleExecute: *const fn (ptr: *anyopaque, ctx: Context) void,
};
const Self = @This();
ptr: *anyopaque,
vt: *const VTable,
pub fn init(ctx: anytype, comptime Impls: type) Self {
    const Ctx = @typeInfo(@TypeOf(ctx)).pointer.child;
    VT.ValidateVTable(VTable, Ctx, Impls);

    const Static = struct {
        const vt: VTable = .{
            .handleExecute = VT.FnCast(Impls.handleExecute),
        };
    };

    return .{
        .ptr = @ptrCast(ctx),
        .vt = &Static.vt,
    };
}
