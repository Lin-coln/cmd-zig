pub const Context = @import("Context.zig");
pub const Handler = @import("Handler/Self.zig");

pub fn callExecute(
    ctx: Context,
    handler: Handler,
) !void {
    try handler.vt.handleExecute(handler.ptr, ctx);
}
