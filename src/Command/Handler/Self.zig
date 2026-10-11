pub const Handler = union(enum) {
    execute: ExecuteHandler,
    subcommands: WithSubcommands,
};

pub const ExecuteHandler = @import("ExecuteHandler.zig");
pub const WithSubcommands = @import("WithSubcommands.zig");
