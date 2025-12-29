//! Field type parser module for Protocol Buffer definitions.
//! Handles parsing and validation of field types including scalar types,
//! bytes/string types, and message/enum references.

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
// Created by ab, 12.06.2024

const std = @import("std");
const ParserBuffer = @import("buffer.zig").ParserBuffer;
const Error = @import("errors.zig").Error;
const lex = @import("lexems.zig");
const ScopedName = @import("scoped-name.zig").ScopedName;
const Enum = @import("enum.zig").Enum;
const Message = @import("message.zig").Message;
const ProtoFile = @import("file.zig").ProtoFile;

/// List of all valid Protocol Buffer scalar types
pub const scalar_types = [_][]const u8{
    "bool",
    "float",
    "double",
    "int32",
    "int64",
    "uint32",
    "uint64",
    "sint32",
    "sint64",
    "fixed32",
    "fixed64",
    "sfixed32",
    "sfixed64",
};

/// Checks if a type name is a Protocol Buffer scalar type
fn isScalarType(src: []const u8) bool {
    for (scalar_types) |scalar_type| {
        if (std.mem.eql(u8, src, scalar_type)) {
            return true;
        }
    }
    return false;
}

/// Checks if a type name is a bytes or string type
fn isBytesType(src: []const u8) bool {
    return std.mem.eql(u8, src, "bytes") or std.mem.eql(u8, src, "string");
}

/// Represents a parsed Protocol Buffer field type with resolution information.
/// Tracks whether the type is scalar, bytes/string, or a reference to a
/// message/enum type, along with scope and import information.
pub const FieldType = struct {
    /// Allocator for dynamic memory
    allocator: std.mem.Allocator,
    /// Original type name from source
    src: []const u8,
    /// Whether this is a scalar type (int32, float, etc)
    is_scalar: bool,
    /// Whether this is bytes or string type
    is_bytes: bool,
    /// Parsed scoped name for message/enum types
    name: ?ScopedName,

    /// Reference to locally defined enum if this is an enum type
    ref_local_enum: ?*Enum = null,
    /// Reference to locally defined message if this is a message type
    ref_local_message: ?*Message = null,

    /// Reference to imported enum if this is an enum type
    ref_external_enum: ?*Enum = null,
    /// Reference to imported message if this is a message type
    ref_external_message: ?*Message = null,
    /// Reference to import file containing the type
    ref_import: ?*ProtoFile = null,

    /// Current scope for name resolution
    scope: ScopedName,
    /// Reference to file containing the scope
    scope_ref: ?*ProtoFile = null,

    /// Parses a field type from the buffer.
    /// Handles scalar types, bytes/string types, and message/enum references.
    ///
    /// # Arguments
    /// * `allocator` - Allocator for dynamic memory
    /// * `scope` - Current scope for name resolution
    /// * `buf` - Parser buffer containing the type definition
    ///
    /// # Errors
    /// Returns error on invalid syntax or allocation failure
    pub fn parse(allocator: std.mem.Allocator, scope: ScopedName, buf: *ParserBuffer) Error!FieldType {
        const src = try lex.fieldType(buf);
        try buf.skipSpaces();

        const scalar = isScalarType(src);
        const is_bytes = isBytesType(src);
        var name: ?ScopedName = null;
        if (!scalar and !is_bytes) {
            name = try ScopedName.init(allocator, src);
        }

        return FieldType{
            .allocator = allocator,
            .src = src,
            .is_scalar = scalar,
            .is_bytes = is_bytes,
            .name = name,
            .scope = scope,
        };
    }

    /// Creates a deep copy of the FieldType
    pub fn clone(self: *const FieldType) Error!FieldType {
        var name: ?ScopedName = null;
        if (self.name) |*n| {
            name = try n.clone();
        }

        return FieldType{
            .allocator = self.allocator,
            .src = self.src,
            .is_scalar = self.is_scalar,
            .is_bytes = self.is_bytes,
            .name = name,
            .scope = self.scope,
        };
    }

    /// Frees all resources owned by the FieldType
    pub fn deinit(self: *FieldType) void {
        if (self.name) |*name| {
            name.deinit();
        }
    }

    /// Returns whether this type references an enum (local or external)
    pub fn isEnum(self: *const @This()) bool {
        return self.ref_external_enum != null or self.ref_local_enum != null;
    }

    /// Returns whether this type references a message (local or external)
    pub fn isMsg(self: *const @This()) bool {
        return self.ref_external_message != null or self.ref_local_message != null;
    }
};

test "field type parsing - scalar types" {
    var buf = ParserBuffer.init("int32");
    var scope = try ScopedName.init(std.testing.allocator, "test");
    defer scope.deinit();

    var field_type = try FieldType.parse(std.testing.allocator, scope, &buf);
    defer field_type.deinit();

    try std.testing.expect(field_type.is_scalar);
    try std.testing.expect(!field_type.is_bytes);
    try std.testing.expect(field_type.name == null);
}

test "field type parsing - bytes types" {
    var buf = ParserBuffer.init("bytes");
    var scope = try ScopedName.init(std.testing.allocator, "test");
    defer scope.deinit();

    var field_type = try FieldType.parse(std.testing.allocator, scope, &buf);
    defer field_type.deinit();

    try std.testing.expect(!field_type.is_scalar);
    try std.testing.expect(field_type.is_bytes);
    try std.testing.expect(field_type.name == null);
}

test "field type parsing - message types" {
    var buf = ParserBuffer.init("MyMessage");
    var scope = try ScopedName.init(std.testing.allocator, "test");
    defer scope.deinit();

    var field_type = try FieldType.parse(std.testing.allocator, scope, &buf);
    defer field_type.deinit();

    try std.testing.expect(!field_type.is_scalar);
    try std.testing.expect(!field_type.is_bytes);
    try std.testing.expect(field_type.name != null);
}
