pub const Context = @import("Context.zig");
pub const Handler = @import("Handler/Self.zig");

pub const Option = @import("Option.zig");

pub fn callExecute(
    ctx: Context,
    handler: Handler,
) !void {
    try handler.vt.onExecute(handler.ptr, ctx);
}
