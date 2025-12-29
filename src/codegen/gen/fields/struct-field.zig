//! This module provides a unified interface for handling different types of Protocol Buffer fields
//! in Zig. It acts as a facade over specialized field implementations, handling field type
//! detection and delegation to appropriate handlers. The module supports all Protocol Buffer field
//! types including scalar, bytes, message, enum, repeated fields, and maps.

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
// Created by ab, 12.11.2024

const std = @import("std");
const Message = @import("../../../parser/main.zig").Message;
const fields = @import("../../../parser/main.zig").fields;
const FieldType = @import("../../../parser/main.zig").FieldType;

/// Import all specialized field type implementations
const field_types = struct {
    const ZigScalarField = @import("scalar.zig").ZigScalarField;
    const ZigBytesField = @import("bytes.zig").ZigBytesField;
    const ZigMessageField = @import("message.zig").ZigMessageField;
    const ZigEnumField = @import("enum.zig").ZigEnumField;
    const ZigRepeatableBytesField = @import("repeated-bytes.zig").ZigRepeatableBytesField;
    const ZigRepeatableMessageField = @import("repeated-message.zig").ZigRepeatableMessageField;
    const ZigRepeatableEnumField = @import("repeated-enum.zig").ZigRepeatableEnumField;
    const ZigRepeatableScalarField = @import("repeated-scalar.zig").ZigRepeatableScalarField;
    const ZigMapField = @import("map.zig").ZigMapField;
};

/// Represents a Protocol Buffer field of any type.
/// Uses a tagged union to handle different field implementations while providing
/// a unified interface for code generation.
pub const Field = union(enum) {
    scalar: field_types.ZigScalarField,
    bytes: field_types.ZigBytesField,
    message: field_types.ZigMessageField,
    enumeration: field_types.ZigEnumField,
    repeated_bytes: field_types.ZigRepeatableBytesField,
    repeated_message: field_types.ZigRepeatableMessageField,
    repeated_enum: field_types.ZigRepeatableEnumField,
    repeated_scalar: field_types.ZigRepeatableScalarField,
    map: field_types.ZigMapField,

    /// Creates wire format constant declaration for the field
    pub fn createWireConst(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createWireConst(),
        };
    }

    /// Creates writer struct field declaration
    pub fn createWriterStructField(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createWriterStructField(),
        };
    }

    /// Creates size calculation code for serialization
    pub fn createSizeCheck(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createSizeCheck(),
        };
    }

    /// Creates serialization code
    pub fn createWriter(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createWriter(),
        };
    }

    /// Creates reader struct field declaration
    pub fn createReaderStructField(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createReaderStructField(),
        };
    }

    /// Creates deserialization case statement
    pub fn createReaderCase(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createReaderCase(),
        };
    }

    /// Creates getter method for the field
    pub fn createReaderMethod(self: Field) ![]const u8 {
        return switch (self) {
            inline else => |f| f.createReaderMethod(),
        };
    }

    /// Indicates whether field's reader needs allocator
    pub fn readerNeedsAllocator(self: Field) bool {
        return switch (self) {
            inline else => |f| f.readerNeedsAllocator(),
        };
    }

    /// Creates cleanup code for reader's storage
    pub fn createReaderDeinit(self: Field) ![]const u8 {
        return switch (self) {
            .repeated_bytes => |f| f.createReaderDeinit(),
            .repeated_message => |f| f.createReaderDeinit(),
            .repeated_enum => |f| f.createReaderDeinit(),
            .repeated_scalar => |f| f.createReaderDeinit(),
            .map => |f| f.createReaderDeinit(),
            else => "",
        };
    }

    /// Cleans up any allocated resources for the field
    pub fn deinit(self: *Field) void {
        switch (self.*) {
            inline else => |*f| f.deinit(),
        }
    }
};

/// Helper for creating appropriate field instances from Protocol Buffer definitions
pub const FieldBuilder = struct {
    /// Creates fields from normal (non-OneOf) message fields
    pub fn createNormalFields(
        allocator: std.mem.Allocator,
        fields_list: *std.ArrayList(Field),
        src: *const Message,
        scope: *std.ArrayList([]const u8),
        wire_name: []const u8,
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !void {
        for (src.fields.items) |*mf| {
            const field = if (mf.repeated)
                try createRepeatedField(
                    allocator,
                    mf,
                    wire_name,
                    scope,
                    writer_struct_name,
                    reader_struct_name,
                )
            else
                try createSingleField(
                    allocator,
                    mf,
                    wire_name,
                    scope,
                    writer_struct_name,
                    reader_struct_name,
                );

            try fields_list.append(allocator, field);
        }
    }

    /// Creates fields from OneOf message fields
    pub fn createOneOfFields(
        allocator: std.mem.Allocator,
        fields_list: *std.ArrayList(Field),
        src: *const Message,
        scope: *std.ArrayList([]const u8),
        wire_name: []const u8,
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !void {
        for (src.oneofs.items) |*of| {
            for (of.fields.items) |*mf| {
                const field = try createOneOfField(
                    allocator,
                    mf,
                    wire_name,
                    scope,
                    writer_struct_name,
                    reader_struct_name,
                );
                try fields_list.append(allocator, field);
            }
        }
    }

    /// Creates fields from map definitions
    pub fn createMapFields(
        allocator: std.mem.Allocator,
        fields_list: *std.ArrayList(Field),
        src: *const Message,
        scope: *std.ArrayList([]const u8),
        wire_name: []const u8,
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !void {
        for (src.maps.items) |*map| {
            const field = try field_types.ZigMapField.init(
                allocator,
                map,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            );
            try fields_list.append(allocator, Field{ .map = field });
        }
    }

    /// Creates a repeated field based on the field type
    fn createRepeatedField(
        allocator: std.mem.Allocator,
        mf: *const fields.NormalField,
        wire_name: []const u8,
        scope: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !Field {
        if (mf.f_type.is_scalar) {
            return Field{ .repeated_scalar = try field_types.ZigRepeatableScalarField.init(
                allocator,
                mf.f_name,
                mf.f_type.src,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.is_bytes) {
            return Field{ .repeated_bytes = try field_types.ZigRepeatableBytesField.init(
                allocator,
                mf.f_name,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.isEnum()) {
            return Field{ .repeated_enum = try field_types.ZigRepeatableEnumField.init(
                allocator,
                mf.f_name,
                mf.f_type,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.isMsg()) {
            return Field{ .repeated_message = try field_types.ZigRepeatableMessageField.init(
                allocator,
                mf.f_name,
                mf.f_type,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        }
        return error.UnsupportedFieldType;
    }

    /// Creates a single (non-repeated) field based on the field type
    fn createSingleField(
        allocator: std.mem.Allocator,
        mf: *const fields.NormalField,
        wire_name: []const u8,
        scope: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !Field {
        if (mf.f_type.is_scalar) {
            return Field{ .scalar = try field_types.ZigScalarField.init(
                allocator,
                mf.f_name,
                mf.f_type.src,
                mf.options,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.is_bytes) {
            return Field{ .bytes = try field_types.ZigBytesField.init(
                allocator,
                mf.f_name,
                mf.options,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.isEnum()) {
            return Field{ .enumeration = try field_types.ZigEnumField.init(
                allocator,
                mf.f_name,
                mf.f_type,
                mf.options,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.isMsg()) {
            return Field{ .message = try field_types.ZigMessageField.init(
                allocator,
                mf.f_name,
                mf.f_type,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        }
        return error.UnsupportedFieldType;
    }

    /// Creates a OneOf field variant based on the field type
    fn createOneOfField(
        allocator: std.mem.Allocator,
        mf: *const fields.OneOfField,
        wire_name: []const u8,
        scope: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !Field {
        if (mf.f_type.is_scalar) {
            return Field{ .scalar = try field_types.ZigScalarField.init(
                allocator,
                mf.f_name,
                mf.f_type.src,
                mf.options,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.is_bytes) {
            return Field{ .bytes = try field_types.ZigBytesField.init(
                allocator,
                mf.f_name,
                mf.options,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.isEnum()) {
            return Field{ .enumeration = try field_types.ZigEnumField.init(
                allocator,
                mf.f_name,
                mf.f_type,
                mf.options,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        } else if (mf.f_type.isMsg()) {
            return Field{ .message = try field_types.ZigMessageField.init(
                allocator,
                mf.f_name,
                mf.f_type,
                mf.index,
                wire_name,
                scope,
                writer_struct_name,
                reader_struct_name,
            ) };
        }
        return error.UnsupportedFieldType;
    }
};
