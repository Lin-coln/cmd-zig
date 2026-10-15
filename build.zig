const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(addCompileErrorTests(b, target));

    const cmd = blk: {
        const mod = b.addModule("cmd", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
        });
        const tests = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(tests).step);
        break :blk mod;
    };

    const foo_step = blk: {
        const step = b.step("foo", "Run examples/foo");

        const exe = b.addExecutable(.{
            .name = "foo",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/foo.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "cmd", .module = cmd },
                },
            }),
        });
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);
        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| run.addArgs(args);

        const tests = b.addTest(.{ .root_module = exe.root_module });
        test_step.dependOn(&b.addRunArtifact(tests).step);

        break :blk step;
    };

    _ = foo_step;
}

fn addCompileErrorTests(b: *std.Build, target: std.Build.ResolvedTarget) *std.Build.Step {
    const step = b.step("test-compile-errors", "Check compile-time validation errors");
    inline for (@import("src/compile_test.zig").sources) |source| {
        inline for (source.CompileTestCases) |case| {
            const check = b.addTest(.{
                .name = "compile-test",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/compile_test.zig"),
                    .target = target,
                }),
                .filters = &.{case.name},
            });
            check.step.name = case.name;
            check.expect_errors = .{ .contains = case.expected_error };
            // Zig 0.16 needs code generation to retain diagnostics across cached builds.
            _ = check.getEmittedBin();
            step.dependOn(&check.step);
        }
    }
    return step;
}
