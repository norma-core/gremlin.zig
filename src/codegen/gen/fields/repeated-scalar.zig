//! This module handles the generation of Zig code for repeated scalar fields in Protocol Buffers.
//! Repeated scalar fields can appear zero or more times in a message and support packing optimization.
//! When packed, multiple scalar values are encoded together in a length-delimited field.
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
const scalar = @import("scalar.zig");

/// Represents a repeated scalar field in Protocol Buffers.
/// Handles both packed and unpacked encoding formats, with specialized
/// reader implementation to support both formats transparently.
pub const ZigRepeatableScalarField = struct {
    allocator: std.mem.Allocator,

    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    zig_type: []const u8,
    sizeFunc_name: []const u8,
    write_func_name: []const u8,
    read_func_name: []const u8,

    writer_field_name: []const u8,
    reader_offset_field_name: []const u8,
    reader_last_offset_field_name: []const u8,
    reader_packed_field_name: []const u8,
    reader_next_method_name: []const u8,

    wire_const_full_name: []const u8,
    wire_const_name: []const u8,
    wire_index: i32,

    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_type: []const u8,
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigRepeatableScalarField {
        const name = try naming.structFieldName(allocator, field_name, names);

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

        return ZigRepeatableScalarField{
            .allocator = allocator,

            .zig_type = scalar.scalarZigType(field_type),
            .sizeFunc_name = scalar.scalarSize(field_type),
            .write_func_name = scalar.scalarWriter(field_type),
            .read_func_name = scalar.scalarReader(field_type),

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

    pub fn deinit(self: *ZigRepeatableScalarField) void {
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_offset_field_name);
        self.allocator.free(self.reader_last_offset_field_name);
        self.allocator.free(self.reader_packed_field_name);
        self.allocator.free(self.reader_next_method_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);
    }

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration
    pub fn createWriterStructField(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: ?[]const {s} = null,", .{ self.writer_field_name, self.zig_type });
    }

    /// Generate size calculation code for serialization.
    /// Handles special cases for empty arrays, single values, and packed encoding.
    pub fn createSizeCheck(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    if (arr.len == 0) {{
            \\    }} else if (arr.len == 1) {{
            \\        res += gremlin.sizes.sizeWireNumber({s}) + {s}(arr[0]);
            \\    }} else {{
            \\        var packed_size: usize = 0;
            \\        for (arr) |v| {{
            \\            packed_size += {s}(v);
            \\        }}
            \\        res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeUsize(packed_size) + packed_size;
            \\    }}
            \\}}
        , .{
            self.writer_field_name,
            self.wire_const_full_name,
            self.sizeFunc_name,
            self.sizeFunc_name,
            self.wire_const_full_name,
        });
    }

    /// Generate serialization code.
    /// Uses packed encoding for multiple values and optimized single-value encoding.
    pub fn createWriter(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    if (arr.len == 0) {{
            \\    }} else if (arr.len == 1) {{
            \\        target.{s}({s}, arr[0]);
            \\    }} else {{
            \\        var packed_size: usize = 0;
            \\        for (arr) |v| {{
            \\            packed_size += {s}(v);
            \\        }}
            \\        target.appendBytesTag({s}, packed_size);
            \\        for (arr) |v| {{
            \\            target.{s}WithoutTag(v);
            \\        }}
            \\    }}
            \\}}
        , .{
            self.writer_field_name,
            self.write_func_name,
            self.wire_const_full_name,
            self.sizeFunc_name,
            self.wire_const_full_name,
            self.write_func_name,
        });
    }

    pub fn createReaderStructField(self: *const ZigRepeatableScalarField) ![]const u8 {
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

    pub fn createReaderCase(self: *const ZigRepeatableScalarField) ![]const u8 {
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
            \\        const result = try buf.{s}(offset);
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
            self.read_func_name,
            self.reader_last_offset_field_name,
        });
    }

    /// Generate getter method that processes stored offsets.
    /// Handles both packed and unpacked formats transparently.
    pub fn createReaderMethod(self: *const ZigRepeatableScalarField) ![]const u8 {
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
            \\        const value_result = try self.buf.{s}(current_offset);
            \\        self.{s} = current_offset + value_result.size;
            \\
            \\        if (self.{s}.? >= self.{s}.?) {{
            \\            self.{s} = null;
            \\        }}
            \\
            \\        return value_result.value;
            \\    }} else {{
            \\        const value_result = try self.buf.{s}(current_offset);
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
            \\        return value_result.value;
            \\    }}
            \\}}
        , .{
            self.reader_next_method_name,  self.reader_struct_name,       self.zig_type,
            self.reader_offset_field_name, self.reader_offset_field_name, self.reader_last_offset_field_name,
            self.reader_offset_field_name, self.reader_packed_field_name, self.read_func_name,
            self.reader_offset_field_name, self.reader_offset_field_name, self.reader_last_offset_field_name,
            self.reader_offset_field_name, self.read_func_name,           self.reader_last_offset_field_name,
            self.reader_offset_field_name, self.wire_const_full_name,     self.reader_offset_field_name,
            self.reader_offset_field_name,
        });
    }
};

test "basic repeatable scalar field" {
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("repeated int32 number_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigRepeatableScalarField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type.src,
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
    try std.testing.expectEqualStrings("const NUMBER_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    // Test writer field
    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("number_field: ?[]const i32 = null,", writer_field_code);

    // Test size check
    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.number_field) |arr| {
        \\    if (arr.len == 0) {
        \\    } else if (arr.len == 1) {
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.NUMBER_FIELD_WIRE) + gremlin.sizes.sizeI32(arr[0]);
        \\    } else {
        \\        var packed_size: usize = 0;
        \\        for (arr) |v| {
        \\            packed_size += gremlin.sizes.sizeI32(v);
        \\        }
        \\        res += gremlin.sizes.sizeWireNumber(TestWire.NUMBER_FIELD_WIRE) + gremlin.sizes.sizeUsize(packed_size) + packed_size;
        \\    }
        \\}
    , size_check_code);

    // Test writer
    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.number_field) |arr| {
        \\    if (arr.len == 0) {
        \\    } else if (arr.len == 1) {
        \\        target.appendInt32(TestWire.NUMBER_FIELD_WIRE, arr[0]);
        \\    } else {
        \\        var packed_size: usize = 0;
        \\        for (arr) |v| {
        \\            packed_size += gremlin.sizes.sizeI32(v);
        \\        }
        \\        target.appendBytesTag(TestWire.NUMBER_FIELD_WIRE, packed_size);
        \\        for (arr) |v| {
        \\            target.appendInt32WithoutTag(v);
        \\        }
        \\    }
        \\}
    , writer_code);

    // Test reader field
    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings(
        \\_number_field_offset: ?usize = null,
        \\_number_field_last_offset: ?usize = null,
        \\_number_field_packed: bool = false,
    , reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.NUMBER_FIELD_WIRE => {
        \\    if (res._number_field_offset == null) {
        \\        res._number_field_offset = offset;
        \\    }
        \\    if (tag.wire == gremlin.ProtoWireType.bytes) {
        \\        res._number_field_packed = true;
        \\        const length_result = try buf.readVarInt(offset);
        \\        res._number_field_last_offset = offset + length_result.size + @as(usize, @intCast(length_result.value));
        \\        offset = res._number_field_last_offset.?;
        \\    } else {
        \\        const result = try buf.readInt32(offset);
        \\        offset += result.size;
        \\        res._number_field_last_offset = offset;
        \\    }
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub fn numberFieldNext(self: *TestReader) gremlin.Error!?i32 {
        \\    if (self._number_field_offset == null) return null;
        \\
        \\    const current_offset = self._number_field_offset.?;
        \\    if (current_offset >= self._number_field_last_offset.?) {
        \\        self._number_field_offset = null;
        \\        return null;
        \\    }
        \\
        \\    if (self._number_field_packed) {
        \\        const value_result = try self.buf.readInt32(current_offset);
        \\        self._number_field_offset = current_offset + value_result.size;
        \\
        \\        if (self._number_field_offset.? >= self._number_field_last_offset.?) {
        \\            self._number_field_offset = null;
        \\        }
        \\
        \\        return value_result.value;
        \\    } else {
        \\        const value_result = try self.buf.readInt32(current_offset);
        \\        const next_offset = current_offset + value_result.size;
        \\
        \\        if (next_offset >= self._number_field_last_offset.? or !self.buf.hasNext(next_offset, 0)) {
        \\            self._number_field_offset = null;
        \\        } else {
        \\            const next_tag = try self.buf.readTagAt(next_offset);
        \\            if (next_tag.number == TestWire.NUMBER_FIELD_WIRE) {
        \\                self._number_field_offset = next_offset + next_tag.size;
        \\            } else {
        \\                self._number_field_offset = null;
        \\            }
        \\        }
        \\
        \\        return value_result.value;
        \\    }
        \\}
    , reader_method_code);
}
