const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run tests");
    const run_step = b.step("run", "Run the app");

    const mod = b.addModule("mod", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const cli = b.addExecutable(.{
        .name = "cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mod", .module = mod },
            },
        }),
    });

    // cli
    {
        b.installArtifact(cli);

        const run_cmd = b.addRunArtifact(cli);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
    }

    // test
    {
        const run_mod_tests = b.addRunArtifact(b.addTest(.{
            .root_module = mod,
        }));

        const run_cli_tests = b.addRunArtifact(b.addTest(.{
            .root_module = cli.root_module,
        }));

        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_cli_tests.step);
    }
}
