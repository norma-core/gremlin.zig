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
// Created by ab, 10.06.2024

const std = @import("std");
const ParserBuffer = @import("buffer.zig").ParserBuffer;
const Error = @import("errors.zig").Error;

/// List of valid protobuf syntax versions with both single and double quote variants.
/// Currently supports proto2 and proto3 versions.
const valid_versions = [_][]const u8{
    "'proto3'",
    "\"proto3\"",
    "'proto2'",
    "\"proto2\"",
};

/// Represents a syntax declaration in a protobuf file.
/// Format: syntax = "proto2"|"proto3";
pub const Syntax = struct {
    /// Starting position of the syntax declaration in the input buffer
    start: usize,
    /// Ending position of the syntax declaration in the input buffer
    end: usize,

    /// Attempts to parse a syntax declaration from the given buffer.
    /// Returns null if the buffer doesn't start with a syntax declaration.
    /// Returns error if the syntax declaration is malformed.
    ///
    /// Expected format:
    /// ```protobuf
    /// syntax = "proto3";
    /// ```
    ///
    /// Errors:
    /// - Error.AssignmentExpected: Missing '=' after 'syntax'
    /// - Error.UnexpectedEOF: Unexpected end of file
    /// - Error.InvalidSyntaxVersion: Invalid protobuf version
    pub fn parse(buf: *ParserBuffer) Error!?Syntax {
        const offset = buf.offset;
        if (!buf.checkStrAndShift("syntax")) {
            return null;
        }
        try buf.assignment();
        for (valid_versions) |version| {
            if (buf.checkStrAndShift(version)) {
                try buf.semicolon();
                return Syntax{
                    .start = offset,
                    .end = buf.offset,
                };
            }
        }
        return Error.InvalidSyntaxVersion;
    }
};

test "syntax parsing" {
    // Test case 1: Invalid syntax keyword
    {
        var buf = ParserBuffer{ .buf = "synz;" };
        try std.testing.expectEqual(null, try Syntax.parse(&buf));
        try std.testing.expectEqual(0, buf.offset);
    }

    // Test case 2: Different keyword (package)
    {
        var buf = ParserBuffer{ .buf = "package test;" };
        try std.testing.expectEqual(null, try Syntax.parse(&buf));
        try std.testing.expectEqual(0, buf.offset);
    }

    // Test case 3: Valid proto3 with single quotes
    {
        var buf = ParserBuffer{ .buf = "syntax = 'proto3';" };
        try std.testing.expectEqual(
            Syntax{ .start = 0, .end = 18 },
            try Syntax.parse(&buf),
        );
        try std.testing.expectEqual(18, buf.offset);
    }

    // Test case 4: Valid proto3 with double quotes
    {
        var buf = ParserBuffer{ .buf = "syntax = \"proto3\";" };
        try std.testing.expectEqual(
            Syntax{ .start = 0, .end = 18 },
            try Syntax.parse(&buf),
        );
        try std.testing.expectEqual(18, buf.offset);
    }

    // Test case 5: Missing assignment operator
    {
        var buf = ParserBuffer{ .buf = "syntax proto3;" };
        try std.testing.expectError(Error.AssignmentExpected, Syntax.parse(&buf));
    }

    // Test case 6: Missing semicolon
    {
        var buf = ParserBuffer{ .buf = "syntax = 'proto3'" };
        try std.testing.expectError(Error.UnexpectedEOF, Syntax.parse(&buf));
    }

    // Test case 7: Invalid protobuf version
    {
        var buf = ParserBuffer{ .buf = "syntax = 'proto4';" };
        try std.testing.expectError(Error.InvalidSyntaxVersion, Syntax.parse(&buf));
    }
}
