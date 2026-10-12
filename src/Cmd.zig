const std = @import("std");
const VT = @import("./utils/VT.zig");
const Allocator = std.mem.Allocator;

pub const Context = struct {
    const Self = @This();
    allocator: Allocator,
    args: []const []const u8,
    pub fn slice(self: Self, idx: union(enum) { start: usize, end: usize }) Self {
        return .{
            .allocator = self.allocator,
            .args = switch (idx) {
                .start => |i| self.args[i..],
                .end => |i| self.args[0..i],
            },
        };
    }
};

pub const Manifest = struct {
    name: []const u8,
    desc: ?[]const u8 = null,
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
        onExecute: *const fn (ptr: *anyopaque, ctx: Context) anyerror!void,
        queryManifests: ?*const fn (*anyopaque, Context) []const Manifest = null,
        queryEntry: ?*const fn (*anyopaque, Context, []const u8) ?Entry = null,
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
                .queryManifests = if (@hasDecl(Impls, "queryManifests")) FnCast(Impls.queryManifests) else null,
                .queryEntry = if (@hasDecl(Impls, "queryEntry")) FnCast(Impls.queryEntry) else null,
            };
            fn FnCast(comptime Fn: anytype) *const VT.NewFn(@TypeOf(Fn), *anyopaque, null) {
                return @ptrCast(&Fn);
            }
            fn onExecute(ptr: *anyopaque, ctx: Context) anyerror!void {
                const self: *Typed = @ptrCast(@alignCast(ptr));
                return Impls.onExecute(self, ctx);
            }
        };

        return .{
            .manifest = manifest,
            .ptr = @ptrCast(typed),
            .vt = &Static.vt,
        };
    }

    pub fn invokeExecute(self: Self, ctx: Context) anyerror!void {
        return try self.vt.onExecute(self.ptr, ctx);
    }

    pub fn resolveNextEntry(self: Entry, ctx: Context) ?struct { entry: Entry, idx: usize } {
        for (ctx.args, 0..) |arg, idx| {
            if (std.mem.eql(u8, arg, "--")) break;
            const entry = self.queryEntry(ctx, arg) orelse continue;
            return .{ .entry = entry, .idx = idx };
        }
        return null;
    }

    pub fn loadHandler(self: Self) Handler {
        return self.vt.onLoadHandler(self.ptr);
    }

    fn queryManifests(self: Self, ctx: Context) ?[]const Manifest {
        const f = self.vt.queryManifests orelse return null;
        return f(self.ptr, ctx);
    }

    fn queryEntry(self: Self, ctx: Context, name: []const u8) ?Entry {
        const f = self.vt.queryEntry orelse return null;
        return f(self.ptr, ctx, name);
    }
};

pub fn executeEntry(entry: Entry, ctx: Context) !void {
    const next = entry.resolveNextEntry(ctx);
    if (next) |sub| {
        try executeEntry(entry, ctx.slice(.{ .end = sub.idx }));
        try executeEntry(sub.entry, ctx.slice(.{ .start = sub.idx }));
    } else {
        return try entry.invokeExecute(ctx);
    }
}
