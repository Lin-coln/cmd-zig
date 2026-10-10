const std = @import("std");

pub const Parser = union(enum) {
    bool: void,
    string: void,
};

const Self = @This();
key: []const u8,
alias: ?u8 = null,
desc: ?[]const u8 = null,
// required: bool = false,
parser: Parser,
