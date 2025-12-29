//! This module handles the generation of Zig code for repeated bytes and string fields
//! in Protocol Buffers. Repeated fields can appear zero or more times in a message.
//! Each value in a repeated bytes/string field is length-delimited in the wire format.
//! The module supports null values in the writer interface while preserving a clean reader API.

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
// Created by ab, 11.11.2024

const std = @import("std");
const naming = @import("naming.zig");
const Option = @import("../../../parser/main.zig").Option;

/// Represents a repeated bytes/string field in Protocol Buffers.
/// Handles both serialization and deserialization of repeated length-delimited fields.
pub const ZigRepeatableBytesField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Generated names for field access
    writer_field_name: []const u8, // Name in writer struct
    reader_field_name: []const u8, // Internal name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in protocol

    /// Initialize a new ZigRepeatableBytesField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigRepeatableBytesField {
        // Generate field name for the writer struct
        const name = try naming.structFieldName(allocator, field_name, names);

        // Generate wire format constant names
        const wirePostfixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field_name, "Wire" });
        defer allocator.free(wirePostfixed);
        const wireConstName = try naming.constName(allocator, wirePostfixed, names);
        const wireName = try std.mem.concat(allocator, u8, &[_][]const u8{
            wire_prefix,
            ".",
            wireConstName,
        });

        // Generate reader method name
        const reader_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ "get_", field_name });
        defer allocator.free(reader_prefixed);
        const readerMethodName = try naming.structMethodName(allocator, reader_prefixed, names);

        return ZigRepeatableBytesField{
            .allocator = allocator,
            .writer_field_name = name,
            .reader_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name }),
            .reader_method_name = readerMethodName,
            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .wire_index = field_index,
            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *ZigRepeatableBytesField) void {
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_field_name);
        self.allocator.free(self.reader_method_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);
    }

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration.
    /// Uses double optional to support explicit null values in the array.
    pub fn createWriterStructField(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?[]const ?[]const u8 = null,", .{self.writer_field_name});
    }

    /// Generate size calculation code for serialization.
    /// Each value requires wire number, length prefix, and content size.
    pub fn createSizeCheck(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    for (arr) |maybe_v| {{
            \\        res += gremlin.sizes.sizeWireNumber({s});
            \\        if (maybe_v) |v| {{
            \\            res += gremlin.sizes.sizeUsize(v.len) + v.len;
            \\        }} else {{
            \\            res += gremlin.sizes.sizeUsize(0);
            \\        }}
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name });
    }

    /// Generate serialization code.
    /// Handles both present values and explicit nulls in the array.
    pub fn createWriter(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    for (arr) |maybe_v| {{
            \\        if (maybe_v) |v| {{
            \\            target.appendBytes({s}, v);
            \\        }} else {{
            \\            target.appendBytesTag({s}, 0);
            \\        }}
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name, self.wire_const_full_name });
    }

    /// Generate reader struct field declaration.
    /// Uses ArrayList to collect values during deserialization.
    pub fn createReaderStructField(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?std.ArrayList([]const u8) = null,", .{self.reader_field_name});
    }

    /// Generate deserialization case statement.
    /// Creates ArrayList on first element and appends subsequent values.
    pub fn createReaderCase(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\    const result = try buf.readBytes(offset);
            \\    offset += result.size;
            \\    if (res.{s} == null) {{
            \\        res.{s} = std.ArrayList([]const u8).init(allocator);
            \\    }}
            \\    try res.{s}.?.append(result.value);
            \\}},
        , .{ self.wire_const_full_name, self.reader_field_name, self.reader_field_name, self.reader_field_name });
    }

    /// Generate getter method that returns the array of values.
    /// Returns empty array if field is not present.
    pub fn createReaderMethod(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}) []const []const u8 {{
            \\    if (self.{s}) |arr| {{
            \\        return arr.items;
            \\    }}
            \\    return &[_][]u8{{}};
            \\}}
        , .{ self.reader_method_name, self.reader_struct_name, self.reader_field_name });
    }

    /// Generate cleanup code for reader's ArrayList
    pub fn createReaderDeinit(self: *const ZigRepeatableBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    arr.deinit();
            \\}}
        , .{self.reader_field_name});
    }

    /// Indicates whether the reader needs an allocator (always true for repeated fields)
    pub fn readerNeedsAllocator(_: *const ZigRepeatableBytesField) bool {
        return true;
    }
};

// Test cases remain unchanged as they provide good coverage
// of both serialization and deserialization, including null handling

test "repeatable bytes field with null values" {
    const fields = @import("../../../parser/main.zig").fields;
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("repeated bytes data_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigRepeatableBytesField.init(
        std.testing.allocator,
        f.f_name,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    defer zig_field.deinit();

    // Test wire constant
    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const DATA_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    // Test writer field
    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("data_field: ?[]const ?[]const u8 = null,", writer_field_code);

    // Test size check
    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.data_field) |arr| {
        \\    for (arr) |maybe_v| {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.DATA_FIELD_WIRE);
        \\        if (maybe_v) |v| {
        \\            res += gremlin.sizes.sizeUsize(v.len) + v.len;
        \\        } else {
        \\            res += gremlin.sizes.sizeUsize(0);
        \\        }
        \\    }
        \\}
    , size_check_code);

    // Test writer
    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.data_field) |arr| {
        \\    for (arr) |maybe_v| {
        \\        if (maybe_v) |v| {
        \\            target.appendBytes(TestWire.DATA_FIELD_WIRE, v);
        \\        } else {
        \\            target.appendBytesTag(TestWire.DATA_FIELD_WIRE, 0);
        \\        }
        \\    }
        \\}
    , writer_code);

    // Test reader field
    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_data_field: ?std.ArrayList([]const u8) = null,", reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.DATA_FIELD_WIRE => {
        \\    const result = try buf.readBytes(offset);
        \\    offset += result.size;
        \\    if (res._data_field == null) {
        \\        res._data_field = std.ArrayList([]const u8).init(allocator);
        \\    }
        \\    try res._data_field.?.append(result.value);
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub fn getDataField(self: *const TestReader) []const []const u8 {
        \\    if (self._data_field) |arr| {
        \\        return arr.items;
        \\    }
        \\    return &[_][]u8{};
        \\}
    , reader_method_code);

    // Test deinit
    const deinit_code = try zig_field.createReaderDeinit();
    defer std.testing.allocator.free(deinit_code);
    try std.testing.expectEqualStrings(
        \\if (self._data_field) |arr| {
        \\    arr.deinit();
        \\}
    , deinit_code);
}
