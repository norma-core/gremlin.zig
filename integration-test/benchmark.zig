const std = @import("std");
const unittest = @import("gen/google/unittest.proto.zig");
const unittest_import = @import("gen/google/unittest_import.proto.zig");
const unittest_import_public = @import("gen/google/unittest_import_public.proto.zig");
const gremlin = @import("gremlin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: {s} <num_iterations>\n", .{args[0]});
        return;
    }

    const num_iterations = try std.fmt.parseInt(u32, args[1], 10);

    // Create the golden message structure (same as in the golden message test)
    const base_msg = unittest.TestAllTypes{
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
        .optional_float = 111,
        .optional_double = 112,
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
        .optional_public_import_message = unittest_import_public.PublicImportMessage{
            .e = 126,
        },
        .optional_lazy_message = unittest.TestAllTypes.NestedMessage{
            .bb = 127,
        },
        .optional_unverified_lazy_message = unittest.TestAllTypes.NestedMessage{
            .bb = 128,
        },
        .optional_nested_enum = unittest.TestAllTypes.NestedEnum.BAZ,
        .optional_foreign_enum = unittest.ForeignEnum.FOREIGN_BAZ,
        .optional_import_enum = unittest_import.ImportEnum.IMPORT_BAZ,
        .optional_string_piece = "124",
        .optional_cord = "125",
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
        .repeated_float = &[_]f32{ 211, 311 },
        .repeated_double = &[_]f64{ 212, 312 },
        .repeated_bool = &[_]bool{ true, false },
        .repeated_string = &[_]?[]const u8{ "215", "315" },
        .repeated_bytes = &[_]?[]const u8{ "216", "316" },
        .repeated_nested_message = &[_]?unittest.TestAllTypes.NestedMessage{
            unittest.TestAllTypes.NestedMessage{
                .bb = 218,
            },
            unittest.TestAllTypes.NestedMessage{
                .bb = 318,
            },
        },
        .repeated_foreign_message = &[_]?unittest.ForeignMessage{
            unittest.ForeignMessage{
                .c = 219,
            },
            unittest.ForeignMessage{
                .c = 319,
            },
        },
        .repeated_import_message = &[_]?unittest_import.ImportMessage{
            unittest_import.ImportMessage{
                .d = 220,
            },
            unittest_import.ImportMessage{
                .d = 320,
            },
        },
        .repeated_lazy_message = &[_]?unittest.TestAllTypes.NestedMessage{
            unittest.TestAllTypes.NestedMessage{
                .bb = 227,
            },
            unittest.TestAllTypes.NestedMessage{
                .bb = 327,
            },
        },
        .repeated_nested_enum = &[_]unittest.TestAllTypes.NestedEnum{ unittest.TestAllTypes.NestedEnum.BAR, unittest.TestAllTypes.NestedEnum.BAZ },
        .repeated_foreign_enum = &[_]unittest.ForeignEnum{ unittest.ForeignEnum.FOREIGN_BAR, unittest.ForeignEnum.FOREIGN_BAZ },
        .repeated_import_enum = &[_]unittest_import.ImportEnum{ unittest_import.ImportEnum.IMPORT_BAR, unittest_import.ImportEnum.IMPORT_BAZ },
        .repeated_string_piece = &[_]?[]const u8{ "224", "324" },
        .repeated_cord = &[_]?[]const u8{ "225", "325" },
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
        .default_float = 411,
        .default_double = 412,
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

    // Pre-allocate a buffer for serialization (10KB should be enough for our message)
    const buffer_size = 10 * 1024;
    const buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    // Variables to track timing
    var total_calc_size_ns: u64 = 0;
    var total_encode_ns: u64 = 0;
    var total_size: usize = 0;

    var i: u32 = 0;
    while (i < num_iterations) : (i += 1) {
        // Create a copy of the message with updated fields
        var msg = base_msg;

        // Update some fields with the iteration number
        msg.optional_int32 = @intCast(i);
        msg.optional_int64 = @intCast(i);
        msg.optional_uint32 = i;
        msg.optional_uint64 = i;

        // Measure calcProtobufSize time
        const calc_start = std.time.nanoTimestamp();
        const size = msg.calcProtobufSize();
        const calc_end = std.time.nanoTimestamp();
        total_calc_size_ns += @intCast(calc_end - calc_start);
        total_size += size;

        // Measure encodeTo time
        // Create a writer with our pre-allocated buffer
        var writer = gremlin.Writer.init(buffer);

        const encode_start = std.time.nanoTimestamp();
        msg.encodeTo(&writer);
        const encode_end = std.time.nanoTimestamp();
        total_encode_ns += @intCast(encode_end - encode_start);

        // Ensure the buffer is actually used (prevent optimization)
        std.mem.doNotOptimizeAway(writer.buf);
    }

    // Calculate averages
    const avg_calc_size_ns = @as(f64, @floatFromInt(total_calc_size_ns)) / @as(f64, @floatFromInt(num_iterations));
    const avg_encode_ns = @as(f64, @floatFromInt(total_encode_ns)) / @as(f64, @floatFromInt(num_iterations));
    const avg_total_ns = avg_calc_size_ns + avg_encode_ns;

    const avg_calc_size_us = avg_calc_size_ns / 1000.0;
    const avg_encode_us = avg_encode_ns / 1000.0;
    const avg_total_us = avg_total_ns / 1000.0;

    const iterations_per_second = 1_000_000_000.0 / avg_total_ns;

    std.debug.print("\nSerialization Benchmark Results:\n", .{});
    std.debug.print("================================\n", .{});
    std.debug.print("Iterations: {}\n", .{num_iterations});
    std.debug.print("Average message size: {} bytes\n\n", .{total_size / num_iterations});

    std.debug.print("Average times per operation:\n", .{});
    std.debug.print("  calcProtobufSize: {d:.3} ns ({d:.3} µs)\n", .{ avg_calc_size_ns, avg_calc_size_us });
    std.debug.print("  encodeTo:         {d:.3} ns ({d:.3} µs)\n", .{ avg_encode_ns, avg_encode_us });
    std.debug.print("  Total:            {d:.3} ns ({d:.3} µs)\n\n", .{ avg_total_ns, avg_total_us });

    std.debug.print("Throughput: {d:.0} operations/second\n", .{iterations_per_second});
    std.debug.print("            {d:.2} MB/second\n", .{(iterations_per_second * @as(f64, @floatFromInt(total_size / num_iterations))) / (1024.0 * 1024.0)});
}
