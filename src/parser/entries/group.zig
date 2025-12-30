//! Group parser module for Protocol Buffer definitions.
//! Handles parsing of the deprecated 'group' syntax in proto2.
//! Groups were replaced by nested messages in proto3, but must still be
//! parsed for backwards compatibility with proto2 files.

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

/// Represents a proto2 group definition.
/// Groups are a deprecated way to define nested message types.
/// Format: [optional|required|repeated] group GroupName = number { ... }
pub const Group = struct {
    /// Starting byte offset in source
    start: usize,
    /// Ending byte offset in source
    end: usize,

    /// Attempts to parse a group definition from the buffer.
    /// Returns null if the input does not start with a group.
    ///
    /// # Protocol Buffer Group Syntax
    /// ```proto
    /// [optional|required|repeated] group GroupName = number {
    ///   // fields...
    /// }
    /// ```
    ///
    /// # Errors
    /// Returns error on invalid syntax or buffer overflow
    pub fn parse(buf: *ParserBuffer) Error!?Group {
        const offset = buf.offset;
        try buf.skipSpaces();

        // Parse optional modifiers (optional, required, repeated)
        _ = buf.checkStrWithSpaceAndShift("optional");
        try buf.skipSpaces();
        _ = buf.checkStrWithSpaceAndShift("required");
        try buf.skipSpaces();
        _ = buf.checkStrWithSpaceAndShift("repeated");
        try buf.skipSpaces();

        // Check if this is actually a group
        if (!buf.checkStrWithSpaceAndShift("group")) {
            buf.offset = offset;
            return null;
        }

        // Parse group name and number
        _ = try lex.ident(buf);
        _ = try buf.assignment();
        _ = try lex.intLit(buf);

        // Skip the group body by counting braces
        var brace_depth: usize = 0;
        while (true) {
            const c = try buf.shouldShiftNext();
            switch (c) {
                '{' => brace_depth += 1,
                '}' => {
                    brace_depth -= 1;
                    if (brace_depth == 0) break;
                },
                else => {},
            }
        }

        return Group{ .start = offset, .end = buf.offset };
    }
};

test "group parsing - basic group" {
    var buf = ParserBuffer.init(
        \\group Result = 1 {
        \\  required string url = 2;
        \\  optional string title = 3;
        \\}
    );
    const group = try Group.parse(&buf) orelse unreachable;
    try std.testing.expect(group.end > group.start);
}

test "group parsing - with modifiers" {
    // Test optional group
    {
        var buf = ParserBuffer.init("optional group OptionalGroup = 1 { required int32 id = 2; }");
        const group = try Group.parse(&buf) orelse unreachable;
        try std.testing.expect(group.end > group.start);
    }

    // Test required group
    {
        var buf = ParserBuffer.init("required group RequiredGroup = 3 { optional string name = 4; }");
        const group = try Group.parse(&buf) orelse unreachable;
        try std.testing.expect(group.end > group.start);
    }

    // Test repeated group
    {
        var buf = ParserBuffer.init("repeated group RepeatedGroup = 5 { required bool flag = 6; }");
        const group = try Group.parse(&buf) orelse unreachable;
        try std.testing.expect(group.end > group.start);
    }
}

test "group parsing - nested groups" {
    var buf = ParserBuffer.init(
        \\group Outer = 1 {
        \\  required string name = 2;
        \\  optional group Inner = 3 {
        \\    required int32 value = 4;
        \\  }
        \\}
    );
    const group = try Group.parse(&buf) orelse unreachable;
    try std.testing.expect(group.end > group.start);
}

test "group parsing - not a group" {
    var buf = ParserBuffer.init("message NotAGroup { required string name = 1; }");
    const result = try Group.parse(&buf);
    try std.testing.expect(result == null);
}
