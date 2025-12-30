const std = @import("std");
const gogofast = @import("gen/gogofast/gogofast.proto.zig");
const unittest = @import("gen/google/unittest.proto.zig");
const unittest_import = @import("gen/google/unittest_import.proto.zig");
const unittest_import_public = @import("gen/google/unittest_import_public.proto.zig");
const map_test = @import("gen/google/map_test.proto.zig");
const gremlin = @import("gremlin");
const Writer = gremlin.Writer;
const Reader = gremlin.Reader;

test "simple write" {
    const expected = &[_]u8{ 8, 101, 16, 102, 146, 1, 2, 8, 118, 232, 3, 0, 240, 3, 0, 248, 3, 0, 128, 4, 0, 136, 4, 0, 144, 4, 0, 157, 4, 0, 0, 0, 0, 161, 4, 0, 0, 0, 0, 0, 0, 0, 0, 173, 4, 0, 0, 0, 0, 177, 4, 0, 0, 0, 0, 0, 0, 0, 0, 189, 4, 0, 0, 0, 0, 193, 4, 0, 0, 0, 0, 0, 0, 0, 0, 200, 4, 0, 210, 4, 0, 218, 4, 0, 136, 5, 0, 144, 5, 0, 152, 5, 0, 162, 5, 0, 170, 5, 0 };
    const allocator = std.testing.allocator;

    const msg = unittest.TestAllTypes{
        .optional_int32 = 101,
        .optional_int64 = 102,
        .optional_nested_message = unittest.TestAllTypes.NestedMessage{ .bb = 118 },
    };

    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    try std.testing.expectEqualSlices(u8, expected, buf);
}

test "simple read" {
    const expected = &[_]u8{ 8, 101, 16, 102, 146, 1, 2, 8, 118, 232, 3, 0, 240, 3, 0, 248, 3, 0, 128, 4, 0, 136, 4, 0, 144, 4, 0, 157, 4, 0, 0, 0, 0, 161, 4, 0, 0, 0, 0, 0, 0, 0, 0, 173, 4, 0, 0, 0, 0, 177, 4, 0, 0, 0, 0, 0, 0, 0, 0, 189, 4, 0, 0, 0, 0, 193, 4, 0, 0, 0, 0, 0, 0, 0, 0, 200, 4, 0, 210, 4, 0, 218, 4, 0, 136, 5, 0, 144, 5, 0, 152, 5, 0, 162, 5, 0, 170, 5, 0 };

    const msg = try unittest.TestAllTypesReader.init(expected);
    try std.testing.expectEqual(101, msg.getOptionalInt32());
    try std.testing.expectEqual(102, msg.getOptionalInt64());

    const nested = try msg.getOptionalNestedMessage();

    try std.testing.expectEqual(118, nested.getBb());
}

test "map kv: empty" {
    const expected = &[_]u8{ 42, 4, 8, 0, 18, 0 };
    const allocator = std.testing.allocator;

    // Create map to hold the test data
    var int32_to_message_field = std.AutoHashMap(i32, map_test.TestMap.MessageValue).init(allocator);
    defer int32_to_message_field.deinit();

    // Add entries including null values
    try int32_to_message_field.put(0, map_test.TestMap.MessageValue{});

    // Create the test message
    const msg = map_test.TestMap{
        .int32_to_message_field = &int32_to_message_field,
    };

    // encode the message
    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    try std.testing.expectEqualSlices(u8, expected, buf);

    // Deencode the message
    var reader = try map_test.TestMapReader.init(buf);

    // Verify the map using iterator
    var found = false;
    while (try reader.nextInt32ToMessageField()) |entry| {
        if (entry.key == 0) {
            try std.testing.expectEqual(0, entry.value.getValue());
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "map kv: value" {
    const allocator = std.testing.allocator;

    // Create map to hold the test data
    var int32_to_message_field = std.AutoHashMap(i32, map_test.TestMap.MessageValue).init(allocator);
    defer int32_to_message_field.deinit();

    // Add entries including null values
    try int32_to_message_field.put(2, map_test.TestMap.MessageValue{
        .value = 32,
    });

    // Create the test message
    const msg = map_test.TestMap{
        .int32_to_message_field = &int32_to_message_field,
    };

    // encode the message
    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    // Deencode the message
    var reader = try map_test.TestMapReader.init(buf);

    // Verify the map using iterator
    var found = false;
    while (try reader.nextInt32ToMessageField()) |entry| {
        if (entry.key == 2) {
            try std.testing.expectEqual(32, entry.value.getValue());
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "negative values" {
    const expected = &[_]u8{ 8, 156, 255, 255, 255, 255, 255, 255, 255, 255, 1, 16, 155, 255, 255, 255, 255, 255, 255, 255, 255, 1, 40, 203, 1, 48, 205, 1, 77, 152, 255, 255, 255, 81, 151, 255, 255, 255, 255, 255, 255, 255, 93, 0, 0, 210, 194, 97, 0, 0, 0, 0, 0, 128, 90, 192, 250, 1, 20, 184, 254, 255, 255, 255, 255, 255, 255, 255, 1, 212, 253, 255, 255, 255, 255, 255, 255, 255, 1, 130, 2, 20, 183, 254, 255, 255, 255, 255, 255, 255, 255, 1, 211, 253, 255, 255, 255, 255, 255, 255, 255, 1, 154, 2, 4, 147, 3, 219, 4, 162, 2, 4, 149, 3, 221, 4, 186, 2, 8, 52, 255, 255, 255, 208, 254, 255, 255, 194, 2, 16, 51, 255, 255, 255, 255, 255, 255, 255, 207, 254, 255, 255, 255, 255, 255, 255, 202, 2, 8, 0, 0, 77, 195, 0, 128, 152, 195, 210, 2, 16, 0, 0, 0, 0, 0, 192, 105, 192, 0, 0, 0, 0, 0, 32, 115, 192, 232, 3, 0, 240, 3, 0, 248, 3, 0, 128, 4, 0, 136, 4, 0, 144, 4, 0, 157, 4, 0, 0, 0, 0, 161, 4, 0, 0, 0, 0, 0, 0, 0, 0, 173, 4, 0, 0, 0, 0, 177, 4, 0, 0, 0, 0, 0, 0, 0, 0, 189, 4, 0, 0, 0, 0, 193, 4, 0, 0, 0, 0, 0, 0, 0, 0, 200, 4, 0, 210, 4, 0, 218, 4, 0, 136, 5, 0, 144, 5, 0, 152, 5, 0, 162, 5, 0, 170, 5, 0 };
    const allocator = std.testing.allocator;

    const msg = unittest.TestAllTypes{
        .optional_int32 = -100,
        .optional_int64 = -101,
        .optional_sint32 = -102,
        .optional_sint64 = -103,
        .optional_sfixed32 = -104,
        .optional_sfixed64 = -105,
        .optional_float = -105,
        .optional_double = -106,

        .repeated_int32 = &[_]i32{ -200, -300 },
        .repeated_int64 = &[_]i64{ -201, -301 },
        .repeated_sint32 = &[_]i32{ -202, -302 },
        .repeated_sint64 = &[_]i64{ -203, -303 },
        .repeated_sfixed32 = &[_]i32{ -204, -304 },
        .repeated_sfixed64 = &[_]i64{ -205, -305 },
        .repeated_float = &[_]f32{ -205, -305 },
        .repeated_double = &[_]f64{ -206, -306 },
    };

    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    try std.testing.expectEqualSlices(u8, expected, buf);

    // Test reader
    const parsed = try unittest.TestAllTypesReader.init(buf);

    // Verify optional fields
    try std.testing.expectEqual(@as(i32, -100), parsed.getOptionalInt32());
    try std.testing.expectEqual(@as(i64, -101), parsed.getOptionalInt64());
    try std.testing.expectEqual(@as(i32, -102), parsed.getOptionalSint32());
    try std.testing.expectEqual(@as(i64, -103), parsed.getOptionalSint64());
    try std.testing.expectEqual(@as(i32, -104), parsed.getOptionalSfixed32());
    try std.testing.expectEqual(@as(i64, -105), parsed.getOptionalSfixed64());
    try std.testing.expectEqual(@as(f32, -105), parsed.getOptionalFloat());
    try std.testing.expectEqual(@as(f64, -106), parsed.getOptionalDouble());

    // Verify repeated fields
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedInt32Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i32, -200), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i32, -300), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedInt64Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i64, -201), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i64, -301), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSint32Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i32, -202), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i32, -302), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSint64Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i64, -203), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i64, -303), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSfixed32Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i32, -204), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i32, -304), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSfixed64Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i64, -205), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i64, -305), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedFloatNext()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(f32, -205), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(f32, -305), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedDoubleNext()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(f64, -206), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(f64, -306), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }
}

test "complex read" {
    const expected = &[_]u8{ 8, 101, 16, 102, 24, 103, 32, 104, 40, 210, 1, 48, 212, 1, 61, 107, 0, 0, 0, 65, 108, 0, 0, 0, 0, 0, 0, 0, 77, 109, 0, 0, 0, 81, 110, 0, 0, 0, 0, 0, 0, 0, 93, 0, 0, 222, 66, 97, 0, 0, 0, 0, 0, 0, 92, 64, 104, 1, 114, 3, 49, 49, 53, 122, 3, 49, 49, 54, 146, 1, 2, 8, 118, 154, 1, 2, 8, 119, 162, 1, 2, 8, 120, 168, 1, 3, 176, 1, 6, 184, 1, 9, 194, 1, 3, 49, 50, 52, 202, 1, 3, 49, 50, 53, 210, 1, 2, 8, 126, 218, 1, 2, 8, 127, 226, 1, 3, 8, 128, 1, 250, 1, 4, 201, 1, 173, 2, 130, 2, 4, 202, 1, 174, 2, 138, 2, 4, 203, 1, 175, 2, 146, 2, 4, 204, 1, 176, 2, 154, 2, 4, 154, 3, 226, 4, 162, 2, 4, 156, 3, 228, 4, 170, 2, 8, 207, 0, 0, 0, 51, 1, 0, 0, 178, 2, 16, 208, 0, 0, 0, 0, 0, 0, 0, 52, 1, 0, 0, 0, 0, 0, 0, 186, 2, 8, 209, 0, 0, 0, 53, 1, 0, 0, 194, 2, 16, 210, 0, 0, 0, 0, 0, 0, 0, 54, 1, 0, 0, 0, 0, 0, 0, 202, 2, 8, 0, 0, 83, 67, 0, 128, 155, 67, 210, 2, 16, 0, 0, 0, 0, 0, 128, 106, 64, 0, 0, 0, 0, 0, 128, 115, 64, 218, 2, 2, 1, 0, 226, 2, 3, 50, 49, 53, 226, 2, 3, 51, 49, 53, 234, 2, 3, 50, 49, 54, 234, 2, 3, 51, 49, 54, 130, 3, 3, 8, 218, 1, 130, 3, 3, 8, 190, 2, 138, 3, 3, 8, 219, 1, 138, 3, 3, 8, 191, 2, 146, 3, 3, 8, 220, 1, 146, 3, 3, 8, 192, 2, 154, 3, 2, 2, 3, 162, 3, 2, 5, 6, 170, 3, 2, 8, 9, 178, 3, 3, 50, 50, 52, 178, 3, 3, 51, 50, 52, 186, 3, 3, 50, 50, 53, 186, 3, 3, 51, 50, 53, 202, 3, 3, 8, 227, 1, 202, 3, 3, 8, 199, 2, 232, 3, 145, 3, 240, 3, 146, 3, 248, 3, 147, 3, 128, 4, 148, 3, 136, 4, 170, 6, 144, 4, 172, 6, 157, 4, 151, 1, 0, 0, 161, 4, 152, 1, 0, 0, 0, 0, 0, 0, 173, 4, 153, 1, 0, 0, 177, 4, 154, 1, 0, 0, 0, 0, 0, 0, 189, 4, 0, 128, 205, 67, 193, 4, 0, 0, 0, 0, 0, 192, 121, 64, 200, 4, 0, 210, 4, 3, 52, 49, 53, 218, 4, 3, 52, 49, 54, 136, 5, 1, 144, 5, 4, 152, 5, 7, 162, 5, 3, 52, 50, 52, 170, 5, 3, 52, 50, 53, 248, 6, 217, 4 };
    const msg = try unittest.TestAllTypesReader.init(expected);

    // Test scalar fields
    try std.testing.expectEqual(@as(i32, 101), msg.getOptionalInt32());
    try std.testing.expectEqual(@as(i64, 102), msg.getOptionalInt64());
    try std.testing.expectEqual(@as(u32, 103), msg.getOptionalUint32());
    try std.testing.expectEqual(@as(u64, 104), msg.getOptionalUint64());
    try std.testing.expectEqual(@as(i32, 105), msg.getOptionalSint32());
    try std.testing.expectEqual(@as(i64, 106), msg.getOptionalSint64());
    try std.testing.expectEqual(@as(u32, 107), msg.getOptionalFixed32());
    try std.testing.expectEqual(@as(u64, 108), msg.getOptionalFixed64());
    try std.testing.expectEqual(@as(i32, 109), msg.getOptionalSfixed32());
    try std.testing.expectEqual(@as(i64, 110), msg.getOptionalSfixed64());
    try std.testing.expectEqual(@as(f32, 111), msg.getOptionalFloat());
    try std.testing.expectEqual(@as(f64, 112), msg.getOptionalDouble());
    try std.testing.expectEqual(true, msg.getOptionalBool());
    try std.testing.expectEqualStrings("115", msg.getOptionalString());
    try std.testing.expectEqualStrings("116", msg.getOptionalBytes());

    // Test nested message
    const nested = try msg.getOptionalNestedMessage();
    try std.testing.expectEqual(@as(i32, 118), nested.getBb());

    // Test foreign message
    const foreign = try msg.getOptionalForeignMessage();
    try std.testing.expectEqual(@as(i32, 119), foreign.getC());

    // Test import message
    const import_msg = try msg.getOptionalImportMessage();
    try std.testing.expectEqual(@as(i32, 120), import_msg.getD());

    // Test repeated fields
    {
        var count: usize = 0;
        var msg_copy = msg;
        while (try msg_copy.repeatedInt32Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i32, 201), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i32, 301), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    // Test enums
    try std.testing.expectEqual(unittest.TestAllTypes.NestedEnum.BAZ, msg.getOptionalNestedEnum());
    try std.testing.expectEqual(unittest.ForeignEnum.FOREIGN_BAZ, msg.getOptionalForeignEnum());
    try std.testing.expectEqual(unittest_import.ImportEnum.IMPORT_BAZ, msg.getOptionalImportEnum());

    // Test string pieces and cords
    try std.testing.expectEqualStrings("124", msg.getOptionalStringPiece());
    try std.testing.expectEqualStrings("125", msg.getOptionalCord());

    // Test defaults
    try std.testing.expectEqual(@as(i32, 401), msg.getDefaultInt32());
    try std.testing.expectEqual(@as(i64, 402), msg.getDefaultInt64());
    try std.testing.expectEqual(@as(u32, 403), msg.getDefaultUint32());
    try std.testing.expectEqual(@as(u64, 404), msg.getDefaultUint64());
    try std.testing.expectEqual(false, msg.getDefaultBool());
    try std.testing.expectEqualStrings("415", msg.getDefaultString());
    try std.testing.expectEqualStrings("416", msg.getDefaultBytes());

    // Test oneof field
    try std.testing.expectEqual(@as(u32, 601), msg.getOneofUint32());
}

test "complex write" {
    const expected = &[_]u8{ 8, 101, 16, 102, 24, 103, 32, 104, 40, 210, 1, 48, 212, 1, 61, 107, 0, 0, 0, 65, 108, 0, 0, 0, 0, 0, 0, 0, 77, 109, 0, 0, 0, 81, 110, 0, 0, 0, 0, 0, 0, 0, 93, 0, 0, 222, 66, 97, 0, 0, 0, 0, 0, 0, 92, 64, 104, 1, 114, 3, 49, 49, 53, 122, 3, 49, 49, 54, 146, 1, 2, 8, 118, 154, 1, 2, 8, 119, 162, 1, 2, 8, 120, 168, 1, 3, 176, 1, 6, 184, 1, 9, 194, 1, 3, 49, 50, 52, 202, 1, 3, 49, 50, 53, 210, 1, 2, 8, 126, 218, 1, 2, 8, 127, 226, 1, 3, 8, 128, 1, 250, 1, 4, 201, 1, 173, 2, 130, 2, 4, 202, 1, 174, 2, 138, 2, 4, 203, 1, 175, 2, 146, 2, 4, 204, 1, 176, 2, 154, 2, 4, 154, 3, 226, 4, 162, 2, 4, 156, 3, 228, 4, 170, 2, 8, 207, 0, 0, 0, 51, 1, 0, 0, 178, 2, 16, 208, 0, 0, 0, 0, 0, 0, 0, 52, 1, 0, 0, 0, 0, 0, 0, 186, 2, 8, 209, 0, 0, 0, 53, 1, 0, 0, 194, 2, 16, 210, 0, 0, 0, 0, 0, 0, 0, 54, 1, 0, 0, 0, 0, 0, 0, 202, 2, 8, 0, 0, 83, 67, 0, 128, 155, 67, 210, 2, 16, 0, 0, 0, 0, 0, 128, 106, 64, 0, 0, 0, 0, 0, 128, 115, 64, 218, 2, 2, 1, 0, 226, 2, 3, 50, 49, 53, 226, 2, 3, 51, 49, 53, 234, 2, 3, 50, 49, 54, 234, 2, 3, 51, 49, 54, 130, 3, 3, 8, 218, 1, 130, 3, 3, 8, 190, 2, 138, 3, 3, 8, 219, 1, 138, 3, 3, 8, 191, 2, 146, 3, 3, 8, 220, 1, 146, 3, 3, 8, 192, 2, 154, 3, 2, 2, 3, 162, 3, 2, 5, 6, 170, 3, 2, 8, 9, 178, 3, 3, 50, 50, 52, 178, 3, 3, 51, 50, 52, 186, 3, 3, 50, 50, 53, 186, 3, 3, 51, 50, 53, 202, 3, 3, 8, 227, 1, 202, 3, 3, 8, 199, 2, 232, 3, 145, 3, 240, 3, 146, 3, 248, 3, 147, 3, 128, 4, 148, 3, 136, 4, 170, 6, 144, 4, 172, 6, 157, 4, 151, 1, 0, 0, 161, 4, 152, 1, 0, 0, 0, 0, 0, 0, 173, 4, 153, 1, 0, 0, 177, 4, 154, 1, 0, 0, 0, 0, 0, 0, 189, 4, 0, 128, 205, 67, 193, 4, 0, 0, 0, 0, 0, 192, 121, 64, 200, 4, 0, 210, 4, 3, 52, 49, 53, 218, 4, 3, 52, 49, 54, 136, 5, 1, 144, 5, 4, 152, 5, 7, 162, 5, 3, 52, 50, 52, 170, 5, 3, 52, 50, 53, 248, 6, 217, 4 };
    const allocator = std.testing.allocator;

    const msg = unittest.TestAllTypes{
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

    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    try std.testing.expectEqualSlices(u8, expected, buf);
}

test "nil list" {
    const expected = &[_]u8{ 202, 3, 0, 202, 3, 2, 8, 1, 202, 3, 0, 232, 3, 0, 240, 3, 0, 248, 3, 0, 128, 4, 0, 136, 4, 0, 144, 4, 0, 157, 4, 0, 0, 0, 0, 161, 4, 0, 0, 0, 0, 0, 0, 0, 0, 173, 4, 0, 0, 0, 0, 177, 4, 0, 0, 0, 0, 0, 0, 0, 0, 189, 4, 0, 0, 0, 0, 193, 4, 0, 0, 0, 0, 0, 0, 0, 0, 200, 4, 0, 210, 4, 0, 218, 4, 0, 136, 5, 0, 144, 5, 0, 152, 5, 0, 162, 5, 0, 170, 5, 0 };
    const allocator = std.testing.allocator;

    const msg = unittest.TestAllTypes{
        .repeated_lazy_message = &[_]?unittest.TestAllTypes.NestedMessage{
            null,
            unittest.TestAllTypes.NestedMessage{
                .bb = 1,
            },
            null,
        },
    };

    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    try std.testing.expectEqualSlices(u8, expected, buf);
}

test "map parsing" {
    const allocator = std.testing.allocator;

    const content = @embedFile("binaries/map_test");
    var data = try map_test.TestMapReader.init(content);

    // Test int32 to int32 map
    {
        var map = std.AutoHashMap(i32, i32).init(allocator);
        defer map.deinit();
        while (try data.nextInt32ToInt32Field()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqual(@as(i32, 101), map.get(100) orelse unreachable);
        try std.testing.expectEqual(@as(i32, 201), map.get(200) orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test int32 to string map
    {
        var map = std.AutoHashMap(i32, []const u8).init(allocator);
        defer map.deinit();
        while (try data.nextInt32ToStringField()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqualStrings("101", map.get(101) orelse unreachable);
        try std.testing.expectEqualStrings("201", map.get(201) orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test int32 to bytes map
    {
        var map = std.AutoHashMap(i32, []const u8).init(allocator);
        defer map.deinit();
        while (try data.nextInt32ToBytesField()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqualSlices(u8, &[_]u8{102}, map.get(102) orelse unreachable);
        try std.testing.expectEqualSlices(u8, &[_]u8{202}, map.get(202) orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test int32 to enum map
    {
        var map = std.AutoHashMap(i32, map_test.TestMap.EnumValue).init(allocator);
        defer map.deinit();
        while (try data.nextInt32ToEnumField()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqual(map_test.TestMap.EnumValue.FOO, map.get(103) orelse unreachable);
        try std.testing.expectEqual(map_test.TestMap.EnumValue.BAR, map.get(203) orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test string to int32 map
    {
        var map = std.StringHashMap(i32).init(allocator);
        defer map.deinit();
        while (try data.nextStringToInt32Field()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqual(@as(i32, 105), map.get("105") orelse unreachable);
        try std.testing.expectEqual(@as(i32, 205), map.get("205") orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test uint32 to int32 map
    {
        var map = std.AutoHashMap(u32, i32).init(allocator);
        defer map.deinit();
        while (try data.nextUint32ToInt32Field()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqual(@as(i32, 106), map.get(106) orelse unreachable);
        try std.testing.expectEqual(@as(i32, 206), map.get(206) orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test int64 to int32 map
    {
        var map = std.AutoHashMap(i64, i32).init(allocator);
        defer map.deinit();
        while (try data.nextInt64ToInt32Field()) |entry| {
            try map.put(entry.key, entry.value);
        }
        try std.testing.expectEqual(@as(i32, 107), map.get(107) orelse unreachable);
        try std.testing.expectEqual(@as(i32, 207), map.get(207) orelse unreachable);
    }

    // Reset reader for next map
    data = try map_test.TestMapReader.init(content);

    // Test int32 to message map
    {
        var found_104 = false;
        var found_204 = false;
        while (try data.nextInt32ToMessageField()) |entry| {
            if (entry.key == 104) {
                try std.testing.expectEqual(@as(i32, 104), entry.value.getValue());
                found_104 = true;
            } else if (entry.key == 204) {
                try std.testing.expectEqual(@as(i32, 204), entry.value.getValue());
                found_204 = true;
            }
        }
        try std.testing.expect(found_104);
        try std.testing.expect(found_204);
    }
}

test "golden message" {
    const content = @embedFile("binaries/golden_message");
    const parsed = try unittest.TestAllTypesReader.init(content);

    // Check scalar fields
    try std.testing.expectEqual(@as(i32, 101), parsed.getOptionalInt32());
    try std.testing.expectEqual(@as(i64, 102), parsed.getOptionalInt64());
    try std.testing.expectEqual(@as(u32, 103), parsed.getOptionalUint32());
    try std.testing.expectEqual(@as(u64, 104), parsed.getOptionalUint64());
    try std.testing.expectEqual(@as(i32, 105), parsed.getOptionalSint32());
    try std.testing.expectEqual(@as(i64, 106), parsed.getOptionalSint64());
    try std.testing.expectEqual(@as(u32, 107), parsed.getOptionalFixed32());
    try std.testing.expectEqual(@as(u64, 108), parsed.getOptionalFixed64());
    try std.testing.expectEqual(@as(i32, 109), parsed.getOptionalSfixed32());
    try std.testing.expectEqual(@as(i64, 110), parsed.getOptionalSfixed64());
    try std.testing.expectEqual(@as(f32, 111), parsed.getOptionalFloat());
    try std.testing.expectEqual(@as(f64, 112), parsed.getOptionalDouble());
    try std.testing.expectEqual(true, parsed.getOptionalBool());
    try std.testing.expectEqualStrings("115", parsed.getOptionalString());
    try std.testing.expectEqualStrings("116", parsed.getOptionalBytes());

    // Test nested messages
    {
        const nested = try parsed.getOptionalNestedMessage();
        try std.testing.expectEqual(@as(i32, 118), nested.getBb());
    }

    {
        const foreign = try parsed.getOptionalForeignMessage();
        try std.testing.expectEqual(@as(i32, 119), foreign.getC());
    }

    {
        const import_msg = try parsed.getOptionalImportMessage();
        try std.testing.expectEqual(@as(i32, 120), import_msg.getD());
    }

    {
        const public_import = try parsed.getOptionalPublicImportMessage();
        try std.testing.expectEqual(@as(i32, 126), public_import.getE());
    }

    {
        const lazy = try parsed.getOptionalLazyMessage();
        try std.testing.expectEqual(@as(i32, 127), lazy.getBb());
    }

    {
        const unverified = try parsed.getOptionalUnverifiedLazyMessage();
        try std.testing.expectEqual(@as(i32, 128), unverified.getBb());
    }

    // Test enums
    try std.testing.expectEqual(unittest.TestAllTypes.NestedEnum.BAZ, parsed.getOptionalNestedEnum());
    try std.testing.expectEqual(unittest.ForeignEnum.FOREIGN_BAZ, parsed.getOptionalForeignEnum());
    try std.testing.expectEqual(unittest_import.ImportEnum.IMPORT_BAZ, parsed.getOptionalImportEnum());

    // Test string pieces and cords
    try std.testing.expectEqualStrings("124", parsed.getOptionalStringPiece());
    try std.testing.expectEqualStrings("125", parsed.getOptionalCord());

    // Test repeated fields
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedInt32Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i32, 201), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i32, 301), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedInt64Next()) |value| {
            if (count == 0) {
                try std.testing.expectEqual(@as(i64, 202), value);
            } else if (count == 1) {
                try std.testing.expectEqual(@as(i64, 302), value);
            }
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }

    // Test oneof fields
    try std.testing.expectEqual(@as(u32, 601), parsed.getOneofUint32());

    {
        const msg = try parsed.getOneofNestedMessage();
        try std.testing.expectEqual(@as(i32, 602), msg.getBb());
    }

    try std.testing.expectEqualStrings("603", parsed.getOneofString());
    try std.testing.expectEqualStrings("604", parsed.getOneofBytes());
}

test "repeated types - marshal and parse" {
    const allocator = std.testing.allocator;

    // Create a test message with all repeated types filled
    const msg = unittest.TestAllTypes{
        // Basic numeric types
        .repeated_int32 = &[_]i32{ -42, 0, 42 },
        .repeated_int64 = &[_]i64{ -9223372036854775808, 0, 9223372036854775807 },
        .repeated_uint32 = &[_]u32{ 0, 42, 4294967295 },
        .repeated_uint64 = &[_]u64{ 0, 42, 18446744073709551615 },

        // Signed variants
        .repeated_sint32 = &[_]i32{ -2147483648, 0, 2147483647 },
        .repeated_sint64 = &[_]i64{ -9223372036854775808, 0, 9223372036854775807 },

        // Fixed width types
        .repeated_fixed32 = &[_]u32{ 0, 42, 4294967295 },
        .repeated_fixed64 = &[_]u64{ 0, 42, 18446744073709551615 },
        .repeated_sfixed32 = &[_]i32{ -2147483648, 0, 2147483647 },
        .repeated_sfixed64 = &[_]i64{ -9223372036854775808, 0, 9223372036854775807 },

        // Floating point types
        .repeated_float = &[_]f32{ -3.4028235e+38, 0, 3.4028235e+38 },
        .repeated_double = &[_]f64{ -1.7976931348623157e+308, 0, 1.7976931348623157e+308 },

        // Bool type
        .repeated_bool = &[_]bool{ true, false, true },

        // String and bytes
        .repeated_string = &[_]?[]const u8{ "hello", "", "world" },
        .repeated_bytes = &[_]?[]const u8{ "bytes1", "", "bytes2" },

        // Message types
        .repeated_nested_message = &[_]?unittest.TestAllTypes.NestedMessage{
            unittest.TestAllTypes.NestedMessage{ .bb = 1 },
            unittest.TestAllTypes.NestedMessage{ .bb = 2 },
            unittest.TestAllTypes.NestedMessage{ .bb = 3 },
        },

        // Enum types
        .repeated_nested_enum = &[_]unittest.TestAllTypes.NestedEnum{
            unittest.TestAllTypes.NestedEnum.FOO,
            unittest.TestAllTypes.NestedEnum.BAR,
            unittest.TestAllTypes.NestedEnum.BAZ,
        },

        // Special string types
        .repeated_string_piece = &[_]?[]const u8{ "piece1", "", "piece2" },
        .repeated_cord = &[_]?[]const u8{ "cord1", "", "cord2" },
    };

    // encode the message
    const buf = try msg.encode(allocator);
    defer allocator.free(buf);

    // Parse the encoded message
    const parsed = try unittest.TestAllTypesReader.init(buf);

    // Test basic numeric types
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedInt32Next()) |value| {
            try std.testing.expectEqual(msg.repeated_int32.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_int32.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedInt64Next()) |value| {
            try std.testing.expectEqual(msg.repeated_int64.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_int64.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedUint32Next()) |value| {
            try std.testing.expectEqual(msg.repeated_uint32.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_uint32.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedUint64Next()) |value| {
            try std.testing.expectEqual(msg.repeated_uint64.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_uint64.?.len, count);
    }

    // Test signed variants
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSint32Next()) |value| {
            try std.testing.expectEqual(msg.repeated_sint32.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_sint32.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSint64Next()) |value| {
            try std.testing.expectEqual(msg.repeated_sint64.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_sint64.?.len, count);
    }

    // Test fixed width types
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedFixed32Next()) |value| {
            try std.testing.expectEqual(msg.repeated_fixed32.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_fixed32.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedFixed64Next()) |value| {
            try std.testing.expectEqual(msg.repeated_fixed64.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_fixed64.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSfixed32Next()) |value| {
            try std.testing.expectEqual(msg.repeated_sfixed32.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_sfixed32.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedSfixed64Next()) |value| {
            try std.testing.expectEqual(msg.repeated_sfixed64.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_sfixed64.?.len, count);
    }

    // Test floating point types
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedFloatNext()) |value| {
            try std.testing.expectEqual(msg.repeated_float.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_float.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedDoubleNext()) |value| {
            try std.testing.expectEqual(msg.repeated_double.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_double.?.len, count);
    }

    // Test bool type
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedBoolNext()) |value| {
            try std.testing.expectEqual(msg.repeated_bool.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_bool.?.len, count);
    }

    // Test string and bytes
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (parsed_copy.repeatedStringNext()) |value| {
            try std.testing.expectEqualStrings(msg.repeated_string.?[count].?, value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_string.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (parsed_copy.repeatedBytesNext()) |value| {
            try std.testing.expectEqualStrings(msg.repeated_bytes.?[count].?, value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_bytes.?.len, count);
    }

    // Test nested messages
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (parsed_copy.repeatedNestedMessageNext()) |value| {
            try std.testing.expectEqual(msg.repeated_nested_message.?[count].?.bb, value.getBb());
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_nested_message.?.len, count);
    }

    // Test enum types
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (try parsed_copy.repeatedNestedEnumNext()) |value| {
            try std.testing.expectEqual(msg.repeated_nested_enum.?[count], value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_nested_enum.?.len, count);
    }

    // Test special string types
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (parsed_copy.repeatedStringPieceNext()) |value| {
            try std.testing.expectEqualStrings(msg.repeated_string_piece.?[count].?, value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_string_piece.?.len, count);
    }
    {
        var count: usize = 0;
        var parsed_copy = parsed;
        while (parsed_copy.repeatedCordNext()) |value| {
            try std.testing.expectEqualStrings(msg.repeated_cord.?[count].?, value);
            count += 1;
        }
        try std.testing.expectEqual(msg.repeated_cord.?.len, count);
    }
}
