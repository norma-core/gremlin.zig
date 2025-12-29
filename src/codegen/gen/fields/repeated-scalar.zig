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
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Scalar type information
    zig_type: []const u8, // Corresponding Zig type for the scalar
    sizeFunc_name: []const u8, // Name of size calculation function
    write_func_name: []const u8, // Name of serialization function
    read_func_name: []const u8, // Name of deserialization function

    // Generated names for field access
    writer_field_name: []const u8, // Name in writer struct
    reader_field_name: []const u8, // Internal name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Reader implementation details
    reader_offsets_name: []const u8, // Name for offset storage array
    reader_wires_name: []const u8, // Name for wire type storage array

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in protocol

    /// Initialize a new ZigRepeatableScalarField with the given parameters
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

        return ZigRepeatableScalarField{
            .allocator = allocator,

            .zig_type = scalar.scalarZigType(field_type),
            .sizeFunc_name = scalar.scalarSize(field_type),
            .write_func_name = scalar.scalarWriter(field_type),
            .read_func_name = scalar.scalarReader(field_type),

            .writer_field_name = name,
            .reader_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name }),
            .reader_method_name = readerMethodName,
            .reader_offsets_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_offsets" }),
            .reader_wires_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_wires" }),

            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .wire_index = field_index,

            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    /// Clean up allocated memory
    pub fn deinit(self: *ZigRepeatableScalarField) void {
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_field_name);
        self.allocator.free(self.reader_method_name);
        self.allocator.free(self.reader_offsets_name);
        self.allocator.free(self.reader_wires_name);
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

    /// Generate reader struct field declaration.
    /// Uses separate arrays for offsets and wire types to support both encoding formats.
    pub fn createReaderStructField(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s}: ?std.ArrayList(usize) = null,
            \\{s}: ?std.ArrayList(gremlin.ProtoWireType) = null,
        , .{
            self.reader_offsets_name,
            self.reader_wires_name,
        });
    }

    /// Generate deserialization case statement.
    /// Stores offset and wire type information for later processing.
    pub fn createReaderCase(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s} => {{
            \\    if (res.{s} == null) {{
            \\        res.{s} = std.ArrayList(usize).init(allocator);
            \\        res.{s} = std.ArrayList(gremlin.ProtoWireType).init(allocator);
            \\    }}
            \\    try res.{s}.?.append(offset);
            \\    try res.{s}.?.append(tag.wire);
            \\    if (tag.wire == gremlin.ProtoWireType.bytes) {{
            \\        const length_result = try buf.readVarInt(offset);
            \\        offset += length_result.size + @as(usize, @intCast(length_result.value));
            \\    }} else {{
            \\        const result = try buf.{s}(offset);
            \\        offset += result.size;
            \\    }}
            \\}},
        , .{
            self.wire_const_full_name,
            self.reader_offsets_name,
            self.reader_offsets_name,
            self.reader_wires_name,
            self.reader_offsets_name,
            self.reader_wires_name,
            self.read_func_name,
        });
    }

    /// Generate getter method that processes stored offsets.
    /// Handles both packed and unpacked formats transparently.
    pub fn createReaderMethod(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}, allocator: std.mem.Allocator) gremlin.Error![]{s} {{
            \\    if (self.{s}) |offsets| {{
            \\        if (offsets.items.len == 0) return &[_]{s}{{}};
            \\
            \\        var result = std.ArrayList({s}).init(allocator);
            \\        errdefer result.deinit();
            \\
            \\        for (offsets.items, self.{s}.?.items) |start_offset, wire_type| {{
            \\            if (wire_type == .bytes) {{
            \\                const length_result = try self.buf.readVarInt(start_offset);
            \\                var offset = start_offset + length_result.size;
            \\                const end_offset = offset + @as(usize, @intCast(length_result.value));
            \\
            \\                while (offset < end_offset) {{
            \\                    const value_result = try self.buf.{s}(offset);
            \\                    try result.append(value_result.value);
            \\                    offset += value_result.size;
            \\                }}
            \\            }} else {{
            \\                const value_result = try self.buf.{s}(start_offset);
            \\                try result.append(value_result.value);
            \\            }}
            \\        }}
            \\        return result.toOwnedSlice();
            \\    }}
            \\    return &[_]{s}{{}};
            \\}}
        , .{
            self.reader_method_name,
            self.reader_struct_name,
            self.zig_type,
            self.reader_offsets_name,
            self.zig_type,
            self.zig_type,
            self.reader_wires_name,
            self.read_func_name,
            self.read_func_name,
            self.zig_type,
        });
    }

    /// Generate cleanup code for reader's temporary storage
    pub fn createReaderDeinit(self: *const ZigRepeatableScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |arr| {{
            \\    arr.deinit();
            \\}}
            \\if (self.{s}) |arr| {{
            \\    arr.deinit();
            \\}}
        , .{
            self.reader_offsets_name,
            self.reader_wires_name,
        });
    }

    /// Indicates whether the reader needs an allocator (always true for arrays)
    pub fn readerNeedsAllocator(_: *const ZigRepeatableScalarField) bool {
        return true;
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
        \\_number_field_offsets: ?std.ArrayList(usize) = null,
        \\_number_field_wires: ?std.ArrayList(gremlin.ProtoWireType) = null,
    , reader_field_code);

    // Test reader case
    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.NUMBER_FIELD_WIRE => {
        \\    if (res._number_field_offsets == null) {
        \\        res._number_field_offsets = std.ArrayList(usize).init(allocator);
        \\        res._number_field_wires = std.ArrayList(gremlin.ProtoWireType).init(allocator);
        \\    }
        \\    try res._number_field_offsets.?.append(offset);
        \\    try res._number_field_wires.?.append(tag.wire);
        \\    if (tag.wire == gremlin.ProtoWireType.bytes) {
        \\        const length_result = try buf.readVarInt(offset);
        \\        offset += length_result.size + @as(usize, @intCast(length_result.value));
        \\    } else {
        \\        const result = try buf.readInt32(offset);
        \\        offset += result.size;
        \\    }
        \\},
    , reader_case_code);

    // Test reader method
    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub fn getNumberField(self: *const TestReader, allocator: std.mem.Allocator) gremlin.Error![]i32 {
        \\    if (self._number_field_offsets) |offsets| {
        \\        if (offsets.items.len == 0) return &[_]i32{};
        \\
        \\        var result = std.ArrayList(i32).init(allocator);
        \\        errdefer result.deinit();
        \\
        \\        for (offsets.items, self._number_field_wires.?.items) |start_offset, wire_type| {
        \\            if (wire_type == .bytes) {
        \\                const length_result = try self.buf.readVarInt(start_offset);
        \\                var offset = start_offset + length_result.size;
        \\                const end_offset = offset + @as(usize, @intCast(length_result.value));
        \\
        \\                while (offset < end_offset) {
        \\                    const value_result = try self.buf.readInt32(offset);
        \\                    try result.append(value_result.value);
        \\                    offset += value_result.size;
        \\                }
        \\            } else {
        \\                const value_result = try self.buf.readInt32(start_offset);
        \\                try result.append(value_result.value);
        \\            }
        \\        }
        \\        return result.toOwnedSlice();
        \\    }
        \\    return &[_]i32{};
        \\}
    , reader_method_code);

    // Test deinit
    const deinit_code = try zig_field.createReaderDeinit();
    defer std.testing.allocator.free(deinit_code);
    try std.testing.expectEqualStrings(
        \\if (self._number_field_offsets) |arr| {
        \\    arr.deinit();
        \\}
        \\if (self._number_field_wires) |arr| {
        \\    arr.deinit();
        \\}
    , deinit_code);
}
