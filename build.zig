const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ------------------------------------------------------------------------
    // Create `liblambd.a`, both as a static library & header file that can be
    // used from C, and as a Zig module that can be consumed by the Zig package
    // manager.
    // ------------------------------------------------------------------------

    const lib_lambda_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_lambda = b.addLibrary(.{
        .linkage = .static,
        .name = "lambda",
        .root_module = lib_lambda_mod,
    });

    b.installArtifact(lib_lambda);
    // TODO: would be nice to generate a C header file here! but that behavior
    // is currently broken: https://github.com/ziglang/zig/issues/18497

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
