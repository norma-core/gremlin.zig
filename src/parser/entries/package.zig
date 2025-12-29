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
const ScopedName = @import("scoped-name.zig").ScopedName;
const fullScopedName = @import("lexems.zig").fullScopedName;

/// Represents a package declaration in a protobuf file.
/// The package name specifies the namespace for message types.
/// Format:
/// ```protobuf
/// package foo.bar.baz;
/// ```
pub const Package = struct {
    /// Starting position of the package declaration in the input buffer
    start: usize,
    /// Ending position of the package declaration in the input buffer
    end: usize,
    /// Fully qualified package name (e.g., "foo.bar.baz")
    name: ScopedName,

    /// Attempts to parse a package declaration from the given buffer.
    /// Returns null if the buffer doesn't start with a package declaration.
    ///
    /// The package name must be a dot-separated sequence of identifiers.
    /// The declaration must end with a semicolon.
    ///
    /// Errors:
    /// - Error.UnexpectedEOF: Buffer ends before declaration is complete
    /// - Error.InvalidCharacter: Invalid character in package name
    /// - Error.OutOfMemory: Failed to allocate memory for package name
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!?Package {
        try buf.skipSpaces();

        const start = buf.offset;

        if (!buf.checkStrWithSpaceAndShift("package")) {
            return null;
        }

        var name = try fullScopedName(allocator, buf);
        errdefer name.deinit();

        try buf.semicolon();

        return Package{
            .start = start,
            .name = name,
            .end = buf.offset,
        };
    }

    /// Frees the memory allocated for the package name
    pub fn deinit(self: *Package) void {
        self.name.deinit();
    }
};

test "package parsing" {
    // Test case 1: Basic package declaration
    {
        var buf = ParserBuffer.init("package my.package;");
        var pkg = try Package.parse(std.testing.allocator, &buf) orelse unreachable;
        defer pkg.deinit();

        try std.testing.expectEqual(0, pkg.start);
        try std.testing.expectEqual(19, pkg.end);
        try std.testing.expectEqualStrings(".my.package", pkg.name.full);
    }

    // Test case 2: Package with extra whitespace
    {
        var buf = ParserBuffer.init("package  my.package  ;");
        var pkg = try Package.parse(std.testing.allocator, &buf) orelse unreachable;
        defer pkg.deinit();

        try std.testing.expectEqualStrings(".my.package", pkg.name.full);
    }

    // Test case 3: Not a package declaration
    {
        var buf = ParserBuffer.init("message Test {}");
        const result = try Package.parse(std.testing.allocator, &buf);
        try std.testing.expect(result == null);
    }

    // Test case 4: Package with deeply nested namespace
    {
        var buf = ParserBuffer.init("package com.example.project.submodule;");
        var pkg = try Package.parse(std.testing.allocator, &buf) orelse unreachable;
        defer pkg.deinit();

        try std.testing.expectEqualStrings(".com.example.project.submodule", pkg.name.full);
    }
}
