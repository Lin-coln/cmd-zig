const std = @import("std");
const Command = @import("../Command/Self.zig");

pub const Identity = union(enum) {
    key: []const u8,
    alias: u8,
};
const Self = @This();
identity: Identity,
value: ?[]const u8 = null,

pub fn findOption(self: Self, opts: []const Command.Option) ?*const Command.Option {
    for (opts) |*opt| {
        switch (self.identity) {
            .key => |key| {
                if (std.mem.eql(u8, opt.key, key)) {
                    return opt;
                }
            },
            .alias => |alias| {
                if (opt.alias) |a| {
                    if (a == alias) {
                        return opt;
                    }
                }
            },
        }
    }

    return null;
}
