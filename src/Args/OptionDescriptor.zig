const std = @import("std");
const t = std.testing;

const Identity = union(enum) { key: []const u8, alias: u8 };

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

    switch (opt_id) {
        .key => |*id| {
            if (name.len == 0) return null;
            id.* = name;
        },
        .alias => |*id| {
            if (name.len != 1) return null;
            id.* = name[0];
        },
    }

    return .{
        .identity = opt_id,
        .value = value,
    };
}

test "OptionDescriptor.parseFromArg: extracts identities and values from long and short options" {
    const long = parseFromArg("--output=file.txt").?;
    try t.expectEqualStrings("output", long.identity.key);
    try t.expectEqualStrings("file.txt", long.value.?);

    const short = parseFromArg("-o=").?;
    try t.expectEqual(@as(u8, 'o'), short.identity.alias);
    try t.expectEqualStrings("", short.value.?);

    const flag = parseFromArg("--verbose").?;
    try t.expectEqualStrings("verbose", flag.identity.key);
    try t.expect(flag.value == null);
}

test "OptionDescriptor.parseFromArg: rejects invalid option arguments" {
    for (&[_][]const u8{ "", "-", "--", "--=value", "-ab", "plain" }) |arg| {
        try t.expect(parseFromArg(arg) == null);
    }
}

test "OptionDescriptor.parseFromArg: preserves equal signs inside a value" {
    const value = parseFromArg("-a=1=2").?;
    try t.expectEqualStrings("1=2", value.value.?);
}
