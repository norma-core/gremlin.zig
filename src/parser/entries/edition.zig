//! Edition parser module for Protocol Buffer text format.
//! Parses edition declarations like `edition = "2018";` which specify
//! the Protocol Buffer edition being used.
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

/// Represents a parsed edition declaration from Protocol Buffer text format.
/// Tracks the source positions for error reporting and stores the edition value.
pub const Edition = struct {
    /// Starting byte offset in the source text
    start: usize,
    /// Ending byte offset in the source text
    end: usize,
    /// The edition string value (e.g. "2018")
    edition: []const u8,

    /// Attempts to parse an edition declaration from the given buffer.
    /// Returns null if no edition declaration is found at the current position.
    ///
    /// Format: edition = "2018";
    ///
    /// # Errors
    /// Returns an error if:
    /// - The assignment operator (=) is missing or malformed
    /// - The edition string is not a valid string literal
    /// - The semicolon is missing
    pub fn parse(buf: *ParserBuffer) Error!?Edition {
        try buf.skipSpaces();
        const offset = buf.offset;

        if (!buf.checkStrAndShift("edition")) {
            return null;
        }

        try buf.assignment();
        const edition_value = try lex.strLit(buf);
        try buf.semicolon();

        return Edition{
            .start = offset,
            .end = buf.offset,
            .edition = edition_value,
        };
    }
};

test "edition parsing" {
    var buf = ParserBuffer.init("edition = \"2018\";");
    try std.testing.expectEqualStrings("2018", (try Edition.parse(&buf) orelse unreachable).edition);
}
