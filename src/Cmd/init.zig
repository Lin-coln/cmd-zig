const Self = @import("Self.zig");
const Context = Self.Context;
const Manifest = Self.Manifest;
const OptionRecord = Self.OptionRecord;

pub const VTable = struct {
    onExecute: *const fn (?*anyopaque, Context, *const OptionRecord) anyerror!void,
    querySubCommand: ?*const fn (?*anyopaque, Context, []const u8) ?Self = null,
    querySubManifests: ?*const fn (?*anyopaque, Context) ?[]const Manifest = null,
};

/// Borrow an instance that must outlive every use of the returned command.
/// Handlers receive the original pointer type as their first argument.
pub fn init(typed: anytype, manifest: Manifest, comptime Impls: type) Self {
    const Ptr = @TypeOf(typed);
    switch (@typeInfo(Ptr)) {
        .pointer => |info| {
            if (info.size != .one or info.is_const) {
                @compileError("Cmd.init requires a mutable single-item pointer");
            }
        },
        else => @compileError("Cmd.init requires an instance pointer; use Cmd.initStatic for stateless commands"),
    }

    return .{
        .manifest = manifest,
        .ptr = typed,
        .vt = &Adapter(Ptr, Impls).vt,
    };
}

/// Construct a stateless command, including at comptime.
/// Handlers receive Context first, with no instance argument.
pub fn initStatic(manifest: Manifest, comptime Impls: type) Self {
    return .{
        .manifest = manifest,
        .ptr = null,
        .vt = &Adapter(null, Impls).vt,
    };
}

fn Adapter(comptime Ptr: ?type, comptime Impls: type) type {
    if (!@hasDecl(Impls, "onExecute")) {
        @compileError(@typeName(Impls) ++ " needs onExecute");
    }

    return struct {
        const vt: VTable = .{
            .onExecute = onExecute,
            .querySubCommand = if (@hasDecl(Impls, "querySubCommand")) querySubCommand else null,
            .querySubManifests = if (@hasDecl(Impls, "querySubManifests")) querySubManifests else null,
        };

        fn onExecute(raw: ?*anyopaque, ctx: Context, opts: *const OptionRecord) anyerror!void {
            if (Ptr) |P| {
                const self: P = @ptrCast(@alignCast(raw.?));
                return Impls.onExecute(self, ctx, opts);
            }
            return Impls.onExecute(ctx, opts);
        }

        fn querySubCommand(raw: ?*anyopaque, ctx: Context, name: []const u8) ?Self {
            if (Ptr) |P| {
                const self: P = @ptrCast(@alignCast(raw.?));
                return Impls.querySubCommand(self, ctx, name);
            }
            return Impls.querySubCommand(ctx, name);
        }

        fn querySubManifests(raw: ?*anyopaque, ctx: Context) ?[]const Manifest {
            if (Ptr) |P| {
                const self: P = @ptrCast(@alignCast(raw.?));
                return Impls.querySubManifests(self, ctx);
            }
            return Impls.querySubManifests(ctx);
        }
    };
}
