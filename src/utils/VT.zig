const std = @import("std");

const Type = std.builtin.Type;

pub fn ValidateVTable(
    comptime VT: type,
    comptime Ctx: type,
    comptime Handlers: type,
) void {
    inline for (@typeInfo(VT).@"struct".fields) |field| {
        if (!@hasDecl(Handlers, field.name)) {
            @compileError(@typeName(Handlers) ++ " needs " ++ field.name);
        }

        const fn_pointer = @typeInfo(field.type).pointer;
        const Expected = Bind(fn_pointer.child, *Ctx);
        if (@TypeOf(@field(Handlers, field.name)) != Expected) {
            @compileError(@typeName(Handlers) ++ "." ++ field.name ++ " must be " ++ @typeName(Expected));
        }
    }
}

pub fn FnCast(comptime Fn: anytype) *const Bind(@TypeOf(Fn), *anyopaque) {
    return @ptrCast(&Fn);
}

fn Bind(comptime Fn: type, comptime Ctx: type) type {
    const info = @typeInfo(Fn).@"fn";
    var param_types: [info.params.len]type = undefined;
    var param_attrs: [info.params.len]Type.Fn.Param.Attributes = undefined;
    for (info.params, 0..) |param, index| {
        param_types[index] = param.type orelse
            @compileError("vtable callbacks cannot use anytype parameters");
        param_attrs[index] = .{ .@"noalias" = param.is_noalias };
    }
    param_types[0] = Ctx;
    return @Fn(
        &param_types,
        &param_attrs,
        info.return_type.?,
        .{
            .@"callconv" = info.calling_convention,
            .varargs = info.is_var_args,
        },
    );
}
