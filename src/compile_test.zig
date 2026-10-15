pub const sources = .{
    @import("Option/init.test.zig"),
    @import("Option/parseFromStr.test.zig"),
};

test {
    inline for (sources) |source| _ = source;
}
