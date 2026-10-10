const VT = @import("../utils/VT.zig");
const Context = @import("Context.zig");

const Self = @This();
ptr: *anyopaque,
vt: *const struct {
    handleExecute: *const fn (ptr: *anyopaque, ctx: *Context) void,
},

pub fn init(ctx: anytype, comptime Impls: type) Self {
    const VTable = @typeInfo(@FieldType(Self, "vt")).pointer.child;
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

pub fn callExecute(self: Self, ctx: *Context) void {
    return self.vt.handleExecute(self.ptr, ctx);
}
