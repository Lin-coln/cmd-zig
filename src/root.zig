pub const Args = @import("Args/Self.zig");
pub const Option = @import("Option/Self.zig");
pub const OptionRecord = @import("Option/Record.zig");
pub const Cmd = @import("Cmd/Self.zig");

test {
    _ = @import("Args/OptionDescriptor.zig");
    _ = @import("Args/Self.zig");
    _ = @import("Cmd/Context.zig");
    _ = @import("Option/Self.zig");
    _ = @import("Option/Value.zig");
    _ = @import("Option/init.zig");
    _ = @import("Option/Record.zig");
    _ = @import("Cmd/init.zig");
    _ = @import("Cmd/initWithCtx.zig");
    _ = @import("Cmd/execute.zig");
}
