//! A lexical analyzer for Protocol Buffers (protobuf) file format.
//! This module handles parsing of various protobuf literals, identifiers,
//! and field types according to the protobuf specification.

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
const Error = @import("errors.zig").Error;
const ParserBuffer = @import("buffer.zig").ParserBuffer;
const ScopedName = @import("scoped-name.zig").ScopedName;

/// Parse a string literal. Handles both single and double quotes.
pub fn strLit(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start_offset = buf.offset;
    const open = try buf.shouldShiftNext();
    if (open != '"' and open != '\'') {
        return Error.InvalidStringLiteral;
    }
    try strLitSingle(buf, open);
    const end_offset = buf.offset;

    return buf.buf[(start_offset + 1)..(end_offset - 1)];
}

fn strLitSingle(buf: *ParserBuffer, close: u8) Error!void {
    while (true) {
        const c = try buf.shouldShiftNext();
        if (c == close) return;

        if (c == '\\') {
            try parseEscapeSequence(buf);
        } else if (c == 0 or c == '\n') {
            return Error.InvalidStringLiteral;
        }
    }
}

fn parseEscapeSequence(buf: *ParserBuffer) Error!void {
    const next = try buf.shouldShiftNext();
    switch (next) {
        // hexEscape = '\' ( "x" | "X" ) hexDigit [ hexDigit ]
        'x', 'X' => {
            while (std.ascii.isHex(try buf.shouldShiftNext())) {}
            buf.offset -= 1;
        },
        // octEscape = '\' octalDigit [ octalDigit [ octalDigit ] ]
        '0'...'7' => {
            while (isOctalDigit(try buf.shouldShiftNext())) {}
            buf.offset -= 1;
        },
        // charEscape = '\' ( "a" | "b" | "f" | "n" | "r" | "t" | "v" | '\' | "'" | '"' )
        'a', 'b', 'f', 'n', 'r', 't', 'v', '\\', '\'', '"', '?' => {},
        // unicodeEscape = '\' "u" hexDigit hexDigit hexDigit hexDigit
        'u' => try parseUnicodeEscape(buf, 4),
        // unicodeLongEscape = '\' "U" [ long unicode format ]
        'U' => try parseExtendedUnicodeEscape(buf),
        else => return Error.InvalidEscape,
    }
}

fn parseUnicodeEscape(buf: *ParserBuffer, count: usize) Error!void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (!std.ascii.isHex(try buf.shouldShiftNext())) {
            return Error.InvalidUnicodeEscape;
        }
    }
}

fn parseExtendedUnicodeEscape(buf: *ParserBuffer) Error!void {
    if (!try buf.checkAndShift('0') or !try buf.checkAndShift('0')) {
        return Error.InvalidUnicodeEscape;
    }

    const next = try buf.shouldShiftNext();
    switch (next) {
        '0' => try parseUnicodeEscape(buf, 5),
        '1' => {
            if (!try buf.checkAndShift('0')) return Error.InvalidUnicodeEscape;
            try parseUnicodeEscape(buf, 4);
        },
        else => return Error.InvalidUnicodeEscape,
    }
}

/// Parse a simple identifier
pub fn ident(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start_offset = buf.offset;
    const c = try buf.shouldShiftNext();
    if (c != '_' and !std.ascii.isAlphabetic(c)) {
        return Error.IdentifierShouldStartWithLetter;
    }

    while (true) {
        const n = try buf.char() orelse break;
        if (!isIdentifierChar(n)) break;
        buf.offset += 1;
    }

    return buf.buf[start_offset..buf.offset];
}

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphabetic(c) or std.ascii.isDigit(c) or c == '_';
}

/// Parse a fully scoped name
pub fn fullScopedName(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!ScopedName {
    const name = try fullIdent(buf);
    if (std.mem.startsWith(u8, name, ".")) {
        return ScopedName.init(allocator, name);
    } else {
        const full = try std.mem.concat(allocator, u8, &[_][]const u8{ ".", name });
        var res = try ScopedName.init(allocator, full);
        res.full_owned = true;
        return res;
    }
}

/// Parse a full identifier (including dots)
pub fn fullIdent(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start_offset = buf.offset;

    while (true) {
        const part = try ident(buf);
        _ = part;

        const next = try buf.char() orelse break;
        if (next != '.') break;
        buf.offset += 1;
    }

    return buf.buf[start_offset..buf.offset];
}

/// Parse an integer literal
pub fn intLit(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start = buf.offset;

    if (try buf.char() == '-') {
        buf.offset += 1;
        try buf.skipSpaces();
    }

    const c = try buf.shouldShiftNext();
    switch (c) {
        '1'...'9' => try parseDecimalDigits(buf),
        '0' => try parseOctalOrHex(buf),
        else => return Error.InvalidIntegerLiteral,
    }

    return buf.buf[start..buf.offset];
}

fn parseDecimalDigits(buf: *ParserBuffer) Error!void {
    while (true) {
        const n = try buf.char() orelse break;
        if (!std.ascii.isDigit(n)) break;
        buf.offset += 1;
    }
}

fn parseOctalOrHex(buf: *ParserBuffer) Error!void {
    const x = try buf.char() orelse return;
    if (x == 'x' or x == 'X') {
        buf.offset += 1;
        while (true) {
            const n = try buf.char() orelse break;
            if (!std.ascii.isHex(n)) break;
            buf.offset += 1;
        }
    } else {
        while (true) {
            const n = try buf.char() orelse break;
            if (!isOctalDigit(n)) break;
            buf.offset += 1;
        }
    }
}

/// Parse a constant value
pub fn constant(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start_offset = buf.offset;

    // Try parsing as identifier
    if (fullIdent(buf)) |parsedIdent| {
        return parsedIdent;
    } else |_| {}
    buf.offset = start_offset;

    // Try parsing as float with optional sign
    {
        const sign = try buf.char();
        if (sign == '+' or sign == '-') buf.offset += 1;
        if (floatLit(buf)) |res| {
            if (res.len > 0) return buf.buf[start_offset..buf.offset];
        } else |_| {}
    }
    buf.offset = start_offset;

    // Try parsing as integer with optional sign
    {
        const sign = try buf.char();
        if (sign == '+' or sign == '-') buf.offset += 1;
        if (intLit(buf)) |res| {
            if (res.len > 0) return buf.buf[start_offset..buf.offset];
        } else |_| {}
    }
    buf.offset = start_offset;

    // Try parsing as boolean
    if (boolLit(buf)) |res| {
        if (res.len > 0) return buf.buf[start_offset..buf.offset];
    } else |_| {}

    // Try parsing as string
    if (strLit(buf)) |_| {
        return buf.buf[start_offset..buf.offset];
    } else |_| {}
    buf.offset = start_offset;

    return Error.InvalidConst;
}

fn decimals(buf: *ParserBuffer) Error!void {
    try parseDecimalDigits(buf);
}

fn exponent(buf: *ParserBuffer) Error!void {
    const c = try buf.char();
    if (c != 'e' and c != 'E') return;

    buf.offset += 1;
    try buf.skipSpaces();

    const sign = try buf.char();
    if (sign == '+' or sign == '-') {
        buf.offset += 1;
        try buf.skipSpaces();
    }

    try decimals(buf);
}

fn floatLit(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start = buf.offset;

    if (try buf.char() == '-') {
        buf.offset += 1;
    }
    try buf.skipSpaces();

    // Handle special values
    if (buf.checkStrAndShift("inf")) return buf.buf[start..buf.offset];
    if (buf.checkStrAndShift("nan")) return buf.buf[start..buf.offset];

    try buf.skipSpaces();
    const c = try buf.char();

    if (c == '.') {
        buf.offset += 1;
        try decimals(buf);
        try exponent(buf);
    } else {
        try decimals(buf);
        const next_c = try buf.char();
        if (next_c == '.') {
            buf.offset += 1;
            try decimals(buf);
            try exponent(buf);
        } else {
            try exponent(buf);
        }
    }

    const end = try buf.char();
    if (end != 'x' and end != 'X') {
        return buf.buf[start..buf.offset];
    }

    return Error.InvalidFloat;
}

fn boolLit(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();
    const start = buf.offset;

    if (buf.checkStrAndShift("true")) return buf.buf[start..buf.offset];
    if (buf.checkStrAndShift("false")) return buf.buf[start..buf.offset];

    return Error.InvalidBooleanLiteral;
}

fn isOctalDigit(c: u8) bool {
    return c >= '0' and c <= '7';
}

const base_types = [_][]const u8{ "double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string", "bytes" };

/// Parse a field type (base type or message type)
pub fn fieldType(buf: *ParserBuffer) Error![]const u8 {
    try buf.skipSpaces();

    // Check for base types first
    for (base_types) |base_type| {
        if (buf.checkStrWithSpaceAndShift(base_type)) {
            return base_type;
        }
    }

    return try messageType(buf);
}

fn messageType(buf: *ParserBuffer) Error![]const u8 {
    const start = buf.offset;
    const c = try buf.char();
    if (c == '.') {
        buf.offset += 1;
    }

    while (true) {
        _ = try ident(buf);
        const iter_c = try buf.char();
        if (iter_c != '.') break;
        buf.offset += 1;
    }

    return buf.buf[start..buf.offset];
}

/// Parse ranges in the format "2", "15", "9 to 11"
pub fn parseRanges(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!std.ArrayList([]const u8) {
    var res = try std.ArrayList([]const u8).initCapacity(allocator, 32);
    errdefer res.deinit(allocator);

    while (true) {
        try buf.skipSpaces();
        const range = try parseRange(buf) orelse return res;

        try res.append(allocator, range);

        const c = try buf.char();
        if (c == ',') {
            buf.offset += 1;
        } else {
            break;
        }
    }

    return res;
}

fn parseRange(buf: *ParserBuffer) Error!?[]const u8 {
    try buf.skipSpaces();
    const start = buf.offset;
    const c = try buf.char();
    if (!std.ascii.isDigit(c orelse 0)) {
        return null;
    }
    _ = try intLit(buf);
    try buf.skipSpaces();
    if (buf.checkStrWithSpaceAndShift("to")) {
        try buf.skipSpaces();
        if (!buf.checkStrAndShift("max")) {
            _ = try intLit(buf);
        }
    }

    return buf.buf[start..buf.offset];
}

test "str literals" {
    var buf = ParserBuffer.init(" \"hello\" ");
    try std.testing.expectEqualStrings("hello", try strLit(&buf));

    buf = ParserBuffer.init(" 'hello' ");
    try std.testing.expectEqualStrings("hello", try strLit(&buf));

    buf = ParserBuffer.init(" \"hello\\\"\" ");
    try std.testing.expectEqualStrings("hello\\\"", try strLit(&buf));

    buf = ParserBuffer.init("'\xDEAD'");
    try std.testing.expectEqualStrings("\xDEAD", try strLit(&buf));
}

test "ident" {
    var buf = ParserBuffer.init("hello ");
    try std.testing.expectEqualStrings("hello", try ident(&buf));

    buf = ParserBuffer.init("hello123 ");
    try std.testing.expectEqualStrings("hello123", try ident(&buf));

    buf = ParserBuffer.init("hello_123 ");
    try std.testing.expectEqualStrings("hello_123", try ident(&buf));

    buf = ParserBuffer.init("hello_123_ ");
    try std.testing.expectEqualStrings("hello_123_", try ident(&buf));

    buf = ParserBuffer.init("1hello_123_ ");
    try std.testing.expectError(Error.IdentifierShouldStartWithLetter, ident(&buf));
}

test "fullIdent" {
    var buf = ParserBuffer.init("hello ");
    try std.testing.expectEqualStrings("hello", try fullIdent(&buf));

    buf = ParserBuffer.init("hello123.world ");
    try std.testing.expectEqualStrings("hello123.world", try fullIdent(&buf));

    buf = ParserBuffer.init("hello_123.world ");
    try std.testing.expectEqualStrings("hello_123.world", try fullIdent(&buf));

    buf = ParserBuffer.init("hello_123_.world ");
    try std.testing.expectEqualStrings("hello_123_.world", try fullIdent(&buf));

    buf = ParserBuffer.init("hello123.456 ");
    try std.testing.expectError(Error.IdentifierShouldStartWithLetter, fullIdent(&buf));
}

test "int lit" {
    var buf = ParserBuffer.init("123 ");
    try std.testing.expectEqualStrings("123", try intLit(&buf));

    buf = ParserBuffer.init("0x123 ");
    try std.testing.expectEqualStrings("0x123", try intLit(&buf));

    buf = ParserBuffer.init("0X123 ");
    try std.testing.expectEqualStrings("0X123", try intLit(&buf));

    buf = ParserBuffer.init("01239 ");
    try std.testing.expectEqualStrings("0123", try intLit(&buf));

    buf = ParserBuffer.init("0 ");
    try std.testing.expectEqualStrings("0", try intLit(&buf));

    buf = ParserBuffer.init("-123 ");
    try std.testing.expectEqualStrings("-123", try intLit(&buf));
}

test "float lit" {
    var inf = ParserBuffer.init("inf ");
    try std.testing.expectEqualStrings("inf", try floatLit(&inf));

    var nan = ParserBuffer.init("nan ");
    try std.testing.expectEqualStrings("nan", try floatLit(&nan));

    var buf = ParserBuffer.init(".456 ");
    try std.testing.expectEqualStrings(".456", try floatLit(&buf));

    buf = ParserBuffer.init(".1e10 ");
    try std.testing.expectEqualStrings(".1e10", try floatLit(&buf));

    buf = ParserBuffer.init(".0 ");
    try std.testing.expectEqualStrings(".0", try floatLit(&buf));

    buf = ParserBuffer.init("123.456 ");
    try std.testing.expectEqualStrings("123.456", try floatLit(&buf));
}

test "field type" {
    var buf = ParserBuffer.init("float64 name");
    const mt = try messageType(&buf);
    try std.testing.expectEqualStrings("float64", mt);
}

test "message type" {
    var buf = ParserBuffer.init(".complex.message.Type name");
    const mt = try messageType(&buf);
    try std.testing.expectEqualStrings(".complex.message.Type", mt);
}

test "parse range" {
    var buf = ParserBuffer.init("1 to 2");
    try std.testing.expectEqualStrings("1 to 2", try parseRange(&buf) orelse unreachable);

    buf = ParserBuffer.init("9 to max");
    try std.testing.expectEqualStrings("9 to max", try parseRange(&buf) orelse unreachable);

    buf = ParserBuffer.init("9,12");
    try std.testing.expectEqualStrings("9", try parseRange(&buf) orelse unreachable);
}

test "parse ranges" {
    var buf = ParserBuffer.init("2, 15, 9 to 11");
    var res = try parseRanges(std.testing.allocator, &buf);
    try std.testing.expectEqual(res.items.len, 3);
    try std.testing.expectEqualStrings("2", res.items[0]);
    try std.testing.expectEqualStrings("15", res.items[1]);
    try std.testing.expectEqualStrings("9 to 11", res.items[2]);
    res.deinit(std.testing.allocator);
}

test "parse x str" {
    var buf = ParserBuffer.init("\"\\xfe\"");
    const c = try strLit(&buf);
    try std.testing.expectEqualStrings("\\xfe", c);
}

test "parse hex const" {
    var buf = ParserBuffer.init("0xFFFFFFFF");
    const c = try constant(&buf);
    try std.testing.expectEqualStrings("0xFFFFFFFF", c);
}

test "trigraph const" {
    var buf = ParserBuffer.init("\"? \\? ?? \\?? \\??? ??/ ?\\?-\"");
    const c = try constant(&buf);
    try std.testing.expectEqualStrings("\"? \\? ?? \\?? \\??? ??/ ?\\?-\"", c);
}
