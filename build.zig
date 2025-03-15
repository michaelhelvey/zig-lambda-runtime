const std = @import("std");

pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    if (env_map.get("LAMBDA_TARGET_AARCH64") != null) {
        std.debug.print("building for linux aarch64 target\n", .{});
        target = b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
        });
    } else {
        std.debug.print("building for native architecture\n", .{});
    }

    // ------------------------------------------------------------------------
    // Create our library module that contains our runtime.
    // ------------------------------------------------------------------------

    const lib_lambda_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ------------------------------------------------------------------------
    // Create an example Zig lambda function that uses our library.
    // ------------------------------------------------------------------------

    const example_mod = b.createModule(.{
        .root_source_file = b.path("src/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("lambda", lib_lambda_mod);

    const example_exe = b.addExecutable(.{
        .name = "bootstrap", // the default executable name for lamba custom runtimes
        .root_module = example_mod,
    });

    b.installArtifact(example_exe);

    // ------------------------------------------------------------------------
    // Configure a tests target for the library
    // ------------------------------------------------------------------------

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_lambda_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
