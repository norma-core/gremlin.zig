//! This module handles the generation of Zig code for Protocol Buffer bytes and string fields.
//! Both field types are handled similarly as they share the same wire format representation.
//! The module provides functionality to create reader and writer methods, handle defaults,
//! and manage wire format encoding for both bytes and string fields.

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
// Created by ab, 10.11.2024

const std = @import("std");
const naming = @import("naming.zig");
const Option = @import("../../../parser/main.zig").Option;

/// Formats a string literal for use in Zig code, properly escaping special characters
/// and converting to hexadecimal representation where necessary. This is particularly
/// important for handling default values of both string and bytes fields.
///
/// Parameters:
///     allocator: Memory allocator to use for the result
///     str: Input string to format (including quotes)
/// Returns:
///     Formatted string with proper escaping, suitable for use in Zig code
fn formatStringLiteral(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, str.len * 2);
    defer result.deinit(allocator);

    // Remove surrounding quotes from input
    const cropped = str[1 .. str.len - 1];
    try result.appendSlice(allocator, "\"");

    // Process each character, applying appropriate escaping
    for (cropped) |c| {
        switch (c) {
            // Control characters
            0 => try result.appendSlice(allocator, "\\x00"),
            1 => try result.appendSlice(allocator, "\\x01"),
            7 => try result.appendSlice(allocator, "\\a"),
            8 => try result.appendSlice(allocator, "\\b"),
            12 => try result.appendSlice(allocator, "\\f"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            11 => try result.appendSlice(allocator, "\\v"),

            // Special characters that need escaping
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\'' => try result.appendSlice(allocator, "\\'"),
            '"' => try result.appendSlice(allocator, "\\\""),

            // All other characters are converted to hex for consistent representation
            else => try std.fmt.format(result.writer(allocator), "\\x{X:0>2}", .{c}),
        }
    }
    try result.appendSlice(allocator, "\"");

    return result.toOwnedSlice(allocator);
}

/// Represents a Protocol Buffer bytes/string field in Zig, managing both reading and writing
/// of the field along with wire format details. The same structure is used for both bytes
/// and string fields as they share the same underlying representation.
pub const ZigBytesField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Field properties
    custom_default: ?[]const u8, // Optional default value for the field

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Generated names for field access
    writer_field_name: []const u8, // Name in the writer struct
    reader_field_name: []const u8, // Internal name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in the protocol

    /// Initialize a new ZigBytesField with the given parameters.
    /// This handles setup for both bytes and string fields.
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_opts: ?std.ArrayList(Option),
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigBytesField {
        // Generate the field name for the writer struct
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

        // Generate reader method name (get_fieldname)
        const reader_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ "get_", field_name });
        defer allocator.free(reader_prefixed);
        const readerMethodName = try naming.structMethodName(allocator, reader_prefixed, names);

        // Process field options for default value
        var custom_default: ?[]const u8 = null;
        if (field_opts) |opts| {
            for (opts.items) |*opt| {
                if (std.mem.eql(u8, opt.name, "default")) {
                    custom_default = try formatStringLiteral(allocator, opt.value);
                    break;
                }
            }
        }

        return ZigBytesField{
            .allocator = allocator,
            .custom_default = custom_default,
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
    pub fn deinit(self: *ZigBytesField) void {
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_field_name);
        self.allocator.free(self.reader_method_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);

        if (self.custom_default) |d| {
            self.allocator.free(d);
        }
    }

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration
    pub fn createWriterStructField(self: *const ZigBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?[]const u8 = null,", .{self.writer_field_name});
    }

    /// Generate size calculation code for serialization
    pub fn createSizeCheck(self: *const ZigBytesField) ![]const u8 {
        if (self.custom_default) |d| {
            // When default value exists, only include size if value differs from default
            return std.fmt.allocPrint(self.allocator,
                \\if (self.{s}) |v| {{
                \\    if (!std.mem.eql(u8, v, {s})) {{
                \\        res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeUsize(v.len) + v.len;
                \\    }}
                \\}} else {{
                \\    res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeUsize(0);
                \\}}
            , .{ self.writer_field_name, d, self.wire_const_full_name, self.wire_const_full_name });
        } else {
            // Without default, include size if value exists
            return std.fmt.allocPrint(self.allocator,
                \\if (self.{s}) |v| {{
                \\    if (v.len > 0) {{
                \\        res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeUsize(v.len) + v.len;
                \\    }}
                \\}}
            , .{ self.writer_field_name, self.wire_const_full_name });
        }
    }

    /// Generate serialization code
    pub fn createWriter(self: *const ZigBytesField) ![]const u8 {
        if (self.custom_default) |d| {
            // With default value, only write if different from default
            return std.fmt.allocPrint(self.allocator,
                \\if (self.{s}) |v| {{
                \\    if (!std.mem.eql(u8, v, {s})) {{
                \\        target.appendBytes({s}, v);
                \\    }}
                \\}} else {{
                \\    target.appendBytes({s}, "");
                \\}}
            , .{ self.writer_field_name, d, self.wire_const_full_name, self.wire_const_full_name });
        } else {
            // Without default, write if value exists
            return std.fmt.allocPrint(self.allocator,
                \\if (self.{s}) |v| {{
                \\    if (v.len > 0) {{
                \\        target.appendBytes({s}, v);
                \\    }}
                \\}}
            , .{ self.writer_field_name, self.wire_const_full_name });
        }
    }

    /// Generate reader struct field declaration
    pub fn createReaderStructField(self: *const ZigBytesField) ![]const u8 {
        if (self.custom_default) |d| {
            return std.fmt.allocPrint(self.allocator, "{s}: ?[]const u8 = {s},", .{ self.reader_field_name, d });
        } else {
            return std.fmt.allocPrint(self.allocator, "{s}: ?[]const u8 = null,", .{self.reader_field_name});
        }
    }

    /// Generate deserialization case statement
    pub fn createReaderCase(self: *const ZigBytesField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\  const result = try buf.readBytes(offset);
            \\  offset += result.size;
            \\  res.{s} = result.value;
            \\}},
        , .{ self.wire_const_full_name, self.reader_field_name });
    }

    /// Generate getter method for the field
    pub fn createReaderMethod(self: *const ZigBytesField) ![]const u8 {
        if (self.custom_default) |d| {
            return std.fmt.allocPrint(self.allocator, "pub inline fn {s}(self: *const {s}) []const u8 {{ return self.{s} orelse {s}; }}", .{ self.reader_method_name, self.reader_struct_name, self.reader_field_name, d });
        } else {
            return std.fmt.allocPrint(self.allocator, "pub inline fn {s}(self: *const {s}) []const u8 {{ return self.{s} orelse &[_]u8{{}}; }}", .{ self.reader_method_name, self.reader_struct_name, self.reader_field_name });
        }
    }
};

test "basic bytes field" {
    const fields = @import("../../../parser/main.zig").fields;
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("bytes data_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigBytesField.init(
        std.testing.allocator,
        f.f_name,
        f.options,
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

    // Test writer field (optional)
    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("data_field: ?[]const u8 = null,", writer_field_code);

    // Test size check
    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.data_field) |v| {
        \\    if (v.len > 0) {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.DATA_FIELD_WIRE) + gremlin.sizes.sizeUsize(v.len) + v.len;
        \\    }
        \\}
    , size_check_code);

    // Test writer
    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.data_field) |v| {
        \\    if (v.len > 0) {
        \\        target.appendBytes(TestWire.DATA_FIELD_WIRE, v);
        \\    }
        \\}
    , writer_code);

    // Test reader field
    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_data_field: ?[]const u8 = null,", reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.DATA_FIELD_WIRE => {
        \\  const result = try buf.readBytes(offset);
        \\  offset += result.size;
        \\  res._data_field = result.value;
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings("pub inline fn getDataField(self: *const TestReader) []const u8 { return self._data_field orelse &[_]u8{}; }", reader_method_code);
}

test "bytes field with default" {
    const fields = @import("../../../parser/main.zig").fields;
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    // Use explicit string with quotes since it comes from parser this way
    var buf = ParserBuffer.init("bytes data_field = 1 [default=\"hello\"];");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigBytesField.init(
        std.testing.allocator,
        f.f_name,
        f.options,
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

    // Test writer field (optional)
    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("data_field: ?[]const u8 = null,", writer_field_code);

    // Test size check with default handling
    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.data_field) |v| {
        \\    if (!std.mem.eql(u8, v, "\x68\x65\x6C\x6C\x6F")) {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.DATA_FIELD_WIRE) + gremlin.sizes.sizeUsize(v.len) + v.len;
        \\    }
        \\} else {
        \\    res += gremlin.sizes.sizeWireNumber(TestWire.DATA_FIELD_WIRE) + gremlin.sizes.sizeUsize(0);
        \\}
    , size_check_code);

    // Test writer with default handling
    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.data_field) |v| {
        \\    if (!std.mem.eql(u8, v, "\x68\x65\x6C\x6C\x6F")) {
        \\        target.appendBytes(TestWire.DATA_FIELD_WIRE, v);
        \\    }
        \\} else {
        \\    target.appendBytes(TestWire.DATA_FIELD_WIRE, "");
        \\}
    , writer_code);

    // Test reader field
    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_data_field: ?[]const u8 = \"\\x68\\x65\\x6C\\x6C\\x6F\",", reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.DATA_FIELD_WIRE => {
        \\  const result = try buf.readBytes(offset);
        \\  offset += result.size;
        \\  res._data_field = result.value;
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings("pub inline fn getDataField(self: *const TestReader) []const u8 { return self._data_field orelse \"\\x68\\x65\\x6C\\x6C\\x6F\"; }", reader_method_code);
}
