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
/// Impls declares pub const manifest and pub fn onExecute.
pub fn initWithCtx(typed: anytype, comptime Impls: type) Self {
    const Ptr = @TypeOf(typed);
    switch (@typeInfo(Ptr)) {
        .pointer => |info| {
            if (info.size != .one or info.is_const) {
                @compileError("Cmd.initWithCtx requires a mutable single-item pointer");
            }
        },
        else => @compileError("Cmd.initWithCtx requires an instance pointer; use Cmd.init for stateless commands"),
    }

    const Impl = Adapter(Ptr, Impls);
    return .{
        .manifest = Impl.manifest,
        .ptr = typed,
        .vt = &Impl.vt,
    };
}

/// Construct a stateless command, including at comptime.
/// Handlers receive Context first, with no instance argument.
/// Impls declares pub const manifest and pub fn onExecute.
pub fn init(comptime Impls: type) Self {
    const Impl = Adapter(null, Impls);
    return .{
        .manifest = Impl.manifest,
        .ptr = null,
        .vt = &Impl.vt,
    };
}

fn Adapter(comptime Ptr: ?type, comptime Impls: type) type {
    if (!@hasDecl(Impls, "manifest")) {
        @compileError(@typeName(Impls) ++ " needs pub const manifest");
    }
    if (@TypeOf(Impls.manifest) != Manifest) {
        @compileError(@typeName(Impls) ++ ".manifest must be Cmd.Manifest, found " ++ @typeName(@TypeOf(Impls.manifest)));
    }
    if (!@hasDecl(Impls, "onExecute")) {
        @compileError(@typeName(Impls) ++ " needs onExecute");
    }

    return struct {
        const manifest: Manifest = Impls.manifest;
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
