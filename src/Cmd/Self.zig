const Context = @import("../Context/Self.zig");

const Self = @This();

/// Borrowed implementation state; it must outlive execution.
ptr: ?*anyopaque = null,
executeFn: *const fn (?*anyopaque, Context) anyerror!void,

pub const init = @import("init.zig").init;
pub const initWithCtx = @import("initWithCtx.zig").initWithCtx;
pub const execute = @import("execute.zig").execute;
