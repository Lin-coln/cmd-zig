const VT = @import("../../utils/VT.zig");
const std = @import("std");
const Handler = @import("Self.zig");
const Context = @import("../Context.zig");

pub const VTable = struct {
    onExecute: *const fn (ptr: *anyopaque, ctx: Context) anyerror!void,
};

pub fn init(ctx: anytype, comptime Impls: type) Handler {
    const Ctx = @typeInfo(@TypeOf(ctx)).pointer.child;

    // comptime validate
    inline for (@typeInfo(VTable).@"struct".fields) |field| {
        if (!@hasDecl(Impls, field.name)) {
            @compileError(@typeName(Impls) ++ " needs " ++ field.name);
        }

        if (std.mem.eql(u8, field.name, "onExecute")) {
            const Actual = @TypeOf(@field(Impls, field.name));
            const ActualReturn = @typeInfo(Actual).@"fn".return_type.?;
            const ExpectedReturn = switch (@typeInfo(ActualReturn)) {
                .error_union => |info| info.error_set!void,
                else => void,
            };

            const fn_ptr = @typeInfo(field.type).pointer;
            const Expected = VT.NewFn(fn_ptr.child, *Ctx, ExpectedReturn);
            if (Actual != Expected) {
                @compileError(@typeName(Impls) ++ "." ++ field.name ++ " must be " ++ @typeName(Expected));
            }
        }
    }

    const Static = struct {
        const vt: VTable = .{
            .onExecute = onExecute,
        };

        fn onExecute(ptr: *anyopaque, context: Context) anyerror!void {
            const self: *Ctx = @ptrCast(@alignCast(ptr));
            return Impls.onExecute(self, context);
        }
    };

    return .{
        .ptr = @ptrCast(ctx),
        .vt = &Static.vt,
    };
}
