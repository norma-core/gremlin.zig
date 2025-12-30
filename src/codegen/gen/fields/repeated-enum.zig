//! This module handles the generation of Zig code for repeated enum fields in Protocol Buffers.
//! Repeated enum fields can appear zero or more times in a message and support packing optimization.
//! When packed, multiple enum values are encoded together in a single length-delimited field.
//! The module supports both packed and unpacked representations for backward compatibility.

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
const fields = @import("../../../parser/main.zig").fields;
const FieldType = @import("../../../parser/main.zig").FieldType;
const Option = @import("../../../parser/main.zig").Option;

pub const ZigRepeatableEnumField = struct {
    allocator: std.mem.Allocator,

    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    target_type: FieldType,
    resolved_enum: ?[]const u8 = null,

    writer_field_name: []const u8,
    reader_offset_field_name: []const u8,
    reader_last_offset_field_name: []const u8,
    reader_packed_field_name: []const u8,
    reader_next_method_name: []const u8,

    wire_const_full_name: []const u8,
    wire_const_name: []const u8,
    wire_index: i32,

    /// Initialize a new ZigRepeatableEnumField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_type: FieldType,
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigRepeatableEnumField {
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

        const reader_next_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field_name, "_next" });
        defer allocator.free(reader_next_prefixed);
        const readerNextMethodName = try naming.structMethodName(allocator, reader_next_prefixed, names);

        return ZigRepeatableEnumField{
            .allocator = allocator,
            .target_type = field_type,
            .writer_field_name = name,
            .reader_offset_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_offset" }),
            .reader_last_offset_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_last_offset" }),
            .reader_packed_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_packed" }),
            .reader_next_method_name = readerNextMethodName,
            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .wire_index = field_index,
            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    /// Set the resolved enum type name after type resolution phase
    pub fn resolve(self: *ZigRepeatableEnumField, resolvedEnum: []const u8) !void {
        if (self.resolved_enum) |e| {
            self.allocator.free(e);
        }
        self.resolved_enum = try self.allocator.dupe(u8, resolvedEnum);
    }

    pub fn deinit(self: *ZigRepeatableEnumField) void {
        if (self.resolved_enum) |e| {
            self.allocator.free(e);
        }
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_offset_field_name);
        self.allocator.free(self.reader_last_offset_field_name);
        self.allocator.free(self.reader_packed_field_name);
        self.allocator.free(self.reader_next_method_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);
    }

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration
    pub fn createWriterStructField(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?[]const {s} = null,", .{ self.writer_field_name, self.resolved_enum.? });
    }

    /// Generate size calculation code for serialization.
    /// Handles special cases for empty arrays, single values, and packed encoding.
    pub fn createSizeCheck(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    if (arr.len == 0) {{
            \\    }} else if (arr.len == 1) {{
            \\        res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeI32(@intFromEnum(arr[0]));
            \\    }} else {{
            \\        var packed_size: usize = 0;
            \\        for (arr) |v| {{
            \\            packed_size += gremlin.sizes.sizeI32(@intFromEnum(v));
            \\        }}
            \\        res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeUsize(packed_size) + packed_size;
            \\    }}
            \\}}
        , .{
            self.writer_field_name,
            self.wire_const_full_name,
            self.wire_const_full_name,
        });
    }

    /// Generate serialization code.
    /// Uses packed encoding for multiple values for efficiency.
    pub fn createWriter(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    if (arr.len == 0) {{
            \\    }} else if (arr.len == 1) {{
            \\        target.appendInt32({s}, @intFromEnum(arr[0]));
            \\    }} else {{
            \\        var packed_size: usize = 0;
            \\        for (arr) |v| {{
            \\            packed_size += gremlin.sizes.sizeI32(@intFromEnum(v));
            \\        }}
            \\        target.appendBytesTag({s}, packed_size);
            \\        for (arr) |v| {{
            \\            target.appendInt32WithoutTag(@intFromEnum(v));
            \\        }}
            \\    }}
            \\}}
        , .{
            self.writer_field_name,
            self.wire_const_full_name,
            self.wire_const_full_name,
        });
    }

    pub fn createReaderStructField(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s}: ?usize = null,
            \\{s}: ?usize = null,
            \\{s}: bool = false,
        , .{
            self.reader_offset_field_name,
            self.reader_last_offset_field_name,
            self.reader_packed_field_name,
        });
    }

    /// Generate deserialization case statement.
    /// Stores offset and wire type information for later processing.
    pub fn createReaderCase(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\    if (res.{s} == null) {{
            \\        res.{s} = offset;
            \\    }}
            \\    if (tag.wire == gremlin.ProtoWireType.bytes) {{
            \\        res.{s} = true;
            \\        const length_result = try buf.readVarInt(offset);
            \\        res.{s} = offset + length_result.size + @as(usize, @intCast(length_result.value));
            \\        offset = res.{s}.?;
            \\    }} else {{
            \\        const result = try buf.readInt32(offset);
            \\        offset += result.size;
            \\        res.{s} = offset;
            \\    }}
            \\}},
        , .{
            self.wire_const_full_name,
            self.reader_offset_field_name,
            self.reader_offset_field_name,
            self.reader_packed_field_name,
            self.reader_last_offset_field_name,
            self.reader_last_offset_field_name,
            self.reader_last_offset_field_name,
        });
    }

    pub fn createReaderMethod(self: *const ZigRepeatableEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *{s}) gremlin.Error!?{s} {{
            \\    if (self.{s} == null) return null;
            \\
            \\    const current_offset = self.{s}.?;
            \\    if (current_offset >= self.{s}.?) {{
            \\        self.{s} = null;
            \\        return null;
            \\    }}
            \\
            \\    if (self.{s}) {{
            \\        const value_result = try self.buf.readInt32(current_offset);
            \\        self.{s} = current_offset + value_result.size;
            \\
            \\        if (self.{s}.? >= self.{s}.?) {{
            \\            self.{s} = null;
            \\        }}
            \\
            \\        return @enumFromInt(value_result.value);
            \\    }} else {{
            \\        const value_result = try self.buf.readInt32(current_offset);
            \\        const next_offset = current_offset + value_result.size;
            \\
            \\        if (next_offset >= self.{s}.? or !self.buf.hasNext(next_offset, 0)) {{
            \\            self.{s} = null;
            \\        }} else {{
            \\            const next_tag = try self.buf.readTagAt(next_offset);
            \\            if (next_tag.number == {s}) {{
            \\                self.{s} = next_offset + next_tag.size;
            \\            }} else {{
            \\                self.{s} = null;
            \\            }}
            \\        }}
            \\
            \\        return @enumFromInt(value_result.value);
            \\    }}
            \\}}
        , .{
            self.reader_next_method_name,       self.reader_struct_name,            self.resolved_enum.?,
            self.reader_offset_field_name,      self.reader_offset_field_name,      self.reader_last_offset_field_name,
            self.reader_offset_field_name,      self.reader_packed_field_name,      self.reader_offset_field_name,
            self.reader_offset_field_name,      self.reader_last_offset_field_name, self.reader_offset_field_name,
            self.reader_last_offset_field_name, self.reader_offset_field_name,      self.wire_const_full_name,
            self.reader_offset_field_name,      self.reader_offset_field_name,
        });
    }
};

test "basic repeatable enum field" {
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("repeated TestEnum enum_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigRepeatableEnumField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    try zig_field.resolve("messages.TestEnum");
    defer zig_field.deinit();

    // Test wire constant
    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const ENUM_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    // Test writer field
    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("enum_field: ?[]const messages.TestEnum = null,", writer_field_code);

    // Test size check
    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.enum_field) |arr| {
        \\    if (arr.len == 0) {
        \\    } else if (arr.len == 1) {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.ENUM_FIELD_WIRE) + gremlin.sizes.sizeI32(@intFromEnum(arr[0]));
        \\    } else {
        \\        var packed_size: usize = 0;
        \\        for (arr) |v| {
        \\            packed_size += gremlin.sizes.sizeI32(@intFromEnum(v));
        \\        }
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.ENUM_FIELD_WIRE) + gremlin.sizes.sizeUsize(packed_size) + packed_size;
        \\    }
        \\}
    , size_check_code);

    // Test writer
    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.enum_field) |arr| {
        \\    if (arr.len == 0) {
        \\    } else if (arr.len == 1) {
        \\        target.appendInt32(TestWire.ENUM_FIELD_WIRE, @intFromEnum(arr[0]));
        \\    } else {
        \\        var packed_size: usize = 0;
        \\        for (arr) |v| {
        \\            packed_size += gremlin.sizes.sizeI32(@intFromEnum(v));
        \\        }
        \\        target.appendBytesTag(TestWire.ENUM_FIELD_WIRE, packed_size);
        \\        for (arr) |v| {
        \\            target.appendInt32WithoutTag(@intFromEnum(v));
        \\        }
        \\    }
        \\}
    , writer_code);

    // Test reader field
    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings(
        \\_enum_field_offset: ?usize = null,
        \\_enum_field_last_offset: ?usize = null,
        \\_enum_field_packed: bool = false,
    , reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.ENUM_FIELD_WIRE => {
        \\    if (res._enum_field_offset == null) {
        \\        res._enum_field_offset = offset;
        \\    }
        \\    if (tag.wire == gremlin.ProtoWireType.bytes) {
        \\        res._enum_field_packed = true;
        \\        const length_result = try buf.readVarInt(offset);
        \\        res._enum_field_last_offset = offset + length_result.size + @as(usize, @intCast(length_result.value));
        \\        offset = res._enum_field_last_offset.?;
        \\    } else {
        \\        const result = try buf.readInt32(offset);
        \\        offset += result.size;
        \\        res._enum_field_last_offset = offset;
        \\    }
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub fn enumFieldNext(self: *TestReader) gremlin.Error!?messages.TestEnum {
        \\    if (self._enum_field_offset == null) return null;
        \\
        \\    const current_offset = self._enum_field_offset.?;
        \\    if (current_offset >= self._enum_field_last_offset.?) {
        \\        self._enum_field_offset = null;
        \\        return null;
        \\    }
        \\
        \\    if (self._enum_field_packed) {
        \\        const value_result = try self.buf.readInt32(current_offset);
        \\        self._enum_field_offset = current_offset + value_result.size;
        \\
        \\        if (self._enum_field_offset.? >= self._enum_field_last_offset.?) {
        \\            self._enum_field_offset = null;
        \\        }
        \\
        \\        return @enumFromInt(value_result.value);
        \\    } else {
        \\        const value_result = try self.buf.readInt32(current_offset);
        \\        const next_offset = current_offset + value_result.size;
        \\
        \\        if (next_offset >= self._enum_field_last_offset.? or !self.buf.hasNext(next_offset, 0)) {
        \\            self._enum_field_offset = null;
        \\        } else {
        \\            const next_tag = try self.buf.readTagAt(next_offset);
        \\            if (next_tag.number == TestWire.ENUM_FIELD_WIRE) {
        \\                self._enum_field_offset = next_offset + next_tag.size;
        \\            } else {
        \\                self._enum_field_offset = null;
        \\            }
        \\        }
        \\
        \\        return @enumFromInt(value_result.value);
        \\    }
        \\}
    , reader_method_code);
}
