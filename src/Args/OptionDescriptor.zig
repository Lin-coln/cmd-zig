const std = @import("std");

pub const Identity = union(enum) {
    key: []const u8,
    alias: u8,
};
const Self = @This();
identity: Identity,
value: ?[]const u8 = null,

pub fn parseFromArg(arg: []const u8) ?Self {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    var opt_id: Identity = if (arg[1] == '-') .{
        .key = arg,
    } else .{
        .alias = arg[1],
    };

    var current = switch (opt_id) {
        .key => arg[2..],
        .alias => arg[1..],
    };

    const idx = std.mem.indexOfScalar(u8, current, '=');

    const name = if (idx) |i| current[0..i] else current;
    const value = if (idx) |i| current[i + 1 ..] else null;

    // -=, --, --=
    if (name.len == 0) return null;

    switch (opt_id) {
        .key => |*id| {
            id.* = name;
        },
        .alias => |*id| {
            id.* = name[0];
        },
    }

    return .{
        .identity = opt_id,
        .value = value,
    };
}
