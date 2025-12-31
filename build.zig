//               .'\   /`.
//             .'.-.`-'.-.`.
//        ..._:   .-. .-.   :_...
//      .'    '-.(o ) (o ).-'    `.
//     :  _    _ _`~(_)~`_ _    _  :
//    :  /:   ' .-=_   _=-. `   ;\  :
//    :   :|-.._  '     `  _..-|:   :
//     :   `:| |`:-:-.-:-:'| |:'   :
//      `.   `.| | | | | | |.'   .'
//        `.   `-:_| | |_:-'   .'
//          `-._   ````    _.-'
//              ``-------''
//
// Created by ab, 14.11.2024

const std = @import("std");

pub const ProtoGenStep = @import("step.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("gremlin_parser", .{
        .root_source_file = b.path("src/parser/main.zig"),
    });

    const gremlin = b.addModule("gremlin", .{
        .root_source_file = b.path("src/gremlin/main.zig"),
    });

    const test_step = b.step("test", "Run tests");

    {
        const parser_test = b.addTest(.{
            .name = "parser",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/parser/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_parser_tests = b.addRunArtifact(parser_test);
        test_step.dependOn(&run_parser_tests.step);
    }

    {
        const gremlin_test = b.addTest(.{
            .name = "wire",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/gremlin/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_gremiln_tests = b.addRunArtifact(gremlin_test);
        test_step.dependOn(&run_gremiln_tests.step);
    }

    {
        const codegen_test = b.addTest(.{
            .name = "codegen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("step.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_codegen_tests = b.addRunArtifact(codegen_test);
        test_step.dependOn(&run_codegen_tests.step);
    }

    {
        const proto_gen_step = b.step("proto-gen", "Generate protobuf files");

        const google_protobuf = ProtoGenStep.create(
            b,
            .{
                .name = "test_data/google protobuf",
                .proto_sources = b.path("test_data/google"),
                .target = b.path("integration-test/gen/google"),
            },
        );
        proto_gen_step.dependOn(&google_protobuf.step);

        const gogofast_protobuf = ProtoGenStep.create(
            b,
            .{
                .name = "test_data/gogofast protobuf",
                .proto_sources = b.path("test_data/gogofast"),
                .target = b.path("integration-test/gen/gogofast"),
            },
        );
        proto_gen_step.dependOn(&gogofast_protobuf.step);

        const ambg_ref_protobuf = ProtoGenStep.create(
            b,
            .{
                .name = "test_data/ambg_ref protobuf",
                .proto_sources = b.path("test_data/ambg_ref"),
                .target = b.path("integration-test/gen/ambg_ref"),
            },
        );
        proto_gen_step.dependOn(&ambg_ref_protobuf.step);

        const integration_test = b.addTest(.{
            .name = "integration",
            .root_module = b.createModule(.{
                .root_source_file = b.path("integration-test/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        integration_test.step.dependOn(proto_gen_step);
        integration_test.root_module.addImport("gremlin", gremlin);

        const run_integration = b.addRunArtifact(integration_test);
        test_step.dependOn(&run_integration.step);

        // Add benchmark binary
        const benchmark_step = b.step("benchmark", "Build serialization benchmark");

        const benchmark_exe = b.addExecutable(.{
            .name = "serialization-benchmark",
            .root_module = b.createModule(.{
                .root_source_file = b.path("integration-test/benchmark.zig"),
                .target = target,
                .optimize = .ReleaseFast, // Use ReleaseFast for benchmarks
            }),
        });

        benchmark_exe.step.dependOn(proto_gen_step);
        benchmark_exe.root_module.addImport("gremlin", gremlin);

        const install_benchmark = b.addInstallArtifact(benchmark_exe, .{});
        benchmark_step.dependOn(&install_benchmark.step);

        // Add a run step for the benchmark
        const run_benchmark = b.addRunArtifact(benchmark_exe);
        run_benchmark.step.dependOn(&install_benchmark.step);

        if (b.args) |args| {
            run_benchmark.addArgs(args);
        } else {
            run_benchmark.addArg("1000"); // Default to 1000 iterations
        }

        const run_benchmark_step = b.step("run-benchmark", "Run serialization benchmark");
        run_benchmark_step.dependOn(&run_benchmark.step);
    }
}
