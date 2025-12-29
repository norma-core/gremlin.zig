//! Enum module provides parsing capabilities for Protocol Buffer enum declarations.
//! This module handles both enum definitions and their fields, supporting options,
//! reserved fields, and nested enum declarations within messages.

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
const ScopedName = @import("scoped-name.zig").ScopedName;

/// EnumField represents a single field within an enum declaration.
/// Example: FOO = 1 [deprecated = true];
pub const EnumField = struct {
    allocator: std.mem.Allocator,
    /// Starting position in source
    start: usize,
    /// Ending position in source
    end: usize,
    /// Field name (e.g., "FOO")
    name: []const u8,
    /// Numeric value assigned to this enum field
    index: i32,
    /// Optional field options
    options: ?std.ArrayList(Option),

    /// Parse an enum field from the buffer.
    /// Returns null if the current buffer position doesn't contain an enum field.
    ///
    /// Format:
    ///   FIELD_NAME = NUMBER [options];
    ///
    /// Memory ownership:
    /// - Caller owns the returned EnumField and must call deinit()
    /// - Options are allocated using the provided allocator
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?EnumField {
        try buf.skipSpaces();
        const start = buf.offset;

        // Parse field name
        const name = try lex.ident(buf);

        // Expect assignment
        try buf.assignment();

        // Parse field value (supports decimal, hex, octal)
        const value = try lex.intLit(buf);
        const parsed = try std.fmt.parseInt(i32, value, 0);

        // Parse optional field options
        const opts = try Option.parseList(allocator, buf);

        try buf.semicolon();

        return EnumField{
            .allocator = allocator,
            .start = start,
            .end = buf.offset,
            .name = name,
            .index = parsed,
            .options = opts,
        };
    }

    /// Free all memory associated with the enum field
    pub fn deinit(self: *EnumField) void {
        if (self.options) |*opts| {
            opts.deinit(self.allocator);
        }
    }
};

/// Enum represents a complete Protocol Buffer enum declaration, including
/// its name, fields, options, and reserved ranges.
pub const Enum = struct {
    allocator: std.mem.Allocator,
    /// Starting position in source
    start: usize,
    /// Ending position in source
    end: usize,
    /// Fully qualified enum name
    name: ScopedName,
    /// Enum-level options
    options: std.ArrayList(Option),
    /// List of enum fields
    fields: std.ArrayList(EnumField),
    /// Reserved field numbers/names
    reserved: std.ArrayList(Reserved),
    /// Parent message if this is a nested enum
    parent: ?*Message = null,

    /// Parse an enum declaration from the buffer.
    /// Returns null if the current buffer position doesn't start with "enum".
    ///
    /// Format:
    ///   enum EnumName {
    ///     option opt = "value";  // enum options
    ///     UNKNOWN = 0;           // enum fields
    ///     reserved 1, 2;         // reserved numbers
    ///   }
    ///
    /// Memory ownership:
    /// - Caller owns the returned Enum and must call deinit()
    /// - All internal structures are allocated using the provided allocator
    /// - Parent message reference is borrowed
    pub fn parse(
        allocator: std.mem.Allocator,
        buf: *ParserBuffer,
        parent: ?ScopedName,
    ) Error!?Enum {
        try buf.skipSpaces();
        const offset = buf.offset;

        // Check for enum keyword
        if (!buf.checkStrWithSpaceAndShift("enum")) {
            return null;
        }

        // Parse enum name
        const name = try lex.ident(buf);
        try buf.openBracket();

        // Initialize containers for enum contents
        var opts = try std.ArrayList(Option).initCapacity(allocator, 1);
        var fields = try std.ArrayList(EnumField).initCapacity(allocator, 32);
        var reserved = try std.ArrayList(Reserved).initCapacity(allocator, 1);
        errdefer {
            opts.deinit(allocator);
            for (fields.items) |*field| field.deinit();
            fields.deinit(allocator);
            for (reserved.items) |*res| res.deinit();
            reserved.deinit(allocator);
        }

        // Handle empty enum
        const c = try buf.char();
        if (c == '}') {
            buf.offset += 1;
        } else {
            // Parse enum contents
            while (true) {
                try buf.skipSpaces();

                // Try parsing each possible enum element
                if (try Option.parse(buf)) |opt| {
                    try opts.append(allocator, opt);
                } else if (try Reserved.parse(allocator, buf)) |res| {
                    try reserved.append(allocator, res);
                } else if (try EnumField.parse(allocator, buf)) |field| {
                    try fields.append(allocator, field);
                }

                // Check for end of enum
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

        // Create scoped name
        const scoped: ScopedName = if (parent) |*p|
            try p.child(name)
        else
            try ScopedName.init(allocator, name);

        return Enum{
            .allocator = allocator,
            .start = offset,
            .end = buf.offset,
            .name = scoped,
            .options = opts,
            .fields = fields,
            .reserved = reserved,
        };
    }

    /// Free all memory associated with the enum
    pub fn deinit(self: *Enum) void {
        self.name.deinit();
        self.options.deinit(self.allocator);
        for (self.fields.items) |*field| {
            field.deinit();
        }
        self.fields.deinit(self.allocator);
        for (self.reserved.items) |*res| {
            res.deinit();
        }
        self.reserved.deinit(self.allocator);
    }

    /// Find a field by name
    pub fn findField(self: Enum, name: []const u8) ?EnumField {
        for (self.fields.items) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return field;
            }
        }
        return null;
    }

    /// Find a field by value
    pub fn findFieldByValue(self: Enum, value: i32) ?EnumField {
        for (self.fields.items) |field| {
            if (field.index == value) {
                return field;
            }
        }
        return null;
    }
};

test "parse basic enum field" {
    var buf = ParserBuffer.init("UNKNOWN = 0;");
    var result = try EnumField.parse(std.testing.allocator, &buf) orelse unreachable;
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.start);
    try std.testing.expectEqual(@as(usize, 12), result.end);
    try std.testing.expectEqualStrings("UNKNOWN", result.name);
    try std.testing.expectEqual(@as(i32, 0), result.index);
}

test "parse enum field with options" {
    var buf = ParserBuffer.init("EAA_RUNNING = 2 [(custom_option) = \"hello world\"];");
    var result = try EnumField.parse(std.testing.allocator, &buf) orelse unreachable;
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.start);
    try std.testing.expectEqual(@as(usize, 50), result.end);
    try std.testing.expectEqualStrings("EAA_RUNNING", result.name);
    try std.testing.expectEqual(@as(i32, 2), result.index);
    try std.testing.expectEqual(@as(usize, 1), (result.options orelse unreachable).items.len);
}

test "parse basic enum" {
    var buf = ParserBuffer.init("enum Test { UNKNOWN = 0; OTHER = 1; }");
    var result = try Enum.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer result.deinit();

    try std.testing.expectEqualStrings("Test", result.name.full);
    try std.testing.expectEqual(@as(usize, 2), result.fields.items.len);
    try std.testing.expectEqualStrings("UNKNOWN", result.fields.items[0].name);
    try std.testing.expectEqualStrings("OTHER", result.fields.items[1].name);
    try std.testing.expectEqual(@as(i32, 0), result.fields.items[0].index);
    try std.testing.expectEqual(@as(i32, 1), result.fields.items[1].index);
}

test "parse empty enum" {
    var buf = ParserBuffer.init("enum Test { }");
    var result = try Enum.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer result.deinit();

    try std.testing.expectEqualStrings("Test", result.name.full);
    try std.testing.expectEqual(@as(usize, 0), result.fields.items.len);
}

test "parse enum with reserved fields" {
    var buf = ParserBuffer.init(
        \\enum MonitorOptionType {
        \\    CTA_UNKNOWN = 0;
        \\    reserved 1;
        \\    CTA_ENABLED = 2;
        \\}
    );
    var result = try Enum.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer result.deinit();

    try std.testing.expectEqualStrings("MonitorOptionType", result.name.full);
    try std.testing.expectEqual(@as(usize, 2), result.fields.items.len);
    try std.testing.expectEqual(@as(usize, 1), result.reserved.items.len);
    try std.testing.expectEqualStrings("1", result.reserved.items[0].items.items[0]);
}

test "parse enum with hex values" {
    var buf = ParserBuffer.init(
        \\enum TronResourceCode {
        \\    BANDWIDTH = 0x00;
        \\    ENERGY = 0x01;
        \\    POWER = 0x02;
        \\}
    );
    var result = try Enum.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer result.deinit();

    try std.testing.expectEqualStrings("TronResourceCode", result.name.full);
    try std.testing.expectEqual(@as(usize, 3), result.fields.items.len);
    try std.testing.expectEqual(@as(i32, 0), result.fields.items[0].index);
    try std.testing.expectEqual(@as(i32, 1), result.fields.items[1].index);
    try std.testing.expectEqual(@as(i32, 2), result.fields.items[2].index);
}
