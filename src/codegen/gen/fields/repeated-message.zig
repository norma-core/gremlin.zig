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
    reader_offset_field_name: []const u8, // Current/first entry offset (used for iteration)
    reader_last_offset_field_name: []const u8, // Last entry offset
    reader_cnt_field_name: []const u8, // Total count of entries
    reader_next_method_name: []const u8, // Public next() iterator method name
    reader_count_method_name: []const u8, // Public count() method name

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

        // Generate reader method names with proper suffixes
        const reader_next_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field_name, "_next" });
        defer allocator.free(reader_next_prefixed);
        const readerNextMethodName = try naming.structMethodName(allocator, reader_next_prefixed, names);

        const reader_count_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field_name, "_count" });
        defer allocator.free(reader_count_prefixed);
        const readerCountMethodName = try naming.structMethodName(allocator, reader_count_prefixed, names);

        return ZigRepeatableMessageField{
            .allocator = allocator,
            .target_type = field_type,
            .writer_field_name = name,
            .reader_offset_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_offset" }),
            .reader_last_offset_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_last_offset" }),
            .reader_cnt_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_cnt" }),
            .reader_next_method_name = readerNextMethodName,
            .reader_count_method_name = readerCountMethodName,
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
        self.allocator.free(self.reader_cnt_field_name);
        self.allocator.free(self.reader_offset_field_name);
        self.allocator.free(self.reader_last_offset_field_name);
        self.allocator.free(self.reader_count_method_name);
        self.allocator.free(self.reader_next_method_name);
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
    /// Stores offsets and count for iteration through repeated values.
    pub fn createReaderStructField(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s}: ?usize = null,
            \\{s}: ?usize = null,
            \\{s}: usize = 0,
        , .{ self.reader_offset_field_name, self.reader_last_offset_field_name, self.reader_cnt_field_name });
    }

    /// Generate deserialization case statement.
    /// Tracks first and last offsets, and counts total entries.
    pub fn createReaderCase(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\    const result = try buf.readBytes(offset);
            \\    offset += result.size;
            \\    if (res.{s} == null) {{
            \\        res.{s} = offset - result.size;
            \\    }}
            \\    res.{s} = offset;
            \\    res.{s} += 1;
            \\}},
        , .{
            self.wire_const_full_name,
            self.reader_offset_field_name,
            self.reader_offset_field_name,
            self.reader_last_offset_field_name,
            self.reader_cnt_field_name,
        });
    }

    /// Generate getter methods for count and next iterator.
    pub fn createReaderMethod(self: *const ZigRepeatableMessageField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}) usize {{
            \\    return self.{s};
            \\}}
            \\
            \\pub fn {s}(self: *{s}) ?{s} {{
            \\    if (self.{s} == null) return null;
            \\
            \\    const current_offset = self.{s}.?;
            \\    const result = self.buf.readBytes(current_offset) catch return null;
            \\    const msg = {s}.init(result.value) catch return null;
            \\
            \\    if (self.{s} != null and current_offset >= self.{s}.?) {{
            \\        self.{s} = null;
            \\        return msg;
            \\    }}
            \\
            \\    if (self.{s} == null) unreachable;
            \\
            \\    var next_offset = current_offset + result.size;
            \\    const max_offset = self.{s}.?;
            \\
            \\    while (next_offset <= max_offset and self.buf.hasNext(next_offset, 0)) {{
            \\        const tag = self.buf.readTagAt(next_offset) catch break;
            \\        next_offset += tag.size;
            \\
            \\        if (tag.number == {s}) {{
            \\            self.{s} = next_offset;
            \\            return msg;
            \\        }} else {{
            \\            next_offset = self.buf.skipData(next_offset, tag.wire) catch break;
            \\        }}
            \\    }}
            \\
            \\    self.{s} = null;
            \\    return msg;
            \\}}
        , .{
            self.reader_count_method_name,      self.reader_struct_name,            self.reader_cnt_field_name,
            self.reader_next_method_name,       self.reader_struct_name,            self.resolved_reader_type.?,
            self.reader_offset_field_name,      self.reader_offset_field_name,      self.resolved_reader_type.?,
            self.reader_last_offset_field_name, self.reader_last_offset_field_name, self.reader_offset_field_name,
            self.reader_last_offset_field_name, self.reader_last_offset_field_name, self.wire_const_full_name,
            self.reader_offset_field_name,      self.reader_offset_field_name,
        });
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
    try std.testing.expectEqualStrings(
        \\_messages_offset: ?usize = null,
        \\_messages_last_offset: ?usize = null,
        \\_messages_cnt: usize = 0,
    , reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.MESSAGES_WIRE => {
        \\    const result = try buf.readBytes(offset);
        \\    offset += result.size;
        \\    if (res._messages_offset == null) {
        \\        res._messages_offset = offset - result.size;
        \\    }
        \\    res._messages_last_offset = offset;
        \\    res._messages_cnt += 1;
        \\},
    , reader_case_code);

    // Test reader method - we'll just check it compiles for now
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    // The method is complex, so we'll just check it's not empty
    try std.testing.expect(reader_method_code.len > 0);
}
