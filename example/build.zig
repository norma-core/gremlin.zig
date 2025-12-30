const std = @import("std");
const ProtoGenStep = @import("gremlin").ProtoGenStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the gremlin dependency
    const gremlin_dep = b.dependency("gremlin", .{
        .target = target,
        .optimize = optimize,
    });

    // Get the gremlin module for imports
    const gremlin_module = gremlin_dep.module("gremlin");

    const protobuf = ProtoGenStep.create(
        b,
        .{
            .name = "example protobuf",
            .proto_sources = b.path("proto"),
            .target = b.path("src/gen"),
        },
    );

    // Create binary
    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add the gremlin module
    exe.root_module.addImport("gremlin", gremlin_module);
    exe.step.dependOn(&protobuf.step);

    b.installArtifact(exe);

    // Tests
    const lib_test = b.addTest(.{
        .name = "example_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add the gremlin module to tests
    lib_test.root_module.addImport("gremlin", gremlin_module);

    const run_tests = b.addRunArtifact(lib_test);
    run_tests.step.dependOn(&protobuf.step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
