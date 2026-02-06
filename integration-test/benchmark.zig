const std = @import("std");
const benchmark = @import("gen/google/benchmark.proto.zig");
const unittest = @import("gen/google/unittest.proto.zig");
const unittest_import = @import("gen/google/unittest_import.proto.zig");
const unittest_import_public = @import("gen/google/unittest_import_public.proto.zig");
const gremlin = @import("gremlin");

// ============================================================================
// Golden Message Creation (TestAllTypes)
// ============================================================================

fn createGoldenMessage() unittest.TestAllTypes {
    return unittest.TestAllTypes{
        .optional_int32 = 101,
        .optional_int64 = 102,
        .optional_uint32 = 103,
        .optional_uint64 = 104,
        .optional_sint32 = 105,
        .optional_sint64 = 106,
        .optional_fixed32 = 107,
        .optional_fixed64 = 108,
        .optional_sfixed32 = 109,
        .optional_sfixed64 = 110,
        .optional_float = 111.0,
        .optional_double = 112.0,
        .optional_bool = true,
        .optional_string = "115",
        .optional_bytes = "116",
        .optional_nested_message = unittest.TestAllTypes.NestedMessage{
            .bb = 118,
        },
        .optional_foreign_message = unittest.ForeignMessage{
            .c = 119,
        },
        .optional_import_message = unittest_import.ImportMessage{
            .d = 120,
        },
        .optional_nested_enum = unittest.TestAllTypes.NestedEnum.BAZ,
        .optional_foreign_enum = unittest.ForeignEnum.FOREIGN_BAZ,
        .optional_import_enum = unittest_import.ImportEnum.IMPORT_BAZ,
        .optional_string_piece = "124",
        .optional_cord = "125",
        .optional_public_import_message = unittest_import_public.PublicImportMessage{
            .e = 126,
        },
        .optional_lazy_message = unittest.TestAllTypes.NestedMessage{
            .bb = 127,
        },
        .optional_unverified_lazy_message = unittest.TestAllTypes.NestedMessage{
            .bb = 128,
        },
        .repeated_int32 = &[_]i32{ 201, 301 },
        .repeated_int64 = &[_]i64{ 202, 302 },
        .repeated_uint32 = &[_]u32{ 203, 303 },
        .repeated_uint64 = &[_]u64{ 204, 304 },
        .repeated_sint32 = &[_]i32{ 205, 305 },
        .repeated_sint64 = &[_]i64{ 206, 306 },
        .repeated_fixed32 = &[_]u32{ 207, 307 },
        .repeated_fixed64 = &[_]u64{ 208, 308 },
        .repeated_sfixed32 = &[_]i32{ 209, 309 },
        .repeated_sfixed64 = &[_]i64{ 210, 310 },
        .repeated_float = &[_]f32{ 211.0, 311.0 },
        .repeated_double = &[_]f64{ 212.0, 312.0 },
        .repeated_bool = &[_]bool{ true, false },
        .repeated_string = &[_]?[]const u8{ "215", "315" },
        .repeated_bytes = &[_]?[]const u8{ "216", "316" },
        .repeated_nested_message = &[_]?unittest.TestAllTypes.NestedMessage{
            unittest.TestAllTypes.NestedMessage{ .bb = 218 },
            unittest.TestAllTypes.NestedMessage{ .bb = 318 },
        },
        .repeated_foreign_message = &[_]?unittest.ForeignMessage{
            unittest.ForeignMessage{ .c = 219 },
            unittest.ForeignMessage{ .c = 319 },
        },
        .repeated_import_message = &[_]?unittest_import.ImportMessage{
            unittest_import.ImportMessage{ .d = 220 },
            unittest_import.ImportMessage{ .d = 320 },
        },
        .repeated_nested_enum = &[_]unittest.TestAllTypes.NestedEnum{ unittest.TestAllTypes.NestedEnum.BAR, unittest.TestAllTypes.NestedEnum.BAZ },
        .repeated_foreign_enum = &[_]unittest.ForeignEnum{ unittest.ForeignEnum.FOREIGN_BAR, unittest.ForeignEnum.FOREIGN_BAZ },
        .repeated_import_enum = &[_]unittest_import.ImportEnum{ unittest_import.ImportEnum.IMPORT_BAR, unittest_import.ImportEnum.IMPORT_BAZ },
        .repeated_string_piece = &[_]?[]const u8{ "224", "324" },
        .repeated_cord = &[_]?[]const u8{ "225", "325" },
        .repeated_lazy_message = &[_]?unittest.TestAllTypes.NestedMessage{
            unittest.TestAllTypes.NestedMessage{ .bb = 227 },
            unittest.TestAllTypes.NestedMessage{ .bb = 327 },
        },
        .default_int32 = 401,
        .default_int64 = 402,
        .default_uint32 = 403,
        .default_uint64 = 404,
        .default_sint32 = 405,
        .default_sint64 = 406,
        .default_fixed32 = 407,
        .default_fixed64 = 408,
        .default_sfixed32 = 409,
        .default_sfixed64 = 410,
        .default_float = 411.0,
        .default_double = 412.0,
        .default_bool = false,
        .default_string = "415",
        .default_bytes = "416",
        .default_nested_enum = unittest.TestAllTypes.NestedEnum.FOO,
        .default_foreign_enum = unittest.ForeignEnum.FOREIGN_FOO,
        .default_import_enum = unittest_import.ImportEnum.IMPORT_FOO,
        .default_string_piece = "424",
        .default_cord = "425",
        .oneof_uint32 = 601,
    };
}

fn updateGoldenMessage(msg: *unittest.TestAllTypes, repeated_storage: []?unittest.TestAllTypes.NestedMessage, i: i32) void {
    msg.optional_int32 = 101 + i;
    msg.optional_nested_message.?.bb = 118 + i;

    // Update in-place without reallocation
    repeated_storage[0].?.bb = 218 + i;
    repeated_storage[1].?.bb = 318 + i;
    msg.repeated_nested_message = repeated_storage;

    msg.oneof_uint32 = @intCast(601 + i);
}

// ============================================================================
// Deep Nested Message Creation
// ============================================================================

fn createDeepNested() benchmark.DeepNested {
    const items_level1 = [_]?benchmark.Level1{
        benchmark.Level1{
        .id = 11,
        .title = "item1_top_level",
        .score = 2.34,
        .nested = benchmark.Level2{
            .id = 110,
            .description = "nested_in_top_item1",
            .payload = "some payload data",
            .nested = benchmark.Level3{
                .id = 1100,
                .name = "deeply_nested_top_item1",
            },
        },
        },
        benchmark.Level1{
        .id = 12,
        .title = "item2_top_level",
        .score = 3.45,
        .nested = benchmark.Level2{
            .id = 120,
            .description = "nested_in_top_item2",
            .payload = "more payload data here",
        },
        },
        benchmark.Level1{
        .id = 13,
        .title = "item3_top_level",
        .score = 4.56,
        },
        benchmark.Level1{
        .id = 14,
        .title = "item4_top_level",
        .score = 5.67,
        .nested = benchmark.Level2{
            .id = 140,
            .description = "nested_in_top_item4",
            .payload = "final payload data",
        },
        },
        benchmark.Level1{
        .id = 15,
        .title = "item5_top_level",
        .score = 6.78,
        },
    };

    const items_level4 = [_]?benchmark.Level4{
        benchmark.Level4{ .value = 41, .data = "item1_with_numbers", .numbers = &[_]i32{ 10, 20, 30, 40, 50 } },
        benchmark.Level4{ .value = 42, .data = "item2_with_numbers", .numbers = &[_]i32{ 60, 70, 80, 90, 100 } },
        benchmark.Level4{ .value = 43, .data = "item3_with_numbers", .numbers = &[_]i32{ 110, 120, 130, 140, 150 } },
        benchmark.Level4{ .value = 44, .data = "item4_with_numbers", .numbers = &[_]i32{ 160, 170, 180, 190, 200 } },
        benchmark.Level4{ .value = 45, .data = "item5_with_numbers", .numbers = &[_]i32{ 210, 220, 230, 240, 250 } },
    };

    const sub_items1 = [_]?benchmark.Level4{
        benchmark.Level4{ .value = 311, .data = "sub1", .numbers = &[_]i32{ 1, 2 } },
        benchmark.Level4{ .value = 312, .data = "sub2", .numbers = &[_]i32{ 3, 4 } },
    };

    const sub_items2 = [_]?benchmark.Level4{
        benchmark.Level4{ .value = 321, .data = "sub3", .numbers = &[_]i32{ 5, 6 } },
        benchmark.Level4{ .value = 322, .data = "sub4", .numbers = &[_]i32{ 7, 8 } },
    };

    const items_level3 = [_]?benchmark.Level3{
        benchmark.Level3{
        .id = 31,
        .name = "item1_nested",
        .nested = benchmark.Level4{
            .value = 310,
            .data = "nested_item1_data",
            .numbers = &[_]i32{ 1, 2, 3, 4, 5 },
        },
            .items = &sub_items1,
        },
        benchmark.Level3{
        .id = 32,
        .name = "item2_nested",
        .nested = benchmark.Level4{
            .value = 320,
            .data = "nested_item2_data",
            .numbers = &[_]i32{ 6, 7, 8, 9, 10 },
        },
            .items = &sub_items2,
        },
        benchmark.Level3{
            .id = 33,
            .name = "item3_nested",
            .nested = benchmark.Level4{
                .value = 330,
                .data = "nested_item3_data",
                .numbers = &[_]i32{ 11, 12, 13, 14, 15 },
            },
        },
        benchmark.Level3{
            .id = 34,
            .name = "item4_nested",
            .nested = benchmark.Level4{
                .value = 340,
                .data = "nested_item4_data",
                .numbers = &[_]i32{ 16, 17, 18, 19, 20 },
            },
        },
    };

    const items_level2 = [_]?benchmark.Level2{
        benchmark.Level2{
        .id = 21,
        .description = "item1_level2_with_payload",
        .payload = "payload for item 1",
        .nested = benchmark.Level3{
            .id = 210,
            .name = "nested_in_item1",
            .nested = benchmark.Level4{
                .value = 2100,
                .data = "deep_nested",
                .numbers = &[_]i32{ 100, 200, 300 },
            },
        },
        },
        benchmark.Level2{
        .id = 22,
        .description = "item2_level2_with_payload",
        .payload = "payload for item 2 with more data",
        .nested = benchmark.Level3{
            .id = 220,
            .name = "nested_in_item2",
        },
        },
        benchmark.Level2{
        .id = 23,
        .description = "item3_level2_with_payload",
        .payload = "payload for item 3",
        },
        benchmark.Level2{
            .id = 24,
            .description = "item4_level2_with_payload",
            .payload = "payload for item 4 with additional content",
        },
    };

    return benchmark.DeepNested{
        .root_id = 1,
        .root_name = "root_node_with_complex_nested_structure",
        .active = true,
        .tags = &[_]?[]const u8{ "tag1", "tag2", "tag3", "tag4", "tag5", "tag6", "tag7", "tag8" },
        .nested = benchmark.Level1{
            .id = 10,
            .title = "level1_primary_branch",
            .score = 1.23456789,
            .nested = benchmark.Level2{
                .id = 20,
                .description = "level2_deeply_nested_with_payload",
                .payload = "this is a much longer payload with more realistic data content that would be found in production systems",
                .nested = benchmark.Level3{
                    .id = 30,
                    .name = "level3_inner_structure",
                    .nested = benchmark.Level4{
                        .value = 40,
                        .data = "level4_leaf_node_with_data",
                        .numbers = &[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
                    },
                    .items = &items_level4,
                },
                .items = &items_level3,
            },
            .items = &items_level2,
        },
        .items = &items_level1,
    };
}

// ============================================================================
// Benchmark Runner
// ============================================================================

fn formatWithUnderscores(n: usize, buf: *[32]u8) []const u8 {
    const s = std.fmt.bufPrint(buf, "{d}", .{n}) catch unreachable;
    if (s.len <= 3) {
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }

    var result_len: usize = 0;

    for (s, 0..) |digit, i| {
        if (i > 0 and (s.len - i) % 3 == 0) {
            buf[result_len] = '_';
            result_len += 1;
        }
        buf[result_len] = digit;
        result_len += 1;
    }

    return buf[0..result_len];
}

fn getCpuInfo(allocator: std.mem.Allocator) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "sysctl", "-n", "machdep.cpu.brand_string" },
    }) catch {
        return allocator.dupe(u8, "Unknown");
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    return allocator.dupe(u8, std.mem.trim(u8, result.stdout, &std.ascii.whitespace));
}

fn getCpuCores() usize {
    return std.Thread.getCpuCount() catch 1;
}

fn benchmarkMarshalDeepNested(msg: benchmark.DeepNested, data: []u8, iterations: usize) i64 {
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var w = gremlin.Writer.init(data);
        msg.encodeTo(&w);
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        var w = gremlin.Writer.init(data);
        msg.encodeTo(&w);
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkUnmarshalDeepNested(data: []const u8, allocator: std.mem.Allocator, iterations: usize) i64 {
    _ = allocator;
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = benchmark.DeepNestedReader.init(data) catch unreachable;
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        _ = benchmark.DeepNestedReader.init(data) catch unreachable;
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkLazyReadDeepNested(data: []const u8, allocator: std.mem.Allocator, iterations: usize) i64 {
    _ = allocator;
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const decoded = benchmark.DeepNestedReader.init(data) catch unreachable;
        _ = decoded.getRootId();
        _ = decoded.getRootName();
        _ = decoded.getActive();
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        const decoded = benchmark.DeepNestedReader.init(data) catch unreachable;
        _ = decoded.getRootId();
        _ = decoded.getRootName();
        _ = decoded.getActive();
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkDeepAccessDeepNested(data: []const u8, allocator: std.mem.Allocator, iterations: usize) i64 {
    _ = allocator;
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const decoded = benchmark.DeepNestedReader.init(data) catch unreachable;
        _ = decoded.getRootId();
        const n1 = decoded.getNested() catch unreachable;
        _ = n1.getId();
        const n2 = n1.getNested() catch unreachable;
        _ = n2.getId();
        const n3 = n2.getNested() catch unreachable;
        _ = n3.getId();
        const n4 = n3.getNested() catch unreachable;
        _ = n4.getValue();
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        const decoded = benchmark.DeepNestedReader.init(data) catch unreachable;
        _ = decoded.getRootId();
        const n1 = decoded.getNested() catch unreachable;
        _ = n1.getId();
        const n2 = n1.getNested() catch unreachable;
        _ = n2.getId();
        const n3 = n2.getNested() catch unreachable;
        _ = n3.getId();
        const n4 = n3.getNested() catch unreachable;
        _ = n4.getValue();
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkMarshalGolden(msg: *unittest.TestAllTypes, repeated_storage: []?unittest.TestAllTypes.NestedMessage, data: []u8, iterations: usize) i64 {
    // Warmup
    var i: i32 = 0;
    while (i < 100) : (i += 1) {
        updateGoldenMessage(msg, repeated_storage, i);
        var w = gremlin.Writer.init(data);
        msg.encodeTo(&w);
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < @as(i32, @intCast(iterations))) : (i += 1) {
        updateGoldenMessage(msg, repeated_storage, i);
        var w = gremlin.Writer.init(data);
        msg.encodeTo(&w);
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkUnmarshalGolden(data: []const u8, allocator: std.mem.Allocator, iterations: usize) i64 {
    _ = allocator;
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = unittest.TestAllTypesReader.init(data) catch unreachable;
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        _ = unittest.TestAllTypesReader.init(data) catch unreachable;
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkLazyReadGolden(data: []const u8, allocator: std.mem.Allocator, iterations: usize) i64 {
    _ = allocator;
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const decoded = unittest.TestAllTypesReader.init(data) catch unreachable;
        _ = decoded.getOptionalInt32();
        _ = decoded.getOptionalInt64();
        _ = decoded.getOptionalString();
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        const decoded = unittest.TestAllTypesReader.init(data) catch unreachable;
        _ = decoded.getOptionalInt32();
        _ = decoded.getOptionalInt64();
        _ = decoded.getOptionalString();
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

fn benchmarkDeepAccessGolden(data: []const u8, allocator: std.mem.Allocator, iterations: usize) i64 {
    _ = allocator;
    // Warmup
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const decoded = unittest.TestAllTypesReader.init(data) catch unreachable;
        _ = decoded.getOptionalInt32();
        _ = decoded.getOptionalString();
        const nested = decoded.getOptionalNestedMessage() catch unreachable;
        _ = nested.getBb();
        const foreign = decoded.getOptionalForeignMessage() catch unreachable;
        _ = foreign.getC();
        const import_msg = decoded.getOptionalImportMessage() catch unreachable;
        _ = import_msg.getD();
    }

    const start = std.time.nanoTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        const decoded = unittest.TestAllTypesReader.init(data) catch unreachable;
        _ = decoded.getOptionalInt32();
        _ = decoded.getOptionalString();
        const nested = decoded.getOptionalNestedMessage() catch unreachable;
        _ = nested.getBb();
        const foreign = decoded.getOptionalForeignMessage() catch unreachable;
        _ = foreign.getC();
        const import_msg = decoded.getOptionalImportMessage() catch unreachable;
        _ = import_msg.getD();
    }
    const end = std.time.nanoTimestamp();

    const total_ns: i128 = end - start;
    return @intCast(@divTrunc(total_ns, @as(i128, @intCast(iterations))));
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const iterations: usize = if (args.len >= 2)
        try std.fmt.parseInt(usize, args[1], 10)
    else
        10_000_000;

    // Print header
    std.debug.print("===========================================\n", .{});
    std.debug.print("gremlin.zig Benchmarks\n", .{});
    std.debug.print("===========================================\n", .{});

    const cpu_info = try getCpuInfo(allocator);
    defer allocator.free(cpu_info);
    std.debug.print("CPU: {s}\n", .{cpu_info});
    std.debug.print("CPU Cores: {d}\n", .{getCpuCores()});

    var buf: [32]u8 = undefined;
    std.debug.print("Iterations: {s}\n", .{formatWithUnderscores(iterations, &buf)});
    std.debug.print("===========================================\n\n", .{});

    // Run Deep Nested Benchmarks
    try runDeepNestedBenchmarks(allocator, iterations);
    std.debug.print("\n", .{});

    // Run Golden Message Benchmarks
    try runGoldenMessageBenchmarks(allocator, iterations);

    std.debug.print("\n===========================================\n", .{});
    std.debug.print("Benchmark Complete!\n", .{});
    std.debug.print("===========================================\n", .{});
}

fn runDeepNestedBenchmarks(allocator: std.mem.Allocator, iterations: usize) !void {
    std.debug.print("🌳 DEEP NESTED MESSAGE BENCHMARKS\n", .{});
    std.debug.print("-------------------------------------------\n", .{});

    // Create message and serialize
    const msg = createDeepNested();
    const size = msg.calcProtobufSize();
    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    var encode_writer = gremlin.Writer.init(data);
    msg.encodeTo(&encode_writer);

    std.debug.print("📦 Message Size: {d} bytes\n\n", .{size});

    // Marshal benchmark
    std.debug.print("🔨 Marshal (Serialize):\n", .{});
    const marshal_time = benchmarkMarshalDeepNested(msg, data, iterations);
    std.debug.print("  {d} ns/op\n\n", .{marshal_time});

    // Unmarshal benchmark
    std.debug.print("📖 Unmarshal (Deserialize):\n", .{});
    const unmarshal_time = benchmarkUnmarshalDeepNested(data, allocator, iterations);
    std.debug.print("  {d} ns/op\n\n", .{unmarshal_time});

    // Lazy Read (root only)
    std.debug.print("🎯 Unmarshal + Root Access (Lazy Parsing):\n", .{});
    const lazy_time = benchmarkLazyReadDeepNested(data, allocator, iterations);
    std.debug.print("  {d} ns/op\n\n", .{lazy_time});

    // Deep Access
    std.debug.print("🔍 Full Deep Access (All Nested Fields):\n", .{});
    const deep_time = benchmarkDeepAccessDeepNested(data, allocator, iterations);
    std.debug.print("  {d} ns/op\n", .{deep_time});
}

fn runGoldenMessageBenchmarks(allocator: std.mem.Allocator, iterations: usize) !void {
    std.debug.print("📜 GOLDEN MESSAGE BENCHMARKS (protobuf_unittest)\n", .{});
    std.debug.print("-------------------------------------------\n", .{});

    // Load golden message binary
    const golden_data = @embedFile("binaries/golden_message");
    std.debug.print("📦 Message Size: {d} bytes\n\n", .{golden_data.len});

    // Create message for marshal benchmark
    var msg = createGoldenMessage();

    // Allocate mutable storage for repeated nested messages
    var repeated_storage = try allocator.alloc(?unittest.TestAllTypes.NestedMessage, 2);
    defer allocator.free(repeated_storage);
    repeated_storage[0] = unittest.TestAllTypes.NestedMessage{ .bb = 218 };
    repeated_storage[1] = unittest.TestAllTypes.NestedMessage{ .bb = 318 };
    msg.repeated_nested_message = repeated_storage;

    const size = msg.calcProtobufSize();
    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    // Marshal benchmark
    std.debug.print("🔨 Marshal (Serialize):\n", .{});
    const marshal_time = benchmarkMarshalGolden(&msg, repeated_storage, data, iterations);
    std.debug.print("  {d} ns/op\n\n", .{marshal_time});

    // Unmarshal benchmark
    std.debug.print("📖 Unmarshal (Deserialize):\n", .{});
    const unmarshal_time = benchmarkUnmarshalGolden(golden_data, allocator, iterations);
    std.debug.print("  {d} ns/op\n\n", .{unmarshal_time});

    // Lazy Read (root only)
    std.debug.print("🎯 Unmarshal + Root Access (Lazy Parsing):\n", .{});
    const lazy_time = benchmarkLazyReadGolden(golden_data, allocator, iterations);
    std.debug.print("  {d} ns/op\n\n", .{lazy_time});

    // Deep Access
    std.debug.print("🔍 Deep Access (Including Nested Messages):\n", .{});
    const deep_time = benchmarkDeepAccessGolden(golden_data, allocator, iterations);
    std.debug.print("  {d} ns/op\n", .{deep_time});
}
