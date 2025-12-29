//! This module handles the generation of Zig code for Protocol Buffer enum fields.
//! It provides functionality to create reader and writer methods for enum fields,
//! handle default values, and manage wire format encoding.
//! Enums are serialized as int32 values in the Protocol Buffer wire format.

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

/// Represents a Protocol Buffer enum field in Zig, managing both reading and writing
/// of the field along with wire format details.
pub const ZigEnumField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Field properties
    target_type: FieldType, // Type information from protobuf
    resolvedEnum: ?[]const u8 = null, // Fully qualified enum type name in Zig
    custom_default: ?[]const u8, // Optional default enum value name

    // Generated names for field access
    writer_field_name: []const u8, // Name in the writer struct
    reader_field_name: []const u8, // Internal name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in the protocol

    /// Initialize a new ZigEnumField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_type: FieldType,
        field_opts: ?std.ArrayList(Option),
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigEnumField {
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
                    custom_default = try allocator.dupe(u8, opt.value);
                    break;
                }
            }
        }

        return ZigEnumField{
            .allocator = allocator,
            .target_type = field_type,
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

    /// Set the resolved enum type name after type resolution phase
    pub fn resolve(self: *ZigEnumField, resolvedEnum: []const u8) !void {
        self.resolvedEnum = try self.allocator.dupe(u8, resolvedEnum);
    }

    /// Clean up allocated memory
    pub fn deinit(self: *ZigEnumField) void {
        if (self.resolvedEnum) |e| {
            self.allocator.free(e);
        }
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
    pub fn createWireConst(self: *const ZigEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration with default value of 0
    pub fn createWriterStructField(self: *const ZigEnumField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: {s} = @enumFromInt(0),", .{ self.writer_field_name, self.resolvedEnum.? });
    }

    /// Generate size calculation code for serialization
    pub fn createSizeCheck(self: *const ZigEnumField) ![]const u8 {
        if (self.custom_default) |d| {
            // When default value exists, only include size if value differs from default
            const full_default = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.resolvedEnum.?, ".", d });
            defer self.allocator.free(full_default);
            return std.fmt.allocPrint(self.allocator, "if (self.{s} != {s}) {{ res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeI32(@intFromEnum(self.{s})); }}", .{ self.writer_field_name, full_default, self.wire_const_full_name, self.writer_field_name });
        } else {
            // Without default, include size if value is not 0
            return std.fmt.allocPrint(self.allocator, "if (@intFromEnum(self.{s}) != 0) {{ res += gremlin.sizes.sizeWireNumber({s}) + gremlin.sizes.sizeI32(@intFromEnum(self.{s})); }}", .{ self.writer_field_name, self.wire_const_full_name, self.writer_field_name });
        }
    }

    /// Generate serialization code
    pub fn createWriter(self: *const ZigEnumField) ![]const u8 {
        if (self.custom_default) |d| {
            // Write value only if it differs from default
            const full_default = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.resolvedEnum.?, ".", d });
            defer self.allocator.free(full_default);
            return std.fmt.allocPrint(self.allocator, "if (self.{s} != {s}) {{ target.appendInt32({s}, @intFromEnum(self.{s})); }}", .{ self.writer_field_name, full_default, self.wire_const_full_name, self.writer_field_name });
        } else {
            // Write value only if it's not 0
            return std.fmt.allocPrint(self.allocator, "if (@intFromEnum(self.{s}) != 0) {{ target.appendInt32({s}, @intFromEnum(self.{s})); }}", .{ self.writer_field_name, self.wire_const_full_name, self.writer_field_name });
        }
    }

    /// Generate reader struct field declaration with default value
    pub fn createReaderStructField(self: *const ZigEnumField) ![]const u8 {
        if (self.custom_default) |d| {
            const full_default = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.resolvedEnum.?, ".", d });
            defer self.allocator.free(full_default);
            return std.fmt.allocPrint(self.allocator, "{s}: {s} = {s},", .{ self.reader_field_name, self.resolvedEnum.?, full_default });
        } else {
            return std.fmt.allocPrint(self.allocator, "{s}: {s} = @enumFromInt(0),", .{ self.reader_field_name, self.resolvedEnum.? });
        }
    }

    /// Generate deserialization case statement
    pub fn createReaderCase(self: *const ZigEnumField) ![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            \\{s} => {{
            \\  const result = try buf.readInt32(offset);
            \\  offset += result.size;
            \\  res.{s} = @enumFromInt(result.value);
            \\}},
        ,
            .{ self.wire_const_full_name, self.reader_field_name },
        );
    }

    /// Generate getter method for the field
    pub fn createReaderMethod(self: *const ZigEnumField) ![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "pub inline fn {s}(self: *const {s}) {s} {{ return self.{s}; }}",
            .{ self.reader_method_name, self.reader_struct_name, self.resolvedEnum.?, self.reader_field_name },
        );
    }

    /// Indicates whether the reader needs an allocator (it doesn't for enums)
    pub fn readerNeedsAllocator(_: *const ZigEnumField) bool {
        return false;
    }
};

test "basic enum field" {
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("TestEnum enum_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigEnumField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type,
        f.options,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    try zig_field.resolve("messages.TestEnum");
    defer zig_field.deinit();

    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const ENUM_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("enum_field: messages.TestEnum = @enumFromInt(0),", writer_field_code);

    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings("if (@intFromEnum(self.enum_field) != 0) { res += gremlin.sizes.sizeWireNumber(TestWire.ENUM_FIELD_WIRE) + gremlin.sizes.sizeI32(@intFromEnum(self.enum_field)); }", size_check_code);

    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings("if (@intFromEnum(self.enum_field) != 0) { target.appendInt32(TestWire.ENUM_FIELD_WIRE, @intFromEnum(self.enum_field)); }", writer_code);

    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_enum_field: messages.TestEnum = @enumFromInt(0),", reader_field_code);

    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.ENUM_FIELD_WIRE => {
        \\  const result = try buf.readInt32(offset);
        \\  offset += result.size;
        \\  res._enum_field = @enumFromInt(result.value);
        \\},
    , reader_case_code);

    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings("pub inline fn getEnumField(self: *const TestReader) messages.TestEnum { return self._enum_field; }", reader_method_code);
}

test "enum field with default" {
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("TestEnum enum_field = 1 [default = OTHER];");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 0);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigEnumField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type,
        f.options,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    try zig_field.resolve("messages.TestEnum");
    defer zig_field.deinit();

    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const ENUM_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("enum_field: messages.TestEnum = @enumFromInt(0),", writer_field_code);

    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings("if (self.enum_field != messages.TestEnum.OTHER) { res += gremlin.sizes.sizeWireNumber(TestWire.ENUM_FIELD_WIRE) + gremlin.sizes.sizeI32(@intFromEnum(self.enum_field)); }", size_check_code);

    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings("if (self.enum_field != messages.TestEnum.OTHER) { target.appendInt32(TestWire.ENUM_FIELD_WIRE, @intFromEnum(self.enum_field)); }", writer_code);

    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_enum_field: messages.TestEnum = messages.TestEnum.OTHER,", reader_field_code);

    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.ENUM_FIELD_WIRE => {
        \\  const result = try buf.readInt32(offset);
        \\  offset += result.size;
        \\  res._enum_field = @enumFromInt(result.value);
        \\},
    , reader_case_code);

    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings("pub inline fn getEnumField(self: *const TestReader) messages.TestEnum { return self._enum_field; }", reader_method_code);
}
