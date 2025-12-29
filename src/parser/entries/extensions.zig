//! Extensions module provides parsing capabilities for Protocol Buffers v2 extension ranges.
//! Extensions allow proto2 messages to be extended with new fields outside the normal
//! numeric range. This module handles parsing the 'extensions' declaration syntax.

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

/// Extensions represents a proto2 extensions declaration, which defines what field numbers
/// are available for extension fields. The declaration can include individual numbers
/// and ranges (e.g., "extensions 4, 20 to 30;").
pub const Extensions = struct {
    allocator: std.mem.Allocator,
    /// Offset in the source where this extensions declaration begins
    start: usize,
    /// Offset in the source where this extensions declaration ends
    end: usize,
    /// List of extension ranges, where each item is either a single number
    /// or a range in the format "X to Y"
    items: std.ArrayList([]const u8),

    /// Parse an extensions declaration from the given buffer.
    /// Returns null if the buffer doesn't start with the "extensions" keyword.
    ///
    /// Format examples:
    ///   extensions 4;
    ///   extensions 2, 15, 9 to 11;
    ///
    /// Memory ownership:
    /// - Caller owns the returned Extensions and must call deinit()
    /// - The items ArrayList and its contents are allocated using the provided allocator
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?Extensions {
        try buf.skipSpaces();

        // Remember where this declaration starts
        const start = buf.offset;

        // Check if this is an extensions declaration
        if (!buf.checkStrWithSpaceAndShift("extensions")) {
            return null;
        }

        // Parse the comma-separated list of ranges
        var fields = try lex.parseRanges(allocator, buf);
        errdefer fields.deinit(allocator);

        // Expect a semicolon at the end
        try buf.semicolon();

        return Extensions{
            .allocator = allocator,
            .start = start,
            .end = buf.offset,
            .items = fields,
        };
    }

    /// Free all memory associated with the Extensions.
    /// Must be called when the Extensions is no longer needed.
    pub fn deinit(self: *Extensions) void {
        // Free each range string and the ArrayList itself
        self.items.deinit(self.allocator);
    }

    /// Returns true if this extensions declaration contains the given field number
    pub fn containsField(self: Extensions, field_number: usize) bool {
        for (self.items.items) |range| {
            if (isSingleNumber(range)) {
                const num = std.fmt.parseInt(usize, range, 10) catch continue;
                if (num == field_number) return true;
            } else {
                // Parse "X to Y" range
                var parts = std.mem.splitSequence(u8, range, " to ");
                const start_str = parts.next() orelse continue;
                const end_str = parts.next() orelse continue;

                const start = std.fmt.parseInt(usize, start_str, 10) catch continue;
                const end = std.fmt.parseInt(usize, end_str, 10) catch continue;

                if (field_number >= start and field_number <= end) return true;
            }
        }
        return false;
    }

    /// Returns true if the given range string represents a single number
    /// rather than a range (i.e., doesn't contain " to ")
    fn isSingleNumber(range: []const u8) bool {
        return std.mem.indexOf(u8, range, " to ") == null;
    }
};

test "parse basic extensions" {
    var buf = ParserBuffer.init("extensions 2, 15, 9 to 11;");
    var res = try Extensions.parse(std.testing.allocator, &buf) orelse {
        try std.testing.expect(false); // Should not reach here
        unreachable;
    };
    defer res.deinit();

    try std.testing.expectEqual(@as(usize, 3), res.items.items.len);
    try std.testing.expectEqualStrings("2", res.items.items[0]);
    try std.testing.expectEqualStrings("15", res.items.items[1]);
    try std.testing.expectEqualStrings("9 to 11", res.items.items[2]);
}

test "parse invalid extensions" {
    // Missing semicolon
    {
        var buf = ParserBuffer.init("extensions 2, 15");
        try std.testing.expectError(Error.UnexpectedEOF, Extensions.parse(std.testing.allocator, &buf));
    }
}

test "check field containment" {
    var buf = ParserBuffer.init("extensions 2, 15, 9 to 11;");
    var extensions = try Extensions.parse(std.testing.allocator, &buf) orelse unreachable;
    defer extensions.deinit();

    // Test single numbers
    try std.testing.expect(extensions.containsField(2));
    try std.testing.expect(extensions.containsField(15));
    try std.testing.expect(!extensions.containsField(3));

    // Test range
    try std.testing.expect(extensions.containsField(9));
    try std.testing.expect(extensions.containsField(10));
    try std.testing.expect(extensions.containsField(11));
    try std.testing.expect(!extensions.containsField(12));
}
