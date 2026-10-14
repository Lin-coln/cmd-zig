const std = @import("std");
const t = std.testing;

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

test "parseDescriptorFromArg classifies terminators, options, and unrecognized arguments" {
    try t.expect(parseDescriptorFromArg("--") == .doubleDash);
    const option = parseDescriptorFromArg("-v=true").option;
    try t.expectEqual(@as(u8, 'v'), option.identity.alias);
    try t.expectEqualStrings("true", option.value.?);
    try t.expectEqualStrings("bad-name", parseDescriptorFromArg("--bad-name=").option.identity.key);
    try t.expectEqualStrings("-ab", parseDescriptorFromArg("-ab").unknown);
    try t.expectEqualStrings("file", parseDescriptorFromArg("file").unknown);
}
