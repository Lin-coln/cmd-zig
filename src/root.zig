pub const Args = @import("Args/Self.zig");
pub const Cmd = @import("Cmd/Self.zig");

test {
    _ = @import("Args/OptionDescriptor.zig");
    _ = @import("Args/Self.zig");
    _ = @import("Cmd/Context.zig");
    _ = @import("Cmd/Option.zig");
    _ = @import("Cmd/OptionRecord.zig");
    _ = @import("Cmd/init.zig");
    _ = @import("Cmd/initWithCtx.zig");
    _ = @import("Cmd/execute.zig");
}
