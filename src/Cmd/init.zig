const std = @import("std");
const VT = @import("../utils/VT.zig");
const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
const Option = Self.Option;

pub const VTable = struct {
    onExecute: *const fn (*anyopaque, Context, *const Option.Record) anyerror!void,
    querySubManifests: ?*const fn (*anyopaque, Context) []const Manifest = null,
    querySubCommand: ?*const fn (*anyopaque, Context, []const u8) ?Self = null,
};

pub fn init(
    typed: anytype,
    manifest: Manifest,
    comptime Impls: type,
) Self {
    const Typed = @typeInfo(@TypeOf(typed)).pointer.child;

    inline for (@typeInfo(VTable).@"struct".fields) |field| {
        const optional = @typeInfo(field.type) == .optional;
        if (!@hasDecl(Impls, field.name)) {
            if (optional) continue;
            @compileError(@typeName(Impls) ++ " needs " ++ field.name);
        }

        const ptr_type = if (optional)
            @typeInfo(field.type).optional.child
        else
            field.type;

        const fn_ptr = @typeInfo(ptr_type).pointer;
        const Actual = @TypeOf(@field(Impls, field.name));

        const Expected = VT.NewFn(
            fn_ptr.child,
            *Typed,
            // onExecute
            if (comptime std.mem.eql(u8, field.name, "onExecute")) blk: {
                const ActualReturn = @typeInfo(Actual).@"fn".return_type.?;
                const ExpectedReturn = switch (@typeInfo(ActualReturn)) {
                    .error_union => |info| info.error_set!void,
                    else => void,
                };
                break :blk ExpectedReturn;
            }
            // default
            else null,
        );

        if (Actual != Expected) {
            @compileError(@typeName(Impls) ++ "." ++ field.name ++ " must be " ++ @typeName(Expected));
        }
    }

    const Static = struct {
        const vt: VTable = .{
            .onExecute = onExecute,
            .querySubManifests = if (@hasDecl(Impls, "querySubManifests")) FnCast(Impls.querySubManifests) else null,
            .querySubCommand = if (@hasDecl(Impls, "querySubCommand")) FnCast(Impls.querySubCommand) else null,
        };
        fn FnCast(comptime Fn: anytype) *const VT.NewFn(@TypeOf(Fn), *anyopaque, null) {
            return @ptrCast(&Fn);
        }
        fn onExecute(ptr: *anyopaque, ctx: Context, opts: *const Option.Record) anyerror!void {
            const self: *Typed = @ptrCast(@alignCast(ptr));
            return Impls.onExecute(self, ctx, opts);
        }
    };

    return .{
        .manifest = manifest,
        .ptr = @ptrCast(typed),
        .vt = &Static.vt,
    };
}
