const init = @import("init.zig").init;

pub const CompileTestCases = .{
    .{
        .name = "Option.init: rejects a default with a different type",
        .expected_error = "error: Option default type does not match option type",
    },
};

test "Option.init: rejects a default with a different type" {
    _ = init("--count=<val>", .{ .type = .int, .default = .{ .string = "1" } });
}
