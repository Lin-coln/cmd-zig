const std = @import("std");
const VT = @import("./utils/VT.zig");
const Allocator = std.mem.Allocator;

pub const Context = struct {
    allocator: Allocator,
    args: []const []const u8,
};

pub const Manifest = struct {
    name: []const u8,
    desc: ?[]const u8,
};

pub const Handler = struct {
    const Self = @This();
    ptr: *anyopaque,
    vt: *const VTable,
    const VTable = struct {
        onExecute: *const fn (ptr: *anyopaque, ctx: Context) anyerror!void,
    };
    pub fn invokeExecute(self: Self, ctx: Context) !void {
        return try self.vt.onExecute(self.ptr, ctx);
    }
};

pub const Entry = struct {
    const Self = @This();
    ptr: *anyopaque,
    vt: *const VTable,
    manifest: Manifest,
    const VTable = struct {
        onLoadHandler: *const fn (ptr: *anyopaque) Handler,
    };
    pub fn loadHandler(self: Self) Handler {
        return try self.vt.onLoadHandler(self.ptr);
    }

    // queryManifests: ?*const fn (ctx: Context) []const Manifest = null,
    // queryEntry: ?*const fn (ctx: Context, name: []const u8) ?Entry = null,
    pub fn init(
        typed: anytype,
        opts: struct {
            manifest: Manifest,
        },
        comptime Impls: type,
    ) Self {
        const Typed = @typeInfo(@TypeOf(typed)).pointer.child;

        // comptime validate
        inline for (@typeInfo(VTable).@"struct".fields) |field| {
            if (!@hasDecl(Impls, field.name)) {
                @compileError(@typeName(Impls) ++ " needs " ++ field.name);
            }

            const fn_ptr = @typeInfo(field.type).pointer;
            const Actual = @TypeOf(@field(Impls, field.name));
            const Expected = VT.NewFn(fn_ptr.child, *Typed, null);
            if (Actual != Expected) {
                @compileError(@typeName(Impls) ++ "." ++ field.name ++ " must be " ++ @typeName(Expected));
            }
        }

        const Static = struct {
            const vt: VTable = .{
                .onLoadHandler = FnCast(Impls.onLoadHandler),
            };
            fn FnCast(comptime Fn: anytype) *const VT.NewFn(@TypeOf(Fn), *anyopaque, null) {
                return @ptrCast(&Fn);
            }
        };

        return .{
            .manifest = opts.manifest,
            .ptr = @ptrCast(typed),
            .vt = &Static.vt,
        };
    }
};

pub fn executeEntry(entry: Entry, ctx: Context) !void {
    const handler = entry.loadHandler();
    return try handler.invokeExecute(ctx);
}

const Root = struct {
    const Self = @This();

    pub fn asEntry(self: Self) Entry {
        return .init(self, .{
            .manifest = .{ .name = "root" },
        }, struct {
            pub const onLoadHandler = Self.onLoadHandler;
        });
    }

    fn onLoadHandler(self: Self) Handler {
        // todo
    }
};
