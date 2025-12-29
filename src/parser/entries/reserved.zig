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
// Created by ab, 11.06.2024

const std = @import("std");
const ParserBuffer = @import("buffer.zig").ParserBuffer;
const Error = @import("errors.zig").Error;
const lex = @import("lexems.zig");

/// Represents a reserved fields declaration in a protobuf message.
/// Can contain either field numbers or field names.
/// Format:
/// ```protobuf
/// message Foo {
///     reserved 2, 15, 9 to 11;        // reserve field numbers
///     reserved "foo", "bar";          // reserve field names
/// }
/// ```
pub const Reserved = struct {
    /// Starting position of the reserved declaration in the input buffer
    start: usize,
    /// Ending position of the reserved declaration in the input buffer
    end: usize,
    /// List of reserved items (either field numbers or field names)
    items: std.ArrayList([]const u8),

    allocator: std.mem.Allocator,

    /// Attempts to parse a reserved declaration from the given buffer.
    /// Returns null if the buffer doesn't start with a reserved declaration.
    ///
    /// Parses either field numbers (including ranges) or field names.
    /// Field numbers and names cannot be mixed in a single declaration.
    ///
    /// Errors:
    /// - Error.UnexpectedEOF: Buffer ends before declaration is complete
    /// - Error.InvalidCharacter: Invalid character in declaration
    /// - Error.OutOfMemory: Failed to allocate memory for items
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?Reserved {
        try buf.skipSpaces();

        const start = buf.offset;

        if (!buf.checkStrWithSpaceAndShift("reserved")) {
            return null;
        }

        var fields = try lex.parseRanges(allocator, buf);
        if (fields.items.len == 0) {
            fields.deinit(allocator);
            fields = try parseFieldNames(allocator, buf);
        }

        try buf.semicolon();

        return Reserved{
            .allocator = allocator,
            .start = start,
            .end = buf.offset,
            .items = fields,
        };
    }

    /// Frees the memory allocated for reserved items
    pub fn deinit(self: *Reserved) void {
        self.items.deinit(self.allocator);
    }
};

/// Parses a list of field names in quotes.
/// Format: "foo", "bar", "baz"
///
/// Returns an ArrayList of field names without quotes.
/// Returns empty ArrayList if no valid field names are found.
fn parseFieldNames(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!std.ArrayList([]const u8) {
    var res = try std.ArrayList([]const u8).initCapacity(allocator, 64);
    errdefer res.deinit(allocator);

    while (true) {
        try buf.skipSpaces();
        const name = try parseFieldName(buf) orelse return res;

        try res.append(allocator, name);

        const c = try buf.char();
        if (c == ',') {
            buf.offset += 1;
        } else {
            break;
        }
    }

    return res;
}

/// Parses a single quoted field name.
/// Accepts both single and double quotes.
/// Returns the field name without quotes, or null if input doesn't start with a quote.
fn parseFieldName(buf: *ParserBuffer) Error!?[]const u8 {
    const start = buf.offset;
    const c = try buf.char();
    if (c != '\"' and c != '\'') {
        return null;
    }
    const start_quote = c;
    buf.offset += 1;

    const res = try lex.ident(buf);
    const end_char = try buf.char();
    if (end_char != start_quote) {
        buf.offset = start;
        return null;
    }
    buf.offset += 1;

    return res;
}

test "parse field name" {
    // Test case 1: Double quoted field name
    {
        var buf = ParserBuffer.init("\"test\"");
        const res = try parseFieldName(&buf) orelse unreachable;
        try std.testing.expectEqualStrings("test", res);
    }

    // Test case 2: Single quoted field name
    {
        var buf = ParserBuffer.init("'test'");
        const res = try parseFieldName(&buf) orelse unreachable;
        try std.testing.expectEqualStrings("test", res);
    }
}

test "parse reserved" {
    // Test case 1: Reserved field numbers with range
    {
        var buf = ParserBuffer.init("reserved 2, 15, 9 to 11;");
        var res = try Reserved.parse(std.testing.allocator, &buf) orelse unreachable;
        defer res.deinit();

        try std.testing.expectEqual(3, res.items.items.len);
        try std.testing.expectEqualStrings("2", res.items.items[0]);
        try std.testing.expectEqualStrings("15", res.items.items[1]);
        try std.testing.expectEqualStrings("9 to 11", res.items.items[2]);
    }

    // Test case 2: Reserved field names
    {
        var buf = ParserBuffer.init("reserved \"foo\", \"bar\";");
        var res = try Reserved.parse(std.testing.allocator, &buf) orelse unreachable;
        defer res.deinit();

        try std.testing.expectEqual(2, res.items.items.len);
        try std.testing.expectEqualStrings("foo", res.items.items[0]);
        try std.testing.expectEqualStrings("bar", res.items.items[1]);
    }
}

test "single reserved" {
    // Test single field number reservation
    {
        var buf = ParserBuffer.init("reserved 1;");
        var res = try Reserved.parse(std.testing.allocator, &buf) orelse unreachable;
        defer res.deinit();

        try std.testing.expectEqual(1, res.items.items.len);
        try std.testing.expectEqualStrings("1", res.items.items[0]);
    }
}
