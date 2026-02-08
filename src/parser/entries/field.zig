//! Field parser module for Protocol Buffer definitions.
//! Handles parsing of all field types including normal fields, oneof fields,
//! and map fields with their associated options and modifiers.

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
const Option = @import("option.zig").Option;
const Reserved = @import("reserved.zig").Reserved;
const Message = @import("message.zig").Message;
const Enum = @import("enum.zig").Enum;
const ScopedName = @import("scoped-name.zig").ScopedName;
const ProtoFile = @import("file.zig").ProtoFile;
const FieldType = @import("field-type.zig").FieldType;
const scalar_types = @import("field-type.zig").scalar_types;

/// Represents a field within a oneof group
pub const OneOfField = struct {
    start: usize,
    end: usize,
    /// Type of the field
    f_type: FieldType,
    /// Name of the field
    f_name: []const u8,
    /// Field number in the protocol
    index: i32,
    /// Optional field options
    options: ?std.ArrayList(Option),

    allocator: std.mem.Allocator,

    /// Parses a single field within a oneof group
    /// Format: type name = number [options];
    pub fn parse(allocator: std.mem.Allocator, scope: ScopedName, buf: *ParserBuffer) Error!OneOfField {
        try buf.skipSpaces();
        const start = buf.offset;

        const f_type = try FieldType.parse(allocator, scope, buf);
        const f_name = try lex.ident(buf);
        try buf.assignment();
        const f_number = try lex.intLit(buf);
        const f_opts = try Option.parseList(allocator, buf);
        try buf.semicolon();

        return OneOfField{
            .allocator = allocator,
            .start = start,
            .end = buf.offset,
            .f_type = f_type,
            .f_name = f_name,
            .index = try std.fmt.parseInt(i32, f_number, 0),
            .options = f_opts,
        };
    }

    /// Creates a deep copy of the field
    pub fn clone(f: *const OneOfField) Error!OneOfField {
        var opts: ?std.ArrayList(Option) = null;
        if (f.options) |options| {
            opts = try options.clone(f.allocator);
        }

        return OneOfField{
            .allocator = f.allocator,
            .start = 0,
            .end = 0,
            .f_type = try f.f_type.clone(),
            .f_name = f.f_name,
            .index = f.index,
            .options = opts,
        };
    }

    /// Frees resources owned by the field
    pub fn deinit(f: *OneOfField) void {
        if (f.options) |*options| {
            options.deinit(f.allocator);
        }
        f.f_type.deinit();
    }
};

/// Represents a oneof group in a message
pub const MessageOneOfField = struct {
    start: usize,
    end: usize,
    /// Name of the oneof group
    name: []const u8,
    /// Fields contained in the oneof group
    fields: std.ArrayList(OneOfField),
    /// Options for the oneof group
    options: std.ArrayList(Option),

    allocator: std.mem.Allocator,

    /// Parses a complete oneof declaration
    /// Format: oneof name { field1; field2; ... }
    pub fn parse(allocator: std.mem.Allocator, scope: ScopedName, buf: *ParserBuffer) Error!?MessageOneOfField {
        try buf.skipSpaces();
        const start = buf.offset;

        if (!buf.checkStrWithSpaceAndShift("oneof")) {
            return null;
        }
        try buf.skipSpaces();
        const name = try lex.ident(buf);
        try buf.openBracket();

        var fields = try std.ArrayList(OneOfField).initCapacity(allocator, 32);
        var options = try std.ArrayList(Option).initCapacity(allocator, 32);
        errdefer {
            fields.deinit(allocator);
            options.deinit(allocator);
        }

        while (true) {
            if (try Option.parse(buf)) |option| {
                try options.append(allocator, option);
            } else {
                try fields.append(allocator, try OneOfField.parse(allocator, scope, buf));
            }
            try buf.skipSpaces();
            const c = try buf.char();
            if (c == '}') {
                buf.offset += 1;
                break;
            }
        }

        return MessageOneOfField{
            .start = start,
            .end = buf.offset,
            .name = name,
            .fields = fields,
            .options = options,
            .allocator = allocator,
        };
    }

    /// Creates a deep copy of the oneof group
    pub fn clone(f: *const MessageOneOfField) Error!MessageOneOfField {
        var fields = try std.ArrayList(OneOfField).initCapacity(f.allocator, 32);
        for (f.fields.items) |*field| {
            try fields.append(f.allocator, try field.clone());
        }

        return MessageOneOfField{
            .allocator = f.allocator,
            .start = 0,
            .end = 0,
            .name = f.name,
            .fields = fields,
            .options = try f.options.clone(f.allocator),
        };
    }

    /// Frees resources owned by the oneof group
    pub fn deinit(f: *MessageOneOfField) void {
        for (f.fields.items) |*field| {
            field.deinit();
        }
        f.fields.deinit(f.allocator);
        f.options.deinit(f.allocator);
    }
};

/// Represents a map field in a message
pub const MessageMapField = struct {
    start: usize,
    end: usize,
    /// Key type of the map
    key_type: []const u8,
    /// Value type of the map
    value_type: FieldType,
    /// Name of the map field
    f_name: []const u8,
    /// Field number in the protocol
    index: i32,
    /// Optional field options
    options: ?std.ArrayList(Option),

    allocator: std.mem.Allocator,

    /// Parses a map field declaration
    /// Format: map<key_type, value_type> name = number [options];
    pub fn parse(allocator: std.mem.Allocator, scope: ScopedName, buf: *ParserBuffer) Error!?MessageMapField {
        try buf.skipSpaces();
        const start = buf.offset;

        if (!buf.checkStrAndShift("map")) {
            return null;
        }
        try buf.skipSpaces();

        // Parse map type definition
        if ((try buf.char()) != '<') return null;
        buf.offset += 1;

        const key_type = try mapKeyType(buf);
        if (key_type == null) {
            return Error.InvalidMapKeyType;
        }

        try buf.skipSpaces();
        if ((try buf.char()) != ',') {
            return Error.InvalidMapKeyType;
        }
        buf.offset += 1;

        const value_type = try FieldType.parse(allocator, scope, buf);
        if (value_type.src.len == 0) {
            return Error.InvalidMapValueType;
        }

        try buf.skipSpaces();
        if ((try buf.char()) != '>') {
            return Error.InvalidMapValueType;
        }
        buf.offset += 1;

        // Parse field definition
        try buf.skipSpaces();
        const f_name = try lex.ident(buf);
        try buf.assignment();
        const f_number = try lex.intLit(buf);
        const options = try Option.parseList(allocator, buf);
        try buf.semicolon();

        return MessageMapField{
            .start = start,
            .end = buf.offset,
            .key_type = key_type orelse unreachable,
            .value_type = value_type,
            .f_name = f_name,
            .index = try std.fmt.parseInt(i32, f_number, 0),
            .options = options,
            .allocator = allocator,
        };
    }

    /// Creates a deep copy of the map field
    pub fn clone(f: *const MessageMapField) Error!MessageMapField {
        var opts: ?std.ArrayList(Option) = null;
        if (f.options) |options| {
            opts = try options.clone(f.allocator);
        }

        return MessageMapField{
            .allocator = f.allocator,
            .start = 0,
            .end = 0,
            .key_type = f.key_type,
            .value_type = try f.value_type.clone(),
            .f_name = f.f_name,
            .index = f.index,
            .options = opts,
        };
    }

    /// Frees resources owned by the map field
    pub fn deinit(f: *MessageMapField) void {
        if (f.options) |*options| {
            options.deinit(f.allocator);
        }
        f.value_type.deinit();
    }
};

/// Represents a normal field in a message
pub const NormalField = struct {
    start: usize,
    end: usize,
    /// Whether the field is repeated
    repeated: bool,
    /// Whether the field is optional (proto2)
    optional: bool,
    /// Whether the field is required (proto2)
    required: bool,
    /// Type of the field
    f_type: FieldType,
    /// Name of the field
    f_name: []const u8,
    /// Field number in the protocol
    index: i32,
    /// Optional field options
    options: ?std.ArrayList(Option),
    allocator: std.mem.Allocator,

    /// Parses a normal field declaration
    /// Format: [repeated|optional|required] type name = number [options];
    pub fn parse(allocator: std.mem.Allocator, scope: ScopedName, buf: *ParserBuffer) Error!NormalField {
        try buf.skipSpaces();
        const start = buf.offset;

        // Parse field modifiers
        var optional = false;
        if (buf.checkStrWithSpaceAndShift("optional")) {
            optional = true;
            try buf.skipSpaces();
        }
        var repeated = false;
        if (buf.checkStrWithSpaceAndShift("repeated")) {
            repeated = true;
            try buf.skipSpaces();
        }
        var required = false;
        if (buf.checkStrWithSpaceAndShift("required")) {
            required = true;
            try buf.skipSpaces();
        }

        // Parse field definition
        const f_type = try FieldType.parse(allocator, scope, buf);
        const f_name = try lex.ident(buf);
        try buf.assignment();
        const f_number = try lex.intLit(buf);
        const f_opts = try Option.parseList(allocator, buf);
        try buf.semicolon();

        return NormalField{ .start = start, .end = buf.offset, .repeated = repeated, .optional = optional, .required = required, .f_type = f_type, .f_name = f_name, .index = try std.fmt.parseInt(i32, f_number, 0), .options = f_opts, .allocator = allocator };
    }

    /// Creates a deep copy of the field
    pub fn clone(f: *const NormalField) Error!NormalField {
        var opts: ?std.ArrayList(Option) = null;
        if (f.options) |options| {
            opts = try options.clone(f.allocator);
        }

        return NormalField{ .start = 0, .end = 0, .repeated = f.repeated, .optional = f.optional, .required = f.required, .index = f.index, .f_name = f.f_name, .f_type = try f.f_type.clone(), .options = opts, .allocator = f.allocator };
    }

    /// Frees resources owned by the field
    pub fn deinit(f: *NormalField) void {
        if (f.options) |*options| {
            options.deinit(f.allocator);
        }
        f.f_type.deinit();
    }
};

/// Parses a map key type (scalar types, string, or bytes)
fn mapKeyType(buf: *ParserBuffer) Error!?[]const u8 {
    try buf.skipSpaces();

    // Check scalar types
    for (scalar_types) |key_type| {
        if (buf.checkStrAndShift(key_type)) {
            return key_type;
        }
    }

    // Check string/bytes types
    if (buf.checkStrAndShift("string")) {
        return "string";
    }
    if (buf.checkStrAndShift("bytes")) {
        return "bytes";
    }

    return null;
}

test "field parsing" {
    var scope = try ScopedName.init(std.testing.allocator, "");
    defer scope.deinit();

    // Test normal field
    {
        var buf = ParserBuffer.init("string name = 1;");
        var f = try NormalField.parse(std.testing.allocator, scope, &buf);
        defer f.deinit();

        try std.testing.expectEqualStrings("string", f.f_type.src);
        try std.testing.expectEqualStrings("name", f.f_name);
        try std.testing.expectEqual(1, f.index);
    }

    // Test map field
    {
        var buf = ParserBuffer.init("map<string, Project> projects = 3;");
        var f = try MessageMapField.parse(std.testing.allocator, scope, &buf) orelse unreachable;
        defer f.deinit();

        try std.testing.expectEqualStrings("string", f.key_type);
        try std.testing.expectEqualStrings("Project", f.value_type.src);
        try std.testing.expectEqualStrings("projects", f.f_name);
    }

    // Test oneof field
    {
        var buf = ParserBuffer.init(
            \\oneof foo {
            \\  string name = 4;
            \\  SubMessage sub_message = 9;
            \\}
        );
        var f = try MessageOneOfField.parse(std.testing.allocator, scope, &buf) orelse unreachable;
        defer f.deinit();

        try std.testing.expectEqualStrings("foo", f.name);
        try std.testing.expectEqual(2, f.fields.items.len);
    }

    // Test field with message literal option
    {
        var buf = ParserBuffer.init("int32 content_node_id = 1 [features = { field_presence: EXPLICIT }];");
        var f = try NormalField.parse(std.testing.allocator, scope, &buf);
        defer f.deinit();

        try std.testing.expectEqualStrings("int32", f.f_type.src);
        try std.testing.expectEqualStrings("content_node_id", f.f_name);
        try std.testing.expectEqual(1, f.index);
        try std.testing.expectEqual(1, f.options.?.items.len);
        try std.testing.expectEqualStrings("features", f.options.?.items[0].name);
        try std.testing.expectEqualStrings("{ field_presence: EXPLICIT }", f.options.?.items[0].value);
    }
}
