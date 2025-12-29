//! This module handles the generation of Zig code for repeated message fields in Protocol Buffers.
//! Repeated message fields can appear zero or more times in a message. Each message is serialized
//! as a length-delimited field. The module supports separate reader/writer types for efficient
//! memory management and lazy message parsing.

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
const fields = @import("../../../parser/main.zig").fields;
const FieldType = @import("../../../parser/main.zig").FieldType;

/// Represents a repeated message field in Protocol Buffers.
/// Handles serialization and deserialization of repeated nested messages,
/// with support for null values and lazy parsing.
pub const ZigRepeatableMessageField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Field properties
    target_type: FieldType, // Type information from protobuf
    resolved_writer_type: ?[]const u8 = null, // Full name of writer message type
    resolved_reader_type: ?[]const u8 = null, // Full name of reader message type

    // Generated names for field access
    writer_field_name: []const u8, // Name in writer struct
    reader_field_name: []const u8, // Name for stored buffers
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in protocol

    /// Initialize a new ZigRepeatableMessageField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_type: FieldType,
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigRepeatableMessageField {
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

        return ZigRepeatableMessageField{
            .allocator = allocator,
            .target_type = field_type,
            .writer_field_name = name,
            .reader_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_bufs" }),
            .reader_method_name = readerMethodName,
            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .wire_index = field_index,
            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    /// Set the resolved message type names after type resolution phase
    pub fn resolve(self: *ZigRepeatableMessageField, resolved_writer_type: []const u8, resolved_reader_type: []const u8) !void {
        if (self.resolved_writer_type) |w| {
            self.allocator.free(w);
        }
        if (self.resolved_reader_type) |r| {
            self.allocator.free(r);
        }
        self.resolved_writer_type = try self.allocator.dupe(u8, resolved_writer_type);
        self.resolved_reader_type = try self.allocator.dupe(u8, resolved_reader_type);
    }

    /// Clean up allocated memory
    pub fn deinit(self: *ZigRepeatableMessageField) void {
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
    pub fn createWireConst(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration.
    /// Uses double optional to support explicit null values in the array.
    pub fn createWriterStructField(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?[]const ?{s} = null,", .{ self.writer_field_name, self.resolved_writer_type.? });
    }

    /// Generate size calculation code for serialization.
    /// Each message requires wire number, length prefix, and its own serialized size.
    pub fn createSizeCheck(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    for (arr) |maybe_v| {{
            \\        res += gremlin.sizes.sizeWireNumber({s});
            \\        if (maybe_v) |v| {{
            \\            const size = v.calcProtobufSize();
            \\            res += gremlin.sizes.sizeUsize(size) + size;
            \\        }} else {{
            \\            res += gremlin.sizes.sizeUsize(0);
            \\        }}
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name });
    }

    /// Generate serialization code.
    /// Handles both present messages and explicit nulls in the array.
    pub fn createWriter(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    for (arr) |maybe_v| {{
            \\        if (maybe_v) |v| {{
            \\            const size = v.calcProtobufSize();
            \\            target.appendBytesTag({s}, size);
            \\            v.encodeTo(target);
            \\        }} else {{
            \\            target.appendBytesTag({s}, 0);
            \\        }}
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name, self.wire_const_full_name });
    }

    /// Generate reader struct field declaration.
    /// Uses ArrayList to store raw message buffers until access.
    pub fn createReaderStructField(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?std.ArrayList([]const u8) = null,", .{self.reader_field_name});
    }

    /// Generate deserialization case statement.
    /// Collects raw message buffers for later parsing.
    pub fn createReaderCase(self: *const ZigRepeatableMessageField) ![]const u8 {
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

    /// Generate getter method that parses raw buffers into message instances.
    /// Implements lazy parsing - messages are only deserialized when accessed.
    pub fn createReaderMethod(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}, allocator: std.mem.Allocator) gremlin.Error![]{s} {{
            \\    if (self.{s}) |bufs| {{
            \\        var result = try std.ArrayList({s}).initCapacity(allocator, bufs.items.len);
            \\        for (bufs.items) |buf| {{
            \\            try result.append(try {s}.init(allocator, buf));
            \\        }}
            \\        return result.toOwnedSlice();
            \\    }}
            \\    return &[_]{s}{{}};
            \\}}
        , .{
            self.reader_method_name,
            self.reader_struct_name,
            self.resolved_reader_type.?,
            self.reader_field_name,
            self.resolved_reader_type.?,
            self.resolved_reader_type.?,
            self.resolved_reader_type.?,
        });
    }

    /// Generate cleanup code for reader's buffer storage
    pub fn createReaderDeinit(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    arr.deinit();
            \\}}
        , .{self.reader_field_name});
    }

    /// Indicates whether the reader needs an allocator (always true for message arrays)
    pub fn readerNeedsAllocator(_: *const ZigRepeatableMessageField) bool {
        return true;
    }
};

test "basic repeatable message field" {
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("repeated SubMessage messages = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigRepeatableMessageField.init(
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

    // Test wire constant
    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const MESSAGES_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    // Test writer field
    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("messages: ?[]const ?messages.SubMessage = null,", writer_field_code);

    // Test size check
    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.messages) |arr| {
        \\    for (arr) |maybe_v| {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.MESSAGES_WIRE);
        \\        if (maybe_v) |v| {
        \\            const size = v.calcProtobufSize();
        \\            res += gremlin.sizes.sizeUsize(size) + size;
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
        \\if (self.messages) |arr| {
        \\    for (arr) |maybe_v| {
        \\        if (maybe_v) |v| {
        \\            const size = v.calcProtobufSize();
        \\            target.appendBytesTag(TestWire.MESSAGES_WIRE, size);
        \\            v.encodeTo(target);
        \\        } else {
        \\            target.appendBytesTag(TestWire.MESSAGES_WIRE, 0);
        \\        }
        \\    }
        \\}
    , writer_code);

    // Test reader field
    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_messages_bufs: ?std.ArrayList([]const u8) = null,", reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.MESSAGES_WIRE => {
        \\    const result = try buf.readBytes(offset);
        \\    offset += result.size;
        \\    if (res._messages_bufs == null) {
        \\        res._messages_bufs = std.ArrayList([]const u8).init(allocator);
        \\    }
        \\    try res._messages_bufs.?.append(result.value);
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub fn getMessages(self: *const TestReader, allocator: std.mem.Allocator) gremlin.Error![]messages.SubMessageReader {
        \\    if (self._messages_bufs) |bufs| {
        \\        var result = try std.ArrayList(messages.SubMessageReader).initCapacity(allocator, bufs.items.len);
        \\        for (bufs.items) |buf| {
        \\            try result.append(try messages.SubMessageReader.init(allocator, buf));
        \\        }
        \\        return result.toOwnedSlice();
        \\    }
        \\    return &[_]messages.SubMessageReader{};
        \\}
    , reader_method_code);

    // Test deinit
    const deinit_code = try zig_field.createReaderDeinit();
    defer std.testing.allocator.free(deinit_code);
    try std.testing.expectEqualStrings(
        \\if (self._messages_bufs) |arr| {
        \\    arr.deinit();
        \\}
    , deinit_code);
}
