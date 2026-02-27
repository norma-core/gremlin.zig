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
const gen = @import("src/codegen/gen.zig");
const generateProtobuf = gen.generateProtobuf;

const ProtoGenStep = @This();

step: std.Build.Step,
proto_sources: std.Build.LazyPath,
gen_output: std.Build.LazyPath,
ignore_masks: ?[]const []const u8,

pub const ProtoGenConfig = struct {
    name: []const u8 = "protobuf",
    proto_sources: std.Build.LazyPath,
    target: std.Build.LazyPath,
    ignore_masks: ?[]const []const u8 = null,
};

pub fn create(
    owner: *std.Build,
    config: ProtoGenConfig,
) *ProtoGenStep {
    const step = owner.allocator.create(ProtoGenStep) catch @panic("OOM");
    step.* = .{
        .step = std.Build.Step.init(.{
            .id = std.Build.Step.Id.custom,
            .name = config.name,
            .owner = owner,
            .makeFn = make,
        }),
        .proto_sources = config.proto_sources,
        .gen_output = config.target,
        .ignore_masks = config.ignore_masks,
    };
    return step;
}

fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const b = step.owner;
    const ps: *ProtoGenStep = @fieldParentPtr("step", step);

    const proto_path = try ps.proto_sources.getPath3(b, step).toString(b.allocator);
    const target_path = try ps.gen_output.getPath3(b, step).toString(b.allocator);

    const proto_path_resolved = try std.Build.Cache.Directory.cwd().handle.realpathAlloc(b.allocator, proto_path);
    defer b.allocator.free(proto_path_resolved);

    generateProtobuf(
        b.allocator,
        proto_path_resolved,
        target_path,
        ps.ignore_masks,
    ) catch |err| {
        std.log.err("failed to generate protobuf code: {s}", .{@errorName(err)});
        return err;
    };
}

test {
    std.testing.refAllDecls(gen);
}
