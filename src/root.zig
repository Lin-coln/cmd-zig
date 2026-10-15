pub const Args = @import("Args/Self.zig");
pub const Option = @import("Option/Self.zig");
pub const OptionValues = @import("OptionValues/Self.zig");
pub const CmdSpec = @import("CmdSpec/Self.zig");
pub const Context = @import("Context/Self.zig");
pub const Cmd = @import("Cmd/Self.zig");
pub const executeWithOptions = @import("executeWithOptions.zig").executeWithOptions;
pub const executeNested = @import("executeNested.zig").executeNested;
pub const WithOptions = @import("WithOptions.zig").WithOptions;
pub const WithSubcommands = @import("WithSubcommands.zig").WithSubcommands;

test {
    _ = @import("Args/OptionDescriptor.zig");
    _ = @import("Args/Self.zig");
    _ = @import("Context/Self.zig");
    _ = @import("Option/Self.zig");
    _ = @import("Option/Value.zig");
    _ = @import("Option/init.zig");
    _ = @import("Option/parseFromStr.zig");
    _ = @import("OptionValues/Self.zig");
    _ = @import("Cmd/init.zig");
    _ = @import("Cmd/initWithCtx.zig");
    _ = @import("Cmd/execute.zig");
    _ = @import("executeWithOptions.zig");
    _ = @import("executeNested.zig");
    _ = @import("WithOptions.zig");
    _ = @import("WithSubcommands.zig");
}
