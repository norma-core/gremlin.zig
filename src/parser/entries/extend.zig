//! Extend declaration parser module for Protocol Buffer text format.
//! Handles parsing of extend blocks and their fields, which allow extending
//! existing message types with additional fields.

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
const ScopedName = @import("scoped-name.zig").ScopedName;

/// Represents a single field within an extend block.
/// Each field has a type, name, number, and optional modifiers/options.
pub const ExtendField = struct {
    /// Starting byte offset in source
    start: usize,
    /// Ending byte offset in source
    end: usize,
    /// Field name (e.g., "unpacked_int32_extension")
    f_name: []const u8,
    /// Field type (e.g., "int32")
    f_type: []const u8,
    /// Field number as string (e.g., "90")
    f_value: []const u8,

    /// Whether field is marked optional
    optional: bool,
    /// Whether field is marked repeated
    repeated: bool,

    /// Optional field options in brackets
    options: ?std.ArrayList(Option),

    allocator: std.mem.Allocator,

    /// Parses a single extend field declaration.
    /// Format: [optional|repeated] type name = number [options];
    ///
    /// # Errors
    /// Returns error on invalid syntax or allocation failure
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?ExtendField {
        try buf.skipSpaces();

        const start = buf.offset;

        // Parse modifiers
        var optional = true;
        if (buf.checkStrAndShift("optional")) {
            try buf.skipSpaces();
        } else {
            optional = false;
        }

        var repeated = false;
        if (buf.checkStrAndShift("repeated")) {
            try buf.skipSpaces();
            repeated = true;
        }

        // Parse the field components
        const f_type = try lex.fieldType(buf);
        const name = try lex.ident(buf);
        try buf.assignment();
        const value = try lex.intLit(buf);
        const opts = try Option.parseList(allocator, buf);
        try buf.semicolon();

        return ExtendField{
            .start = start,
            .end = buf.offset,
            .optional = optional,
            .repeated = repeated,
            .f_name = name,
            .f_type = f_type,
            .f_value = value,
            .options = opts,
            .allocator = allocator,
        };
    }

    /// Frees resources owned by the ExtendField
    pub fn deinit(self: *ExtendField) void {
        if (self.options) |*opts| {
            opts.deinit(self.allocator);
        }
    }
};

/// Represents a complete extend block declaration which extends
/// an existing message type with new fields.
pub const Extend = struct {
    /// Starting byte offset in source
    start: usize,
    /// Ending byte offset in source
    end: usize,
    /// Name of the message type being extended
    base: ScopedName,

    /// Allocator used for dynamic allocations
    allocator: std.mem.Allocator,
    /// List of fields added by this extend block
    fields: std.ArrayList(ExtendField),

    /// Parses a complete extend block.
    /// Format: extend MessageType { fields... }
    ///
    /// # Errors
    /// Returns error on invalid syntax or allocation failure
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?Extend {
        try buf.skipSpaces();

        const offset = buf.offset;
        if (!buf.checkStrWithSpaceAndShift("extend")) {
            return null;
        }

        // Parse the base message type being extended
        const base_src = try lex.fieldType(buf);
        const base = try ScopedName.init(allocator, base_src);
        try buf.openBracket();

        // Parse the field declarations
        var fields = try std.ArrayList(ExtendField).initCapacity(allocator, 32);
        errdefer fields.deinit(allocator);

        // Handle empty extend block
        const c = try buf.char();
        if (c == '}') {
            buf.offset += 1;
        } else {
            // Parse fields until closing brace
            while (true) {
                if (try ExtendField.parse(allocator, buf)) |field| {
                    try fields.append(allocator, field);
                }
                try buf.skipSpaces();
                const ec = try buf.char();
                if (ec == ';') {
                    buf.offset += 1;
                } else if (ec == '}') {
                    buf.offset += 1;
                    break;
                }
            }
        }

        return Extend{
            .start = offset,
            .end = buf.offset,
            .base = base,
            .allocator = allocator,
            .fields = fields,
        };
    }

    /// Frees all resources owned by the Extend declaration
    pub fn deinit(self: *Extend) void {
        for (self.fields.items) |*field| {
            field.deinit();
        }
        self.fields.deinit(self.allocator);
        self.base.deinit();
    }
};

test "extend field parsing" {
    var buf = ParserBuffer.init("string field = 0;");
    const result = try ExtendField.parse(std.testing.allocator, &buf) orelse unreachable;

    try std.testing.expectEqual(0, result.start);
    try std.testing.expectEqual(17, result.end);
    try std.testing.expectEqualStrings("string", result.f_type);
    try std.testing.expectEqualStrings("field", result.f_name);
    try std.testing.expectEqualStrings("0", result.f_value);
}

test "extend block parsing" {
    var buf = ParserBuffer.init(
        \\ extend TestUnpackedExtensions {
        \\    repeated    int32 unpacked_int32_extension    =  90 [packed = false];
        \\    repeated    int64 unpacked_int64_extension    =  91 [packed = false];
        \\    repeated   uint32 unpacked_uint32_extension   =  92 [packed = false];
        \\    repeated   uint64 unpacked_uint64_extension   =  93 [packed = false];
        \\    repeated   sint32 unpacked_sint32_extension   =  94 [packed = false];
        \\    repeated   sint64 unpacked_sint64_extension   =  95 [packed = false];
        \\    repeated  fixed32 unpacked_fixed32_extension  =  96 [packed = false];
        \\    repeated  fixed64 unpacked_fixed64_extension  =  97 [packed = false];
        \\    repeated sfixed32 unpacked_sfixed32_extension =  98 [packed = false];
        \\    repeated sfixed64 unpacked_sfixed64_extension =  99 [packed = false];
        \\    repeated    float unpacked_float_extension    = 100 [packed = false];
        \\    repeated   double unpacked_double_extension   = 101 [packed = false];
        \\    repeated     bool unpacked_bool_extension     = 102 [packed = false];
        \\    repeated ForeignEnum unpacked_enum_extension  = 103 [packed = false];
        \\ }
    );
    var result = try Extend.parse(std.testing.allocator, &buf) orelse unreachable;
    defer result.deinit();
}
