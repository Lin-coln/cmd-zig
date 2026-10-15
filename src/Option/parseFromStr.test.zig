const parseFromStr = @import("parseFromStr.zig").parseFromStr;

pub const CompileTestCases = .{
    .{
        .name = "parseFromStr: rejects whitespace in the option name",
        .expected_error = "error: Invalid option format",
    },
};

test "parseFromStr: rejects whitespace in the option name" {
    _ = comptime parseFromStr("--bad name");
}
