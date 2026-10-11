const std = @import("std");

pub const OptionDescriptor = @import("OptionDescriptor.zig");

pub const Descriptor = union(enum) {
    option: OptionDescriptor,
    doubleDash: void,
    unknown: []const u8,
};

pub fn parseDescriptorFromArg(arg: []const u8) Descriptor {
    if (arg.len == 2 and arg[0] == '-' and arg[1] == '-') {
        return .doubleDash;
    }

    if (OptionDescriptor.parseFromArg(arg)) |opt| return .{ .option = opt };

    return .{ .unknown = arg };
}
