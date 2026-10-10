const std = @import("std");
const OptionDescriptor = @import("OptionDescriptor.zig");

pub const Descriptor = union(enum) {
    pub const Option = OptionDescriptor;

    option: Option,
    doubleDash: void,
    unknown: []const u8,

    pub fn initFromSlice(arg: []const u8) Descriptor {
        if (arg.len < 2) return .{ .unknown = arg };
        if (arg[0] != '-') return .{ .unknown = arg };

        if (arg.len == 2 and arg[0] == '-' and arg[1] == '-') {
            return .doubleDash;
        }

        var opt_id: Option.Identity = if (arg[1] == '-') .{
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

        switch (opt_id) {
            .key => |*id| {
                id.* = name;
            },
            .alias => |*id| {
                id.* = name[0];
            },
        }

        return .{
            .option = .{
                .identity = opt_id,
                .value = value,
            },
        };
    }
};
