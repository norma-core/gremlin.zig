//! ParserBuffer provides utilities for parsing text content with common operations
//! like handling whitespace, comments, and basic syntax elements. It's particularly
//! useful for implementing parsers for domain-specific languages or file formats.

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
const Error = @import("errors.zig").Error;
const whitespace_chars = [_]u8{ ' ', '\t', '\n', '\r' };

pub const ParserBuffer = struct {
    /// The underlying buffer containing the text to be parsed
    buf: []const u8,
    /// Current parsing position within the buffer
    offset: usize = 0,
    /// Optional allocator used for file-based buffers
    allocator: ?std.mem.Allocator = null,

    /// Initialize a new ParserBuffer with the given text content
    pub fn init(buf: []const u8) ParserBuffer {
        return ParserBuffer{ .buf = buf };
    }

    /// Initialize a ParserBuffer by reading the entire contents of a file
    /// Caller owns the memory and must call deinit()
    pub fn initFile(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !ParserBuffer {
        var file = try std.Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only });
        defer file.close(io);
        var file_reader = file.reader(io, &.{});
        const buf = try file_reader.interface.allocRemaining(allocator, .unlimited);
        return ParserBuffer{ .buf = buf, .allocator = allocator };
    }

    /// Free the buffer if it was allocated
    pub fn deinit(self: *ParserBuffer) void {
        if (self.allocator) |a| {
            a.free(self.buf);
        }
    }

    /// Check if the buffer starts with the given prefix at the current offset
    /// If it matches, advance the offset past the prefix
    pub fn checkStrAndShift(self: *ParserBuffer, prefix: []const u8) bool {
        if (std.mem.startsWith(u8, self.buf[self.offset..], prefix)) {
            self.offset += prefix.len;
            return true;
        }
        return false;
    }

    /// Check if the buffer starts with the given prefix followed by whitespace
    /// If it matches, advance the offset past both the prefix and the whitespace
    pub fn checkStrWithSpaceAndShift(self: *ParserBuffer, prefix: []const u8) bool {
        const matches_prefix = std.mem.startsWith(u8, self.buf[self.offset..], prefix);
        if (!matches_prefix) return false;

        const has_space_after = self.offset + prefix.len < self.buf.len and
            std.mem.indexOfScalar(u8, &whitespace_chars, self.buf[self.offset + prefix.len]) != null;
        if (!has_space_after) return false;

        self.offset += prefix.len + 1;
        return true;
    }

    /// Skip over any whitespace and comments at the current position
    /// Handles both single-line (//) and multi-line (/* */) comments
    pub fn skipSpaces(self: *ParserBuffer) Error!void {
        // Skip whitespace characters
        while (self.offset < self.buf.len and
            std.mem.indexOfScalar(u8, &whitespace_chars, self.buf[self.offset]) != null) : (self.offset += 1)
        {}

        // Handle comments
        const c = try self.char();
        if (c != '/') return;

        if (self.offset + 1 >= self.buf.len) return Error.UnexpectedEOF;

        switch (self.buf[self.offset + 1]) {
            // Single-line comment
            '/' => {
                while (self.offset < self.buf.len and (try self.char()) != '\n') {
                    self.offset += 1;
                }
                try self.skipSpaces();
            },
            // Multi-line comment
            '*' => {
                self.offset += 2;
                while (true) {
                    if (self.offset >= self.buf.len) return Error.UnexpectedEOF;

                    if (self.buf[self.offset] == '*' and
                        self.offset + 1 < self.buf.len and
                        self.buf[self.offset + 1] == '/')
                    {
                        self.offset += 2;
                        try self.skipSpaces();
                        break;
                    }
                    self.offset += 1;
                }
            },
            else => {},
        }
    }

    /// Check if the current character matches the expected one and advance if it does
    pub fn checkAndShift(self: *ParserBuffer, expected: u8) Error!bool {
        if (self.offset >= self.buf.len) return Error.UnexpectedEOF;

        if (self.buf[self.offset] == expected) {
            self.offset += 1;
            return true;
        }
        return false;
    }

    /// Get the current character without advancing the offset
    pub fn char(self: *ParserBuffer) Error!?u8 {
        if (self.offset >= self.buf.len) return null;
        return self.buf[self.offset];
    }

    /// Get the current character and advance the offset
    /// Returns error if at end of buffer
    pub fn shouldShiftNext(self: *ParserBuffer) Error!u8 {
        if (self.offset >= self.buf.len) return Error.UnexpectedEOF;

        const c = self.buf[self.offset];
        self.offset += 1;
        return c;
    }

    /// Expect and consume a semicolon, skipping any whitespace before it
    pub fn semicolon(self: *ParserBuffer) Error!void {
        try self.skipSpaces();
        if (try self.shouldShiftNext() != ';') {
            return Error.SemicolonExpected;
        }
    }

    /// Expect and consume an equals sign, skipping any whitespace before and after
    pub fn assignment(self: *ParserBuffer) Error!void {
        try self.skipSpaces();
        if (try self.shouldShiftNext() != '=') {
            return Error.AssignmentExpected;
        }
        try self.skipSpaces();
    }

    /// Expect and consume an opening brace, skipping any whitespace before and after
    pub fn openBracket(self: *ParserBuffer) Error!void {
        try self.skipSpaces();
        if (try self.shouldShiftNext() != '{') {
            return Error.BracketExpected;
        }
        try self.skipSpaces();
    }

    /// Expect and consume a closing brace, skipping any whitespace before and after
    pub fn closeBracket(self: *ParserBuffer) Error!void {
        try self.skipSpaces();
        if (try self.shouldShiftNext() != '}') {
            return Error.BracketExpected;
        }
        try self.skipSpaces();
    }

    /// Calculate the current line number (1-based)
    pub fn calcLineNumber(self: *ParserBuffer) usize {
        var line: usize = 1;
        for (self.buf[0..self.offset]) |c| {
            if (c == '\n') line += 1;
        }
        return line;
    }

    /// Calculate the column position from the start of the current line
    pub fn calcLineStart(self: *ParserBuffer) usize {
        var i: usize = self.offset;
        while (i > 0) : (i -= 1) {
            if (self.buf[i - 1] == '\n') break;
        }
        return self.offset - i;
    }

    /// Calculate the number of characters remaining until the end of the current line
    pub fn calcLineEnd(self: *ParserBuffer) usize {
        var i: usize = self.offset;
        while (i < self.buf.len) : (i += 1) {
            if (self.buf[i] == '\n') break;
        }
        return i - self.offset;
    }
};

test "whitespaces test" {
    var buf = ParserBuffer{ .buf = "  \t\n\rtest" };
    try (&buf).skipSpaces();
    try std.testing.expectEqual(5, buf.offset);

    var buf1 = ParserBuffer{ .buf = "  \t\n\rtest", .offset = 3 };
    try (&buf1).skipSpaces();
    try std.testing.expectEqual(5, buf1.offset);

    var buf2 = ParserBuffer{ .buf = " test" };
    try (&buf2).skipSpaces();
    try std.testing.expectEqual(1, buf2.offset);
}

test "prefix test" {
    var buf = ParserBuffer{ .buf = "import 'abc';" };
    try std.testing.expect(buf.checkStrAndShift("import"));

    buf = ParserBuffer{ .buf = "import 'abc';" };
    try std.testing.expect(buf.checkStrWithSpaceAndShift("import"));
}

test "large comment" {
    var buf = ParserBuffer.init(
        \\// Protocol Buffers - Google's data interchange format
        \\// Copyright 2008 Google Inc.  All rights reserved.
        \\//
        \\// Use of this source code is governed by a BSD-style
        \\// license that can be found in the LICENSE file or at
        \\// https://developers.google.com/open-source/licenses/bsd
        \\//
        \\// Test schema for proto3 messages.  This test schema is used by:
        \\//
        \\// - benchmarks
        \\// - fuzz tests
        \\// - conformance tests
        \\
        \\ syntax = "proto3";
    );

    try buf.skipSpaces();
    try std.testing.expect(buf.checkStrAndShift("syntax"));
}

test "file read" {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path_len = try std.Io.Dir.cwd().realPathFile(std.testing.io, "test_data/google/proto3.proto", &path_buffer);
    const path = path_buffer[0..path_len];

    var buf = try ParserBuffer.initFile(std.testing.io, std.testing.allocator, path);
    try std.testing.expect(buf.buf.len > 0);
    buf.deinit();
}

test "large /* comment" {
    var buf = ParserBuffer.init(
        \\/* Protocol Buffers - Google's data interchange format
        \\   another line
        \\   * and this one
        \\ */
        \\ syntax = "proto3"
    );
    try buf.skipSpaces();
    try std.testing.expect(buf.checkStrAndShift("syntax"));
}
