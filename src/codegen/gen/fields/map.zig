//! This module handles the generation of Zig code for Protocol Buffer map fields.
//! Protocol Buffers represent maps as repeated key-value pairs in the wire format.
//! In Zig, maps are implemented using either StringHashMap or AutoHashMap depending
//! on the key type.

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
const naming = @import("naming.zig");
const Option = @import("../../../parser/main.zig").Option;
const FieldType = @import("../../../parser/main.zig").FieldType;
const MessageMapField = @import("../../../parser/main.zig").fields.MessageMapField;

const scalarSize = @import("scalar.zig").scalarSize;
const scalarZigType = @import("scalar.zig").scalarZigType;
const scalarWriter = @import("scalar.zig").scalarWriter;
const scalarReader = @import("scalar.zig").scalarReader;
const scalarDefaultValue = @import("scalar.zig").scalarDefaultValue;

pub const ZigMapField = struct {
    allocator: std.mem.Allocator,

    writer_struct_name: []const u8,
    reader_struct_name: []const u8,

    key_type: []const u8,
    value_type: FieldType,
    field_index: i32,

    writer_field_name: []const u8,
    reader_offset_field_name: []const u8,
    reader_last_offset_field_name: []const u8,
    reader_cnt_field_name: []const u8,
    reader_next_method_name: []const u8,
    reader_cnt_method_name: []const u8,
    reader_entry_type_name: []const u8,

    wire_const_full_name: []const u8,
    wire_const_name: []const u8,

    resolved_enum_type: ?[]const u8 = null,
    resolved_writer_message_type: ?[]const u8 = null,
    resolved_reader_message_type: ?[]const u8 = null,

    pub fn init(
        allocator: std.mem.Allocator,
        field: *const MessageMapField,
        wire_prefix: []const u8,
        names: *std.ArrayList([]const u8),
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !ZigMapField {
        const name = try naming.structFieldName(allocator, field.f_name, names);

        const wirePostfixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field.f_name, "Wire" });
        defer allocator.free(wirePostfixed);
        const wireConstName = try naming.constName(allocator, wirePostfixed, names);
        const wireName = try std.mem.concat(allocator, u8, &[_][]const u8{
            wire_prefix,
            ".",
            wireConstName,
        });

        const reader_next_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ "next_", field.f_name });
        defer allocator.free(reader_next_prefixed);
        const readerNextMethodName = try naming.structMethodName(allocator, reader_next_prefixed, names);

        const reader_cnt_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ "count_", field.f_name });
        defer allocator.free(reader_cnt_prefixed);
        const readerCntMethodName = try naming.structMethodName(allocator, reader_cnt_prefixed, names);

        const entry_type_prefixed = try std.mem.concat(allocator, u8, &[_][]const u8{ field.f_name, "_entry" });
        defer allocator.free(entry_type_prefixed);
        const entryTypeName = try naming.structName(allocator, entry_type_prefixed, names);

        return ZigMapField{
            .allocator = allocator,
            .key_type = field.key_type,
            .value_type = field.value_type,
            .field_index = field.index,
            .writer_field_name = name,
            .reader_offset_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_offset" }),
            .reader_last_offset_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_last_offset" }),
            .reader_cnt_field_name = try std.mem.concat(allocator, u8, &[_][]const u8{ "_", name, "_cnt" }),
            .reader_next_method_name = readerNextMethodName,
            .reader_cnt_method_name = readerCntMethodName,
            .reader_entry_type_name = entryTypeName,
            .wire_const_full_name = wireName,
            .wire_const_name = wireConstName,
            .writer_struct_name = writer_struct_name,
            .reader_struct_name = reader_struct_name,
        };
    }

    pub fn deinit(self: *ZigMapField) void {
        self.allocator.free(self.writer_field_name);
        self.allocator.free(self.reader_offset_field_name);
        self.allocator.free(self.reader_last_offset_field_name);
        self.allocator.free(self.reader_cnt_field_name);
        self.allocator.free(self.reader_next_method_name);
        self.allocator.free(self.reader_cnt_method_name);
        self.allocator.free(self.reader_entry_type_name);
        self.allocator.free(self.wire_const_full_name);
        self.allocator.free(self.wire_const_name);

        if (self.resolved_enum_type) |e| {
            self.allocator.free(e);
        }
        if (self.resolved_reader_message_type) |m| {
            self.allocator.free(m);
        }
        if (self.resolved_writer_message_type) |m| {
            self.allocator.free(m);
        }
    }

    // Key-related helper functions

    /// Get the Zig type for the map key
    fn keyType(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return "[]const u8";
        } else {
            return scalarZigType(self.key_type);
        }
    }

    /// Generate code for calculating key size
    fn keySize(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return self.allocator.dupe(u8,
                \\const key = entry.key_ptr.*;
                \\        const key_size = gremlin.sizes.sizeUsize(key.len) + key.len;
            );
        } else {
            return std.mem.concat(self.allocator, u8, &[_][]const u8{
                "const key = entry.key_ptr.*;\n",
                "        const key_size = ",
                scalarSize(self.key_type),
                "(key);",
            });
        }
    }

    /// Generate code for writing key to wire format
    fn keyWrite(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return self.allocator.dupe(u8, "target.appendBytes(1, key);");
        } else {
            return std.mem.concat(self.allocator, u8, &[_][]const u8{
                "target.",
                scalarWriter(self.key_type),
                "(1, key);",
            });
        }
    }

    /// Generate code for reading key from wire format
    fn keyRead(self: *const ZigMapField) ![]const u8 {
        if (std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes")) {
            return self.allocator.dupe(u8,
                \\const sized_key = try entry_buf.readBytes(entry_offset);
                \\                      key = sized_key.value;
                \\                      entry_offset += sized_key.size;
            );
        } else {
            return std.fmt.allocPrint(self.allocator,
                \\const sized_key = try entry_buf.{s}(entry_offset);
                \\                      key = sized_key.value;
                \\                      entry_offset += sized_key.size;
            , .{scalarReader(self.key_type)});
        }
    }

    // Value-related helper functions

    /// Get the Zig type for map value (writer side)
    fn valueType(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "[]const u8");
        } else if (self.value_type.is_scalar) {
            return try self.allocator.dupe(u8, scalarZigType(self.value_type.src));
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8, self.resolved_enum_type.?);
        } else {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                self.resolved_writer_message_type.?,
            });
        }
    }

    /// Get the Zig type for map value (reader side)
    fn valueReaderType(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "[]const u8");
        } else if (self.value_type.is_scalar) {
            return try self.allocator.dupe(u8, scalarZigType(self.value_type.src));
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8, self.resolved_enum_type.?);
        } else {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                self.resolved_reader_message_type.?,
            });
        }
    }

    /// Generate code for reading value from wire format
    fn valueRead(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return self.allocator.dupe(u8,
                \\const sized_value = try entry_buf.readBytes(entry_offset);
                \\                      value = sized_value.value;
                \\                      entry_offset += sized_value.size;
            );
        } else if (self.value_type.is_scalar) {
            return std.fmt.allocPrint(self.allocator,
                \\const sized_value = try entry_buf.{s}(entry_offset);
                \\                      value = sized_value.value;
                \\                      entry_offset += sized_value.size;
            , .{scalarReader(self.value_type.src)});
        } else if (self.value_type.isEnum()) {
            return self.allocator.dupe(u8,
                \\const sized_value = try entry_buf.readInt32(entry_offset);
                \\                      value = @enumFromInt(sized_value.value);
                \\                      entry_offset += sized_value.size;
            );
        } else {
            return std.fmt.allocPrint(self.allocator,
                \\const sized_value = try entry_buf.readBytes(entry_offset);
                \\                      value = try {s}.init(sized_value.value);
                \\                      entry_offset += sized_value.size;
            , .{self.resolved_reader_message_type.?});
        }
    }

    /// Generate code for calculating value size
    fn valueSize(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8,
                \\const value = entry.value_ptr.*;
                \\        const value_size = gremlin.sizes.sizeUsize(value.len) + value.len;
            );
        } else if (self.value_type.is_scalar) {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                "const value = entry.value_ptr.*;\n        const value_size = ",
                scalarSize(self.value_type.src),
                "(value);",
            });
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8,
                \\const value = entry.value_ptr.*;
                \\        const value_size = gremlin.sizes.sizeI32(@intFromEnum(value));
            );
        } else {
            return try self.allocator.dupe(u8,
                \\const value = entry.value_ptr;
                \\        const v_size = value.calcProtobufSize();
                \\        const value_size: usize = gremlin.sizes.sizeUsize(v_size) + v_size;
            );
        }
    }

    /// Generate code for writing value to wire format
    fn valueWrite(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "target.appendBytes(2, value);");
        } else if (self.value_type.is_scalar) {
            return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                "target.",
                scalarWriter(self.value_type.src),
                "(2, value);",
            });
        } else if (self.value_type.isEnum()) {
            return try self.allocator.dupe(u8, "target.appendInt32(2, @intFromEnum(value));");
        } else {
            return try self.allocator.dupe(u8,
                \\target.appendBytesTag(2, v_size);
                \\        value.encodeTo(target);
            );
        }
    }

    /// Generate code for value variable declaration
    fn valueReaderVar(self: *const ZigMapField) ![]const u8 {
        if (self.value_type.is_bytes) {
            return try self.allocator.dupe(u8, "var value: []const u8 = undefined;");
        } else if (self.value_type.is_scalar) {
            return try std.fmt.allocPrint(self.allocator, "var value: {s} = {s};", .{ scalarZigType(self.value_type.src), scalarDefaultValue(self.value_type.src) });
        } else if (self.value_type.isEnum()) {
            return try std.fmt.allocPrint(self.allocator, "var value: {s} = @enumFromInt(0);", .{self.resolved_enum_type.?});
        } else {
            return try std.fmt.allocPrint(self.allocator, "var value: {s} = undefined;", .{self.resolved_reader_message_type.?});
        }
    }

    // Type resolution methods

    /// Set the resolved enum type name after type resolution phase
    pub fn resolveEnumValue(self: *ZigMapField, resolved_enum_type: []const u8) !void {
        self.resolved_enum_type = try self.allocator.dupe(u8, resolved_enum_type);
    }

    /// Set the resolved message type names after type resolution phase
    pub fn resoveMessageValue(self: *ZigMapField, resolved_writer_message_type: []const u8, resolved_reader_message_type: []const u8) !void {
        self.resolved_writer_message_type = try self.allocator.dupe(u8, resolved_writer_message_type);
        self.resolved_reader_message_type = try self.allocator.dupe(u8, resolved_reader_message_type);
    }

    // Code generation methods for field definitions and operations

    /// Generate map entry type definition for top-level declarations
    pub fn generateDeclarations(self: *const ZigMapField) ![]const u8 {
        const key_type = try self.keyType();
        const value_type = try self.valueReaderType();
        defer self.allocator.free(value_type);

        return std.fmt.allocPrint(self.allocator,
            \\pub const {s} = struct {{
            \\    key: {s},
            \\    value: {s},
            \\}};
        , .{ self.reader_entry_type_name, key_type, value_type });
    }

    /// Generate wire format constant declaration
    pub fn createWireConst(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "const {s}: gremlin.ProtoWireNumber = {d};", .{ self.wire_const_name, self.field_index });
    }

    /// Generate writer struct field declaration.
    /// Creates either a StringHashMap or AutoHashMap based on key type.
    pub fn createWriterStructField(self: *const ZigMapField) ![]const u8 {
        const is_str_key = std.mem.eql(u8, self.key_type, "string") or std.mem.eql(u8, self.key_type, "bytes");
        const value_type = try self.valueType();
        defer self.allocator.free(value_type);

        if (is_str_key) {
            return std.fmt.allocPrint(self.allocator, "{s}: ?*std.StringHashMap({s}) = null,", .{ self.writer_field_name, value_type });
        } else {
            const key_type = try self.keyType();
            return std.fmt.allocPrint(self.allocator, "{s}: ?*std.AutoHashMap({s}, {s}) = null,", .{ self.writer_field_name, key_type, value_type });
        }
    }

    /// Generate size calculation code for serialization.
    /// Maps are encoded as repeated messages, where each message contains a key-value pair.
    pub fn createSizeCheck(self: *const ZigMapField) ![]const u8 {
        const key_size = try self.keySize();
        const value_size = try self.valueSize();
        defer self.allocator.free(key_size);
        defer self.allocator.free(value_size);

        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |v| {{
            \\    var it = v.iterator();
            \\    const entry_wire = gremlin.sizes.sizeWireNumber({s});
            \\    while (it.next()) |entry| {{
            \\        {s}
            \\        {s}
            \\        const entry_size = key_size + value_size + gremlin.sizes.sizeWireNumber(1) + gremlin.sizes.sizeWireNumber(2);
            \\        res += entry_wire + gremlin.sizes.sizeUsize(entry_size) + entry_size;
            \\    }}
            \\}}
        , .{ self.writer_field_name, self.wire_const_full_name, key_size, value_size });
    }

    /// Generate serialization code for the map field.
    /// Each key-value pair is written as a separate message with fields 1 (key) and 2 (value).
    pub fn createWriter(self: *const ZigMapField) ![]const u8 {
        const key_writer = try self.keyWrite();
        const value_writer = try self.valueWrite();
        const key_size = try self.keySize();
        const value_size = try self.valueSize();
        defer self.allocator.free(key_writer);
        defer self.allocator.free(value_writer);
        defer self.allocator.free(key_size);
        defer self.allocator.free(value_size);

        return std.fmt.allocPrint(self.allocator,
            \\if (self.{s}) |v| {{
            \\    var it = v.iterator();
            \\    while (it.next()) |entry| {{
            \\        {s}
            \\        {s}
            \\        const entry_size = key_size + value_size + gremlin.sizes.sizeWireNumber(1) + gremlin.sizes.sizeWireNumber(2);
            \\        target.appendBytesTag({s}, entry_size);
            \\        {s}
            \\        {s}
            \\    }}
            \\}}
        , .{ self.writer_field_name, key_size, value_size, self.wire_const_full_name, key_writer, value_writer });
    }

    pub fn createReaderStructField(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\{s}: ?usize = null,
            \\{s}: ?usize = null,
            \\{s}: usize = 0,
        , .{ self.reader_offset_field_name, self.reader_last_offset_field_name, self.reader_cnt_field_name });
    }

    pub fn createReaderCase(self: *const ZigMapField) ![]const u8 {
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
        , .{ self.wire_const_full_name, self.reader_offset_field_name, self.reader_offset_field_name, self.reader_last_offset_field_name, self.reader_cnt_field_name });
    }

    /// Generate count method that returns the number of map entries
    pub fn createReaderCountMethod(self: *const ZigMapField) ![]const u8 {
        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *const {s}) usize {{
            \\    return self.{s};
            \\}}
        , .{ self.reader_cnt_method_name, self.reader_struct_name, self.reader_cnt_field_name });
    }

    /// Generate next method that iterates through map entries
    pub fn createReaderNextMethod(self: *const ZigMapField) ![]const u8 {
        const key_type = try self.keyType();
        const value_type = try self.valueReaderType();
        const key_read = try self.keyRead();
        const value_reader_var = try self.valueReaderVar();
        const value_read = try self.valueRead();
        defer self.allocator.free(value_type);
        defer self.allocator.free(key_read);
        defer self.allocator.free(value_reader_var);
        defer self.allocator.free(value_read);

        return std.fmt.allocPrint(self.allocator,
            \\pub fn {s}(self: *{s}) gremlin.Error!?{s} {{
            \\    if (self.{s}) |current_offset| {{
            \\        if (self.{s}) |last_offset| {{
            \\            if (current_offset >= last_offset) {{
            \\                self.{s} = null;
            \\                return null;
            \\            }}
            \\        }}
            \\
            \\        var offset = current_offset;
            \\        const tag = try self.buf.readTagAt(offset);
            \\        offset += tag.size;
            \\
            \\        const result = try self.buf.readBytes(offset);
            \\        offset += result.size;
            \\
            \\        const entry_buf = gremlin.Reader.init(result.value);
            \\        var entry_offset: usize = 0;
            \\
            \\        var key: {s} = undefined;
            \\        var has_key = false;
            \\        {s}
            \\        var has_value = false;
            \\
            \\        while (entry_buf.hasNext(entry_offset, 0)) {{
            \\            const entry_tag = try entry_buf.readTagAt(entry_offset);
            \\            entry_offset += entry_tag.size;
            \\            switch (entry_tag.number) {{
            \\                1 => {{
            \\                    {s}
            \\                    has_key = true;
            \\                }},
            \\                2 => {{
            \\                    {s}
            \\                    has_value = true;
            \\                }},
            \\                else => {{
            \\                    entry_offset = try entry_buf.skipData(entry_offset, entry_tag.wire);
            \\                }}
            \\            }}
            \\        }}
            \\
            \\        self.{s} = offset;
            \\
            \\        if (has_key and has_value) {{
            \\            return {s}{{ .key = key, .value = value }};
            \\        }}
            \\        return null;
            \\    }}
            \\    return null;
            \\}}
        , .{
            self.reader_next_method_name,
            self.reader_struct_name,
            self.reader_entry_type_name,
            self.reader_offset_field_name,
            self.reader_last_offset_field_name,
            self.reader_offset_field_name,
            key_type,
            value_reader_var,
            key_read,
            value_read,
            self.reader_offset_field_name,
            self.reader_entry_type_name,
        });
    }

    /// Generate reader method that combines both count and next methods
    pub fn createReaderMethod(self: *const ZigMapField) ![]const u8 {
        const count_method = try self.createReaderCountMethod();
        defer self.allocator.free(count_method);
        const next_method = try self.createReaderNextMethod();
        defer self.allocator.free(next_method);

        return std.fmt.allocPrint(self.allocator,
            \\{s}
            \\
            \\{s}
        , .{ count_method, next_method });
    }
};
