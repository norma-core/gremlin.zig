//! This module handles the generation of Zig code for Protocol Buffer scalar fields.
//! It provides mappings between Protocol Buffer scalar types and their Zig equivalents,
//! along with support for default values and specialized encoding/decoding functions.
//! Scalar fields include numeric types (integers and floats) and booleans.

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

/// Maps Protocol Buffer scalar types to their corresponding Zig types
pub fn scalarZigType(proto_type: []const u8) []const u8 {
    if (std.mem.eql(u8, proto_type, "bool")) return "bool";
    if (std.mem.eql(u8, proto_type, "float")) return "f32";
    if (std.mem.eql(u8, proto_type, "double")) return "f64";
    if (std.mem.eql(u8, proto_type, "int32")) return "i32";
    if (std.mem.eql(u8, proto_type, "int64")) return "i64";
    if (std.mem.eql(u8, proto_type, "uint32")) return "u32";
    if (std.mem.eql(u8, proto_type, "uint64")) return "u64";
    if (std.mem.eql(u8, proto_type, "sint32")) return "i32";
    if (std.mem.eql(u8, proto_type, "sint64")) return "i64";
    if (std.mem.eql(u8, proto_type, "fixed32")) return "u32";
    if (std.mem.eql(u8, proto_type, "fixed64")) return "u64";
    if (std.mem.eql(u8, proto_type, "sfixed32")) return "i32";
    if (std.mem.eql(u8, proto_type, "sfixed64")) return "i64";

    unreachable;
}

/// Returns the default value for each Protocol Buffer scalar type
pub fn scalarDefaultValue(proto_type: []const u8) []const u8 {
    if (std.mem.eql(u8, proto_type, "bool")) return "false";
    if (std.mem.eql(u8, proto_type, "float")) return "0.0";
    if (std.mem.eql(u8, proto_type, "double")) return "0.0";
    if (std.mem.eql(u8, proto_type, "int32")) return "0";
    if (std.mem.eql(u8, proto_type, "int64")) return "0";
    if (std.mem.eql(u8, proto_type, "uint32")) return "0";
    if (std.mem.eql(u8, proto_type, "uint64")) return "0";
    if (std.mem.eql(u8, proto_type, "sint32")) return "0";
    if (std.mem.eql(u8, proto_type, "sint64")) return "0";
    if (std.mem.eql(u8, proto_type, "fixed32")) return "0";
    if (std.mem.eql(u8, proto_type, "fixed64")) return "0";
    if (std.mem.eql(u8, proto_type, "sfixed32")) return "0";
    if (std.mem.eql(u8, proto_type, "sfixed64")) return "0";

    unreachable;
}

/// Returns the size calculation function name for each Protocol Buffer scalar type
pub fn scalarSize(f_type: []const u8) []const u8 {
    const scalar_sizes = .{
        .{ "bool", "gremlin.sizes.sizeBool" },
        .{ "float", "gremlin.sizes.sizeFloat" },
        .{ "double", "gremlin.sizes.sizeDouble" },
        .{ "int32", "gremlin.sizes.sizeI32" },
        .{ "int64", "gremlin.sizes.sizeI64" },
        .{ "uint32", "gremlin.sizes.sizeU32" },
        .{ "uint64", "gremlin.sizes.sizeU64" },
        .{ "sint32", "gremlin.sizes.sizeSI32" },
        .{ "sint64", "gremlin.sizes.sizeSI64" },
        .{ "fixed32", "gremlin.sizes.sizeFixed32" },
        .{ "fixed64", "gremlin.sizes.sizeFixed64" },
        .{ "sfixed32", "gremlin.sizes.sizeSFixed32" },
        .{ "sfixed64", "gremlin.sizes.sizeSFixed64" },
    };

    inline for (scalar_sizes) |pair| {
        if (std.mem.eql(u8, f_type, pair[0])) {
            return pair[1];
        }
    }
    unreachable;
}

/// Returns the serialization function name for each Protocol Buffer scalar type
pub fn scalarWriter(f_type: []const u8) []const u8 {
    const scalar_writers = .{
        .{ "bool", "appendBool" },
        .{ "float", "appendFloat32" },
        .{ "double", "appendFloat64" },
        .{ "int32", "appendInt32" },
        .{ "int64", "appendInt64" },
        .{ "uint32", "appendUint32" },
        .{ "uint64", "appendUint64" },
        .{ "sint32", "appendSint32" },
        .{ "sint64", "appendSint64" },
        .{ "fixed32", "appendFixed32" },
        .{ "fixed64", "appendFixed64" },
        .{ "sfixed32", "appendSfixed32" },
        .{ "sfixed64", "appendSfixed64" },
    };

    inline for (scalar_writers) |pair| {
        if (std.mem.eql(u8, f_type, pair[0])) {
            return pair[1];
        }
    }
    unreachable;
}

/// Returns the deserialization function name for each Protocol Buffer scalar type
pub fn scalarReader(f_type: []const u8) []const u8 {
    const scalar_reads = .{
        .{ "bool", "readBool" },
        .{ "float", "readFloat32" },
        .{ "double", "readFloat64" },
        .{ "int32", "readInt32" },
        .{ "int64", "readInt64" },
        .{ "uint32", "readUInt32" },
        .{ "uint64", "readUInt64" },
        .{ "sint32", "readSInt32" },
        .{ "sint64", "readSInt64" },
        .{ "fixed32", "readFixed32" },
        .{ "fixed64", "readFixed64" },
        .{ "sfixed32", "readSFixed32" },
        .{ "sfixed64", "readSFixed64" },
    };

    inline for (scalar_reads) |pair| {
        if (std.mem.eql(u8, f_type, pair[0])) {
            return pair[1];
        }
    }
    unreachable;
}

/// Converts Protocol Buffer scalar default value strings to Zig expressions.
/// Handles special floating point values (inf, -inf, nan).
fn convertScalarDefault(allocator: std.mem.Allocator, value: []const u8, zigType: []const u8) ![]const u8 {
    const lower_cased = try std.ascii.allocLowerString(allocator, value);
    defer allocator.free(lower_cased);

    if (std.mem.eql(u8, lower_cased, "inf")) {
        return try std.mem.concat(allocator, u8, &[_][]const u8{ "std.math.inf(", zigType, ")" });
    }
    if (std.mem.eql(u8, lower_cased, "-inf")) {
        return try std.mem.concat(allocator, u8, &[_][]const u8{ "-std.math.inf(", zigType, ")" });
    }
    if (std.mem.eql(u8, lower_cased, "nan")) {
        return try std.mem.concat(allocator, u8, &[_][]const u8{ "std.math.nan(", zigType, ")" });
    }

    return allocator.dupe(u8, value);
}

/// Represents a Protocol Buffer scalar field in Zig.
/// Handles serialization, deserialization, and default values for scalar types.
pub const ZigScalarField = struct {
    // Memory management
    allocator: std.mem.Allocator,

    // Owned struct
    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    // Type information
    zig_type: []const u8, // Corresponding Zig type
    custom_default: ?[]const u8, // Custom default value if specified
    type_default: []const u8, // Type's standard default value

    // Function names for operations
    sizeFunc_name: []const u8, // Size calculation function
    write_func_name: []const u8, // Serialization function
    read_func_name: []const u8, // Deserialization function

    // Generated names for field access
    writer_field_name: []const u8, // Name in writer struct
    reader_field_name: []const u8, // Name in reader struct
    reader_method_name: []const u8, // Public getter method name

    // Wire format metadata
    wire_const_full_name: []const u8, // Full qualified wire constant name
    wire_const_name: []const u8, // Short wire constant name
    wire_index: i32, // Field number in protocol

    /// Initialize a new ZigScalarField with the given parameters
    pub fn init(
        allocator: std.mem.Allocator,
        field_name: []const u8,
        field_type: []const u8,
        field_opts: ?std.ArrayList(Option),
        field_index: i32,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigScalarField {
        // Generate field names
        const name = try naming.structFieldName(allocator, field_name, names);
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

        // Get Zig type mapping
        const zig_type = scalarZigType(field_type);

        // Process default value if present
        var custom_default: ?[]const u8 = null;
        if (field_opts) |opts| {
            for (opts.items) |*opt| {
                if (std.mem.eql(u8, opt.name, "default")) {
                    custom_default = try convertScalarDefault(allocator, opt.value, zig_type);
                    break;
                }
            }
        }

        return ZigScalarField{
            .allocator = allocator,
            .zig_type = zig_type,
            .type_default = scalarDefaultValue(field_type),
            .custom_default = custom_default,
            .sizeFunc_name = scalarSize(field_type),
            .write_func_name = scalarWriter(field_type),
            .read_func_name = scalarReader(field_type),
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
    pub fn deinit(self: *ZigScalarField) void {
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
    pub fn createWireConst(self: *const ZigScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.wire_index });
    }

    /// Generate writer struct field declaration with appropriate default
    pub fn createWriterStructField(self: *const ZigScalarField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}: {s} = {s},", .{ self.writer_field_name, self.zig_type, self.type_default });
    }

    /// Generate size calculation code.
    /// Only includes field in output if value differs from default.
    pub fn createSizeCheck(self: *const ZigScalarField) ![]const u8 {
        const default_value = if (self.custom_default) |d| d else self.type_default;
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s} != {s}) {{
            \\    res += gremlin.sizes.sizeWireNumber({s}) + {s}(self.{s});
            \\}}
        , .{ self.writer_field_name, default_value, self.wire_const_full_name, self.sizeFunc_name, self.writer_field_name });
    }

    /// Generate serialization code.
    /// Only writes field if value differs from default.
    pub fn createWriter(self: *const ZigScalarField) ![]const u8 {
        const default_value = if (self.custom_default) |d| d else self.type_default;
        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s} != {s}) {{
            \\    target.{s}({s}, self.{s});
            \\}}
        , .{ self.writer_field_name, default_value, self.write_func_name, self.wire_const_full_name, self.writer_field_name });
    }

    /// Generate reader struct field declaration with appropriate default
    pub fn createReaderStructField(self: *const ZigScalarField) ![]const u8 {
        const default_value = if (self.custom_default) |d| d else self.type_default;
        return std.fmt.allocPrint(self.allocator, "{s}: {s} = {s},", .{ self.reader_field_name, self.zig_type, default_value });
    }

    /// Generate deserialization case statement.
    /// Reads scalar value and updates the field directly.
    pub fn createReaderCase(self: *const ZigScalarField) ![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            \\{s} => {{
            \\    const result = try buf.{s}(offset);
            \\    offset += result.size;
            \\    res.{s} = result.value;
            \\}},
        ,
            .{ self.wire_const_full_name, self.read_func_name, self.reader_field_name },
        );
    }

    /// Generate getter method for the field.
    /// Simply returns the stored value as defaults are handled at initialization.
    pub fn createReaderMethod(self: *const ZigScalarField) ![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            \\pub inline fn {s}(self: *const {s}) {s} {{
            \\    return self.{s};
            \\}}
        ,
            .{
                self.reader_method_name,
                self.reader_struct_name,
                self.zig_type,
                self.reader_field_name,
            },
        );
    }
};

test "basic field" {
    const fields = @import("../../../parser/main.zig").fields;
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("uint64 uint_field = 1;");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigScalarField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type.src,
        f.options,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    defer zig_field.deinit();

    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const UINT_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("uint_field: u64 = 0,", writer_field_code);

    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.uint_field != 0) {
        \\    res += gremlin.sizes.sizeWireNumber(TestWire.UINT_FIELD_WIRE) + gremlin.sizes.sizeU64(self.uint_field);
        \\}
    , size_check_code);

    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.uint_field != 0) {
        \\    target.appendUint64(TestWire.UINT_FIELD_WIRE, self.uint_field);
        \\}
    , writer_code);

    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_uint_field: u64 = 0,", reader_field_code);

    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.UINT_FIELD_WIRE => {
        \\    const result = try buf.readUInt64(offset);
        \\    offset += result.size;
        \\    res._uint_field = result.value;
        \\},
    , reader_case_code);

    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub inline fn getUintField(self: *const TestReader) u64 {
        \\    return self._uint_field;
        \\}
    , reader_method_code);
}

test "default field" {
    const fields = @import("../../../parser/main.zig").fields;
    const ScopedName = @import("../../../parser/main.zig").ScopedName;
    const ParserBuffer = @import("../../../parser/main.zig").ParserBuffer;

    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    var buf = ParserBuffer.init("int32 int_field = 1 [default=42];");
    var f = try fields.NormalField.parse(std.testing.allocator, scope, &buf);
    defer f.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 32);
    defer names.deinit(std.testing.allocator);

    var zig_field = try ZigScalarField.init(
        std.testing.allocator,
        f.f_name,
        f.f_type.src,
        f.options,
        f.index,
        "TestWire",
        &names,
        "TestWriter",
        "TestReader",
    );
    defer zig_field.deinit();

    const wire_const_code = try zig_field.createWireConst();
    defer std.testing.allocator.free(wire_const_code);
    try std.testing.expectEqualStrings("const INT_FIELD_WIRE: gremlin.ProtoWireNumber = 1;", wire_const_code);

    const writer_field_code = try zig_field.createWriterStructField();
    defer std.testing.allocator.free(writer_field_code);
    try std.testing.expectEqualStrings("int_field: i32 = 0,", writer_field_code);

    const size_check_code = try zig_field.createSizeCheck();
    defer std.testing.allocator.free(size_check_code);
    try std.testing.expectEqualStrings(
        \\if (self.int_field != 42) {
        \\    res += gremlin.sizes.sizeWireNumber(TestWire.INT_FIELD_WIRE) + gremlin.sizes.sizeI32(self.int_field);
        \\}
    , size_check_code);

    const writer_code = try zig_field.createWriter();
    defer std.testing.allocator.free(writer_code);
    try std.testing.expectEqualStrings(
        \\if (self.int_field != 42) {
        \\    target.appendInt32(TestWire.INT_FIELD_WIRE, self.int_field);
        \\}
    , writer_code);

    const reader_field_code = try zig_field.createReaderStructField();
    defer std.testing.allocator.free(reader_field_code);
    try std.testing.expectEqualStrings("_int_field: i32 = 42,", reader_field_code);

    const reader_case_code = try zig_field.createReaderCase();
    defer std.testing.allocator.free(reader_case_code);
    try std.testing.expectEqualStrings(
        \\TestWire.INT_FIELD_WIRE => {
        \\    const result = try buf.readInt32(offset);
        \\    offset += result.size;
        \\    res._int_field = result.value;
        \\},
    , reader_case_code);

    const reader_method_code = try zig_field.createReaderMethod();
    defer std.testing.allocator.free(reader_method_code);
    try std.testing.expectEqualStrings(
        \\pub inline fn getIntField(self: *const TestReader) i32 {
        \\    return self._int_field;
        \\}
    , reader_method_code);
}
