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

/// Represents a protobuf option declaration.
/// Options can appear as standalone declarations or in lists.
/// Format:
/// ```protobuf
/// option java_package = "com.example.foo";
/// message Foo {
///     string name = 1 [(custom) = "value", deprecated = true];
/// }
/// ```
pub const Option = struct {
    /// Starting position of the option declaration in the input buffer
    start: usize,
    /// Ending position of the option declaration in the input buffer
    end: usize,
    /// Option name, can include custom scope (e.g., "java_package" or "(custom).field")
    name: []const u8,
    /// Option value (string, number, or boolean)
    value: []const u8,

    /// Attempts to parse a standalone option declaration from the given buffer.
    /// Returns null if the buffer doesn't start with an option declaration.
    ///
    /// Errors:
    /// - Error.UnexpectedEOF: Buffer ends before declaration is complete
    /// - Error.InvalidCharacter: Invalid character in option declaration
    /// - Error.InvalidOptionName: Malformed option name
    pub fn parse(buf: *ParserBuffer) Error!?Option {
        try buf.skipSpaces();

        const start = buf.offset;

        if (!buf.checkStrWithSpaceAndShift("option")) {
            return null;
        }

        const name = try optionName(buf);
        try buf.assignment();
        const value = try lex.constant(buf);

        try buf.semicolon();

        return Option{
            .start = start,
            .end = buf.offset,
            .name = name,
            .value = value,
        };
    }

    /// Attempts to parse a list of options enclosed in square brackets.
    /// Format: [option1 = value1, option2 = value2]
    /// Returns null if the buffer doesn't start with '['
    ///
    /// Caller owns the returned ArrayList and must call deinit.
    ///
    /// Errors:
    /// - Error.UnexpectedEOF: Buffer ends before list is complete
    /// - Error.InvalidCharacter: Invalid character in option list
    /// - Error.InvalidOptionName: Malformed option name
    /// - Error.OutOfMemory: Failed to allocate memory for list
    pub fn parseList(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?std.ArrayList(Option) {
        try buf.skipSpaces();
        if (try buf.char() != '[') {
            return null;
        }
        buf.offset += 1;
        try buf.skipSpaces();

        if (try buf.char() == ']') {
            buf.offset += 1;
            return try std.ArrayList(Option).initCapacity(allocator, 32);
        }

        var res = try std.ArrayList(Option).initCapacity(allocator, 32);
        errdefer res.deinit(allocator);

        while (true) {
            const start = buf.offset;
            const name = try optionName(buf);
            try buf.assignment();
            const value = try lex.constant(buf);

            try res.append(allocator, Option{
                .start = start,
                .end = buf.offset,
                .name = name,
                .value = value,
            });

            try buf.skipSpaces();
            const c = try buf.char() orelse return Error.UnexpectedEOF;
            switch (c) {
                ',' => {
                    buf.offset += 1;
                    continue;
                },
                ']' => {
                    buf.offset += 1;
                    return res;
                },
                else => return Error.InvalidCharacter,
            }
        }
    }
};

/// Parses a complete option name, which can include multiple parts
/// separated by dots and custom scopes in parentheses.
/// Format: part1.part2.(custom.scope).part3
fn optionName(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start = buf.offset;
    while (true) {
        try optionNamePart(buf);
        if (try buf.char() != '.') {
            break;
        }
        buf.offset += 1;
    }

    return buf.buf[start..buf.offset];
}

/// Parses a single part of an option name.
/// Can be either a simple identifier or a custom scope in parentheses.
fn optionNamePart(buf: *ParserBuffer) Error!void {
    const c = try buf.char() orelse return Error.InvalidOptionName;
    switch (c) {
        '(' => {
            buf.offset += 1;
            if (try buf.char() == '.') {
                buf.offset += 1;
            }
            _ = try lex.fullIdent(buf);
            if (!try buf.checkAndShift(')')) {
                return Error.InvalidOptionName;
            }
        },
        else => {
            _ = try lex.ident(buf);
        },
    }
}

test "basic option" {
    // Test standalone option parsing
    var buf = ParserBuffer.init("option java_package = \"com.example.foo\";");

    const opt = try Option.parse(&buf) orelse unreachable;
    try std.testing.expectEqualStrings("java_package", opt.name);
    try std.testing.expectEqualStrings("\"com.example.foo\"", opt.value);
    try std.testing.expectEqual(0, opt.start);
    try std.testing.expectEqual(40, opt.end);
}

test "option list" {
    // Test multiple options in a list
    var buf = ParserBuffer.init("[java_package = \"com.example.foo\", another = true]");

    var opts = try Option.parseList(std.testing.allocator, &buf) orelse unreachable;
    defer opts.deinit(std.testing.allocator);

    try std.testing.expectEqual(2, opts.items.len);

    try std.testing.expectEqualStrings("java_package", opts.items[0].name);
    try std.testing.expectEqualStrings("\"com.example.foo\"", opts.items[0].value);

    try std.testing.expectEqualStrings("another", opts.items[1].name);
    try std.testing.expectEqualStrings("true", opts.items[1].value);
}

test "float options" {
    // Test floating point option values
    var buf = ParserBuffer.init("[default = 51.5]");

    var opts = try Option.parseList(std.testing.allocator, &buf) orelse unreachable;
    defer opts.deinit(std.testing.allocator);

    try std.testing.expectEqual(1, opts.items.len);
    try std.testing.expectEqualStrings("default", opts.items[0].name);
    try std.testing.expectEqualStrings("51.5", opts.items[0].value);
}

test "empty string options" {
    // Test empty string option values
    var buf = ParserBuffer.init("[default = \"\"]");

    var opts = try Option.parseList(std.testing.allocator, &buf) orelse unreachable;
    defer opts.deinit(std.testing.allocator);

    try std.testing.expectEqual(1, opts.items.len);
    try std.testing.expectEqualStrings("default", opts.items[0].name);
    try std.testing.expectEqualStrings("\"\"", opts.items[0].value);
}

test "message literal option" {
    // Test option with message literal value (features)
    var buf = ParserBuffer.init("[features = { field_presence: EXPLICIT }]");

    var opts = try Option.parseList(std.testing.allocator, &buf) orelse unreachable;
    defer opts.deinit(std.testing.allocator);

    try std.testing.expectEqual(1, opts.items.len);
    try std.testing.expectEqualStrings("features", opts.items[0].name);
    try std.testing.expectEqualStrings("{ field_presence: EXPLICIT }", opts.items[0].value);
}
