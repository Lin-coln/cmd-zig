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
        const Expected = NewFn(fn_pointer.child, *Ctx, null);
        if (@TypeOf(@field(Handlers, field.name)) != Expected) {
            @compileError(@typeName(Handlers) ++ "." ++ field.name ++ " must be " ++ @typeName(Expected));
        }
    }
}

pub fn FnCast(comptime Fn: anytype) *const NewFn(@TypeOf(Fn), *anyopaque, null) {
    return @ptrCast(&Fn);
}

pub fn NewFn(comptime Fn: type, comptime Ctx: ?type, comptime Return: ?type) type {
    const info = @typeInfo(Fn).@"fn";
    var param_types: [info.params.len]type = undefined;
    var param_attrs: [info.params.len]Type.Fn.Param.Attributes = undefined;

    for (info.params, 0..) |param, index| {
        param_types[index] = param.type orelse
            @compileError("vtable callbacks cannot use anytype parameters");
        param_attrs[index] = .{ .@"noalias" = param.is_noalias };
    }

    if (Ctx) |Context| {
        param_types[0] = Context;
    }

    return @Fn(
        &param_types,
        &param_attrs,
        Return orelse info.return_type.?,
        .{
            .@"callconv" = info.calling_convention,
            .varargs = info.is_var_args,
        },
    );
}
