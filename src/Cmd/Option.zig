const std = @import("std");
const Args = @import("../Args/Self.zig");

pub const Parser = union(enum) {
    bool: void,
    string: void,
};
pub const Entry = struct {
    opt: *const Self,
    value: ?[]const u8 = null,
};
const Self = @This();
key: []const u8,
alias: ?u8 = null,
desc: ?[]const u8 = null,
// required: bool = false,
parser: Parser,

pub fn parseEntry(opts: []const Self, desc: Args.Descriptor) ?Entry {
    switch (desc) {
        .option => |d| {
            const opt: *const Self = findOption(opts, d) orelse return null;
            return .{
                .opt = opt,
                .value = d.value,
            };
        },
        else => return null,
    }
}

fn findOption(opts: []const Self, desc: Args.OptionDescriptor) ?*const Self {
    for (opts) |*opt| {
        switch (desc.identity) {
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
