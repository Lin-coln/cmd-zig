const std = @import("std");
const t = std.testing;

pub const Type = std.meta.Tag(Value);
pub const Value = union(enum) {
    boolean: bool,
    int: i64,
    float: f64,
    string: []const u8,

    pub fn parse(kind: Type, raw: []const u8) !Value {
        switch (kind) {
            .string => return .{ .string = raw },
            .boolean => {
                if (std.mem.eql(u8, raw, "false")) {
                    return .{ .boolean = false };
                } else if (std.mem.eql(u8, raw, "true")) {
                    return .{ .boolean = true };
                } else {
                    return error.InvalidOptionValueFound;
                }
            },
            .int => {
                return .{ .int = std.fmt.parseInt(i64, raw, 10) catch return error.InvalidOptionValueFound };
            },
            .float => {
                return .{ .float = std.fmt.parseFloat(f64, raw) catch return error.InvalidOptionValueFound };
            },
        }
    }
};

test "Value.parse: returns the declared type for valid raw values" {
    const cases = [_]struct { kind: Type, raw: []const u8, expected: Value }{
        .{ .kind = .string, .raw = "file", .expected = .{ .string = "file" } },
        .{ .kind = .string, .raw = "", .expected = .{ .string = "" } },
        .{ .kind = .boolean, .raw = "true", .expected = .{ .boolean = true } },
        .{ .kind = .boolean, .raw = "false", .expected = .{ .boolean = false } },
        .{ .kind = .int, .raw = "42", .expected = .{ .int = 42 } },
        .{ .kind = .int, .raw = "0", .expected = .{ .int = 0 } },
        .{ .kind = .int, .raw = "-1", .expected = .{ .int = -1 } },
        .{ .kind = .float, .raw = "1.5", .expected = .{ .float = 1.5 } },
        .{ .kind = .float, .raw = "-0.25", .expected = .{ .float = -0.25 } },
    };
    comptime {
        for (@typeInfo(Type).@"enum".fields) |field| {
            var covered = false;
            for (cases) |case| {
                if (std.mem.eql(u8, @tagName(case.kind), field.name)) covered = true;
            }
            if (!covered) @compileError("Value.parse cases need a " ++ field.name ++ " example");
        }
    }
    inline for (cases) |case| {
        try t.expectEqualDeep(case.expected, try Value.parse(case.kind, case.raw));
    }
}

test "Value.parse: rejects invalid raw values" {
    const cases = [_]struct { kind: Type, raw: []const u8 }{
        .{ .kind = .boolean, .raw = "yes" },
        .{ .kind = .boolean, .raw = "" },
        .{ .kind = .int, .raw = "" },
        .{ .kind = .int, .raw = "abc" },
        .{ .kind = .int, .raw = "9223372036854775808" },
        .{ .kind = .int, .raw = "-9223372036854775809" },
        .{ .kind = .float, .raw = "" },
        .{ .kind = .float, .raw = "abc" },
        .{ .kind = .float, .raw = "1.2.3" },
    };
    inline for (cases) |case| {
        try t.expectError(error.InvalidOptionValueFound, Value.parse(case.kind, case.raw));
    }
}
