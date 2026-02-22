//! Provides functionality for managing imports in generated Zig code from Protocol Buffer definitions.
//! This module handles both system imports (std, gremlin) and file-based imports, managing their
//! resolution and code generation.

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
// Created by ab, 04.11.2024

const std = @import("std");
const paths = @import("./paths.zig");
const naming = @import("./fields/naming.zig");
const Import = @import("../../parser/main.zig").Import;
const ProtoFile = @import("../../parser/main.zig").ProtoFile;
const ZigFile = @import("./file.zig").ZigFile;
const well_known_types = @import("../../parser/well_known_types.zig");

/// Represents a Zig import statement, handling both system imports (std, gremlin)
/// and imports from other proto files.
pub const ZigImport = struct {
    allocator: std.mem.Allocator,
    alias: []const u8, // Import alias used in generated code
    path: []const u8, // Import path
    src: ?*const ProtoFile, // Source proto file (null for system imports)
    target: ?*const ZigFile = null, // Resolved target Zig file
    is_system: bool, // Whether this is a system import (std/gremlin)

    /// Initialize a new ZigImport instance.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for string allocations
    ///   - src: Source proto file (null for system imports)
    ///   - alias: Import alias to use in generated code
    ///   - path: Import path
    ///
    /// Returns: A new ZigImport instance
    /// Error: OutOfMemory if string allocation fails
    pub fn init(allocator: std.mem.Allocator, src: ?*const ProtoFile, alias: []const u8, path: []const u8) !ZigImport {
        return ZigImport{
            .allocator = allocator,
            .src = src,
            .is_system = std.mem.eql(u8, path, "std") or std.mem.eql(u8, path, "gremlin"),
            .alias = try allocator.dupe(u8, alias),
            .path = try allocator.dupe(u8, path),
        };
    }

    /// Frees resources owned by this import.
    pub fn deinit(self: *ZigImport) void {
        self.allocator.free(self.alias);
        self.allocator.free(self.path);
    }

    /// Resolves this import against a list of generated Zig files.
    /// Links the import to its corresponding target file for cross-file references.
    ///
    /// Parameters:
    ///   - files: Slice of all generated Zig files
    ///
    /// Panics: If import resolution fails
    pub fn resolve(self: *ZigImport, files: []ZigFile) !void {
        if (self.is_system) {
            return;
        }

        for (files) |*f| {
            if (self.src) |src| {
                if (src == f.file) {
                    self.target = f;
                    return;
                }
            } else {
                unreachable;
            }
        }

        std.debug.panic("Failed to resolve import: {s}", .{self.path});
    }

    /// Generates the Zig code representation of this import.
    ///
    /// Returns: Allocated string containing the import statement
    /// Error: OutOfMemory if allocation fails
    pub fn code(self: *const ZigImport) ![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "const {s} = @import(\"{s}\");",
            .{ self.alias, self.path },
        );
    }
};

/// Resolves an import path to create a ZigImport instance.
/// Handles path resolution between proto files and generated Zig files,
/// ensuring proper relative paths are used. Import paths are generated
/// relative to the importing file's location, as required by Zig's
/// `@import` builtin.
///
/// Parameters:
///   - allocator: Memory allocator for string allocations
///   - src: Source Protocol Buffer file containing the import
///   - proto_root: Root directory of proto files
///   - target_root: Root directory for generated Zig files
///   - import_path_in_proto_file: Path to the imported proto file
///   - proto_file_path: Path of the current proto file (the one doing the importing)
///   - names: List of existing names to avoid conflicts
///
/// Returns: A new ZigImport instance with resolved paths
/// Error: OutOfMemory if allocation fails
///        File system errors during path resolution
pub fn importResolve(
    allocator: std.mem.Allocator,
    src: *const ProtoFile,
    proto_root: []const u8,
    target_root: []const u8,
    import_path_in_proto_file: []const u8,
    proto_file_path: []const u8,
    names: *std.ArrayList([]const u8),
) !ZigImport {
    // For well-known types, the import_path is already relative (e.g., "google/protobuf/any.proto")
    // For regular files, compute relative path from proto_root
    const imported_file_rel_path_from_proto_root = if (well_known_types.isWellKnownImport(import_path_in_proto_file))
        try allocator.dupe(u8, import_path_in_proto_file)
    else
        try std.fs.path.relativePosix(allocator, proto_root, import_path_in_proto_file);
    defer allocator.free(imported_file_rel_path_from_proto_root);

    // Generate output path for the imported file
    const out_path = try paths.outputPath(allocator, imported_file_rel_path_from_proto_root, target_root);
    defer allocator.free(out_path);

    // Generate import alias from filename
    const file_name = std.fs.path.stem(import_path_in_proto_file);
    const name = try naming.importAlias(allocator, file_name, names);
    defer allocator.free(name);

    // Determine if import is from same directory
    const file_dir = std.fs.path.dirname(proto_file_path) orelse ".";
    const import_dir = std.fs.path.dirname(import_path_in_proto_file) orelse ".";

    if (std.mem.eql(u8, file_dir, import_dir)) {
        // Same directory - use just the filename
        return try ZigImport.init(allocator, src, name, std.fs.path.basename(out_path));
    } else {
        // Different directory - compute path relative to the importing file's output location
        // First, get the output path for the current file (the one doing the importing)
        const current_file_rel_to_proto_root = try std.fs.path.relativePosix(allocator, proto_root, proto_file_path);
        defer allocator.free(current_file_rel_to_proto_root);

        const current_file_out_path = try paths.outputPath(allocator, current_file_rel_to_proto_root, target_root);
        defer allocator.free(current_file_out_path);

        // Get the directory of the current output file
        const current_out_dir = std.fs.path.dirname(current_file_out_path) orelse ".";

        // Compute relative path from current file's directory to imported file
        const rel_import_path = try std.fs.path.relativePosix(allocator, current_out_dir, out_path);
        defer allocator.free(rel_import_path);

        return try ZigImport.init(allocator, src, name, rel_import_path);
    }
}

test "importResolve same directory" {
    const allocator = std.testing.allocator;
    var names = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer names.deinit(allocator);

    // Simulate two proto files in the same directory
    const result = try importResolve(
        allocator,
        undefined, // src not used in test
        "/proto",
        "gen",
        "/proto/foo/baz.proto",
        "/proto/foo/bar.proto",
        &names,
    );
    defer @constCast(&result).deinit();

    // Same directory should use just the filename
    try std.testing.expectEqualStrings("baz.proto.zig", result.path);
}

test "importResolve different parent directory" {
    const allocator = std.testing.allocator;
    var names = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer names.deinit(allocator);

    // Simulate two proto files in different directories
    const result = try importResolve(
        allocator,
        undefined, // src not used in test
        "/proto",
        "gen",
        "/proto/baz/qux.proto", // proto/baz vs. proto/foo
        "/proto/foo/bar.proto",
        &names,
    );
    defer @constCast(&result).deinit();

    // Different directory should use relative path from importing file's directory
    try std.testing.expectEqualStrings("../baz/qux.proto.zig", result.path);
}

test "importResolve importer nested below importee" {
    const allocator = std.testing.allocator;
    var names = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer names.deinit(allocator);

    // Simulate importing from a nested directory to a parent directory
    const result = try importResolve(
        allocator,
        undefined, // src not used in test
        "/proto",
        "gen",
        "/proto/foo/shallow.proto",
        "/proto/foo/bar/deep.proto",
        &names,
    );
    defer @constCast(&result).deinit();

    try std.testing.expectEqualStrings("../shallow.proto.zig", result.path);
}

test "importResolve importee nested below importer" {
    const allocator = std.testing.allocator;
    var names = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer names.deinit(allocator);

    // Simulate importing from a parent directory to a nested directory
    const result = try importResolve(
        allocator,
        undefined, // src not used in test
        "/proto",
        "gen",
        "/proto/foo/bar/deep.proto",
        "/proto/foo/shallow.proto",
        &names,
    );
    defer @constCast(&result).deinit();

    try std.testing.expectEqualStrings("bar/deep.proto.zig", result.path);
}
