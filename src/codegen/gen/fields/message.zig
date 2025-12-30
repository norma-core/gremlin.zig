//! This module handles the generation of Zig code for Protocol Buffer message fields.
//! Message fields are nested Protocol Buffer messages that are serialized as length-delimited
//! fields in the wire format. The module provides functionality to create reader and writer
//! methods, handle nested message serialization, and manage wire format encoding.

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
const FieldType = @import("../../../parser/main.zig").FieldType;

/// Represents a Protocol Buffer message field in Zig.
/// Message fields require special handling since they involve nested serialization
/// and separate reader/writer types for efficient memory management.
pub const ZigMessageField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Field properties
    target_type: FieldType, // Type information from protobuf

    // Generated names for field access
    writer_field_name: []const u8, // Name in the writer struct
    reader_field_name: []const u8, // Internal buffer name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in protocol

    // Resolved type information
    resolved_writer_type: ?[]const u8 = null, // Full name of writer message type
    resolved_reader_type: ?[]const u8 = null, // Full name of reader message type

    /// Initialize a new ZigMessageField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_type: FieldType,
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigMessageField {
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

        // Generate reader method name
        const reader_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ "get_", field_name });
        defer allocator.free(reader_prefixed);
        const readerMethodName = try naming.structMethodName(allocator, reader_prefixed, names);

        return ZigMessageField{
            .allocator = allocator,
            .target_type = field_type,
            .writer_field_name = name,
            .reader_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_buf" }),
            .reader_method_name = readerMethodName,
            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .wire_index = field_index,
            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    /// Set the resolved message type names after type resolution phase
    pub fn resolve(self: *ZigMessageField, resolved_writer_type: []const u8, resolved_reader_type: []const u8) !void {
        self.resolved_writer_type = try self.allocator.dupe(u8, resolved_writer_type);
        self.resolved_reader_type = try self.allocator.dupe(u8, resolved_reader_type);
    }

    /// Clean up allocated memory
    pub fn deinit(self: *ZigMessageField) void {
        if (self.resolved_writer_type) |w| {
            self.allocator.free(w);
        }
        if (self.resolved_reader_type) |r| {
            self.allocator.free(r);
        }
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_field_name);
        self.allocator.free(self.reader_method_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);
    }

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration.
    /// Message fields are optional and use their specific writer type.
    pub fn createWriterStructField(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?{s} = null,", .{ self.writer_field_name, self.resolved_writer_type.? });
    }

    /// Generate size calculation code for serialization.
    /// Message fields are length-delimited, requiring size of both the message and the length prefix.
    pub fn createSizeCheck(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |v| {{
            \\    const size = v.calcProtobufSize();
            \\    if (size > 0) {{
            \\        res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeUsize(size) + size;
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name });
    }

    /// Generate serialization code.
    /// Writes the field tag, length prefix, and then recursively serializes the nested message.
    pub fn createWriter(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |v| {{
            \\    const size = v.calcProtobufSize();
            \\    if (size > 0) {{
            \\        target.appendBytesTag({s}, size);
            \\        v.encodeTo(target);
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name });
    }

    /// Generate reader struct field declaration.
    /// Reader stores the raw bytes until lazy deserialization is needed.
    pub fn createReaderStructField(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?[]const u8 = null,", .{self.reader_field_name});
    }

    /// Generate deserialization case statement.
    /// Stores the raw message bytes for later processing.
    pub fn createReaderCase(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\  const result = try buf.readBytes(offset);
            \\  offset += result.size;
            \\  res.{s} = result.value;
            \\}},
        , .{ self.wire_const_full_name, self.reader_field_name });
    }

    /// Generate getter method that creates reader instance from stored bytes.
    /// This implements lazy deserialization - messages are only parsed when accessed.
    pub fn createReaderMethod(self: *const ZigMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}) gremlin.Error!{s} {{
            \\    if (self.{s}) |buf| {{
            \\        return try {s}.init(buf);
            \\    }}
            \\    return try {s}.init(&[_]u8{{}});
            \\}}
        , .{
            self.reader_method_name,
            self.reader_struct_name,
            self.resolved_reader_type.?,
            self.reader_field_name,
            self.resolved_reader_type.?,
            self.resolved_reader_type.?,
        });
    }
};

test "basic message field" {
    const fields = @import("../../../parser/main.zig").fields;
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("SubMessage message_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigMessageField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    try zig_field.resolve("messages.SubMessage", "messages.SubMessageReader");
    defer zig_field.deinit();

    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const MESSAGE_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("message_field: ?messages.SubMessage = null,", writer_field_code);

    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.message_field) |v| {
        \\    const size = v.calcProtobufSize();
        \\    if (size > 0) {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.MESSAGE_FIELD_WIRE) + gremlin.sizes.sizeUsize(size) + size;
        \\    }
        \\}
    , size_check_code);

    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.message_field) |v| {
        \\    const size = v.calcProtobufSize();
        \\    if (size > 0) {
        \\        target.appendBytesTag(TestWire.MESSAGE_FIELD_WIRE, size);
        \\        v.encodeTo(target);
        \\    }
        \\}
    , writer_code);

    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_message_field_buf: ?[]const u8 = null,", reader_field_code);

    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.MESSAGE_FIELD_WIRE => {
        \\  const result = try buf.readBytes(offset);
        \\  offset += result.size;
        \\  res._message_field_buf = result.value;
        \\},
    , reader_case_code);

    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub fn getMessageField(self: *const TestReader) gremlin.Error!messages.SubMessageReader {
        \\    if (self._message_field_buf) |buf| {
        \\        return try messages.SubMessageReader.init(buf);
        \\    }
        \\    return try messages.SubMessageReader.init(&[_]u8{});
        \\}
    , reader_method_code);
}
