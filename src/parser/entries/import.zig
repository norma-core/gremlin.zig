//! Import module provides parsing capabilities for Protocol Buffer import statements.
//! This module handles both regular imports and qualified imports (weak/public),
//! supporting the full Protocol Buffer import syntax.

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
const strLit = @import("lexems.zig").strLit;
const ProtoFile = @import("file.zig").ProtoFile;

/// ImportType represents the qualification of an import statement.
/// Protocol Buffers supports three types of imports:
/// - Regular (no qualifier)
/// - Weak (symbols are optional)
/// - Public (symbols are re-exported)
pub const ImportType = enum {
    /// Weak imports don't cause errors if the imported file is missing
    weak,
    /// Public imports re-export all symbols from the imported file
    public,
};

/// Import represents a single Protocol Buffer import statement.
/// Examples:
/// ```protobuf
/// import "foo/bar.proto";              // Regular import
/// import weak "foo/optional.proto";     // Weak import
/// import public "foo/reexported.proto"; // Public import
/// ```
pub const Import = struct {
    /// Starting position of the import statement in source
    start: usize,
    /// Ending position of the import statement in source
    end: usize,
    /// Import qualification (weak/public) if any
    i_type: ?ImportType,
    /// Path to the imported file
    path: []const u8,
    /// Reference to the parsed imported file (null until resolved)
    target: ?*ProtoFile = null,

    /// Parse an import statement from the given buffer.
    /// Returns null if the current position doesn't contain an import statement.
    ///
    /// Syntax:
    ///   import [weak|public] "path/to/file.proto";
    ///
    /// Returns:
    ///   Import structure if successful
    ///   null if not an import statement
    ///   Error if invalid syntax
    pub fn parse(buf: *ParserBuffer) Error!?Import {
        try buf.skipSpaces();
        const start = buf.offset;

        // Check for import keyword
        if (!buf.checkStrWithSpaceAndShift("import")) {
            return null;
        }

        // Parse optional import type qualifier
        var i_type: ?ImportType = null;
        if (buf.checkStrAndShift("weak")) {
            i_type = ImportType.weak;
        } else if (buf.checkStrAndShift("public")) {
            i_type = ImportType.public;
        }

        // Parse the import path (must be a string literal)
        const path = try strLit(buf);

        // Expect semicolon
        try buf.semicolon();

        return Import{
            .start = start,
            .end = buf.offset,
            .i_type = i_type,
            .path = path,
        };
    }

    /// Returns true if this is a weak import
    pub fn isWeak(self: Import) bool {
        return self.i_type == ImportType.weak;
    }

    /// Returns true if this is a public import
    pub fn isPublic(self: Import) bool {
        return self.i_type == ImportType.public;
    }

    /// Returns true if the imported file has been resolved
    pub fn isResolved(self: Import) bool {
        return self.target != null;
    }

    /// Get the basename of the imported file (everything after the last slash)
    pub fn basename(self: Import) []const u8 {
        const last_slash = std.mem.lastIndexOf(u8, self.path, "/") orelse return self.path;
        return self.path[last_slash + 1 ..];
    }

    /// Get the directory part of the import path (everything before the last slash)
    pub fn directory(self: Import) []const u8 {
        const last_slash = std.mem.lastIndexOf(u8, self.path, "/") orelse return "";
        return self.path[0..last_slash];
    }
};

test "parse weak import" {
    var buf = ParserBuffer.init("import weak \"foo/bar\";");
    const import = try Import.parse(&buf) orelse {
        try std.testing.expect(false);
        unreachable;
    };

    try std.testing.expectEqual(@as(usize, 0), import.start);
    try std.testing.expectEqual(@as(usize, 22), import.end);
    try std.testing.expectEqual(ImportType.weak, import.i_type.?);
    try std.testing.expectEqualStrings("foo/bar", import.path);
    try std.testing.expect(import.isWeak());
    try std.testing.expect(!import.isPublic());
}

test "parse public import" {
    var buf = ParserBuffer.init("import public \"foo/bar\";");
    const import = try Import.parse(&buf) orelse unreachable;

    try std.testing.expectEqual(@as(usize, 0), import.start);
    try std.testing.expectEqual(@as(usize, 24), import.end);
    try std.testing.expectEqual(ImportType.public, import.i_type.?);
    try std.testing.expectEqualStrings("foo/bar", import.path);
    try std.testing.expect(!import.isWeak());
    try std.testing.expect(import.isPublic());
}

test "parse regular import" {
    var buf = ParserBuffer.init("import \"foo/bar-baz.proto\";");
    const import = try Import.parse(&buf) orelse unreachable;

    try std.testing.expectEqual(@as(usize, 0), import.start);
    try std.testing.expectEqual(@as(usize, 27), import.end);
    try std.testing.expectEqual(null, import.i_type);
    try std.testing.expectEqualStrings("foo/bar-baz.proto", import.path);
    try std.testing.expect(!import.isWeak());
    try std.testing.expect(!import.isPublic());
}

test "parse path components" {
    var buf = ParserBuffer.init("import \"foo/bar/baz.proto\";");
    const import = try Import.parse(&buf) orelse unreachable;

    try std.testing.expectEqualStrings("baz.proto", import.basename());
    try std.testing.expectEqualStrings("foo/bar", import.directory());
}

test "parse multiple imports" {
    const import_text =
        \\import "google/protobuf/any.proto";
        \\import "google/protobuf/duration.proto";
        \\import "google/protobuf/field_mask.proto";
        \\import "google/protobuf/struct.proto";
        \\import "google/protobuf/timestamp.proto";
        \\import "google/protobuf/wrappers.proto";
    ;

    var buf = ParserBuffer.init(import_text);

    // Should be able to parse 6 consecutive imports
    inline for (0..6) |_| {
        const import = try Import.parse(&buf) orelse {
            try std.testing.expect(false);
            unreachable;
        };
        try std.testing.expect(std.mem.startsWith(u8, import.path, "google/protobuf/"));
        try std.testing.expect(std.mem.endsWith(u8, import.path, ".proto"));
    }

    // Should be no more imports
    try std.testing.expectEqual(@as(?Import, null), try Import.parse(&buf));
}
