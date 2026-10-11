const std = @import("std");

pub const Command = @import("Command/Self.zig");
pub const Args = @import("Args/Self.zig");
pub const Cmd = @import("Cmd/Self.zig");

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
