//! Main module for the Protocol Buffer to Zig code generator.
//! This module orchestrates the generation process, handling file parsing,
//! code generation, and file output management.

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
// Created by ab, 14.11.2024

const std = @import("std");

const gremlin_parser = @import("../parser/main.zig");
const ProtoFile = gremlin_parser.ProtoFile;
const paths = @import("gen/paths.zig");
const FileOutput = @import("gen/output.zig").FileOutput;
const ZigFile = @import("gen/file.zig").ZigFile;
const well_known_types = @import("../parser/well_known_types.zig");

/// GeneratorError enumerates possible errors that can occur during code generation
pub const GeneratorError = error{
    /// File path could not be resolved
    PathResolutionError,
    /// File could not be created or written
    FileWriteError,
    /// Parser encountered an error
    ParserError,
    /// Reference resolution failed
    ReferenceResolutionError,
};

/// Creates a ZigFile instance from a Protocol Buffer file.
/// Handles path resolution and initialization of the Zig source file.
///
/// Parameters:
///   - allocator: Memory allocator for string operations
///   - file: Source Protocol Buffer file
///   - proto_root: Root directory of proto files
///   - target_root: Root directory for generated Zig files
///
/// Returns: Initialized ZigFile instance
/// Error: PathResolutionError if paths cannot be resolved
///        FileWriteError if file operations fail
fn createFile(
    allocator: std.mem.Allocator,
    file: *const ProtoFile,
    proto_root: []const u8,
    target_root: []const u8,
) !ZigFile {
    const file_path = file.path.?;

    // For well-known types, the path is already relative (e.g., "google/protobuf/any.proto")
    // For regular files, compute relative path from proto_root
    const rel_to_proto = if (well_known_types.isWellKnownImport(file_path))
        try allocator.dupe(u8, file_path)
    else
        try std.fs.path.relativePosix(allocator, proto_root, file_path);
    defer allocator.free(rel_to_proto);

    // Generate output path
    const out_path = try paths.outputPath(allocator, rel_to_proto, target_root);
    defer allocator.free(out_path);

    // Initialize Zig file
    return ZigFile.init(
        allocator,
        out_path,
        file,
        proto_root,
        target_root,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => err,
            else => GeneratorError.FileWriteError,
        };
    };
}

/// Main function to generate Zig code from Protocol Buffer definitions.
/// Orchestrates the complete generation process including parsing, reference resolution,
/// and code generation.
///
/// Parameters:
///   - allocator: Memory allocator for all operations
///   - proto_root: Root directory containing proto files
///   - target_root: Root directory for generated Zig files
///   - ignore_masks: Optional list of glob patterns to ignore
///
/// Error: GeneratorError variants for different failure modes
///        OutOfMemory if allocation fails
pub fn generateProtobuf(
    allocator: std.mem.Allocator,
    proto_root: []const u8,
    target_root: []const u8,
    ignore_masks: ?[]const []const u8,
) !void {
    var parsed = try gremlin_parser.parse(allocator, proto_root, ignore_masks);
    defer parsed.deinit();

    // Create ZigFile instances
    var files = try std.ArrayList(ZigFile).initCapacity(allocator, parsed.files.items.len);
    defer {
        for (files.items) |*file| {
            file.deinit();
        }
        files.deinit(allocator);
    }

    // Initialize files
    for (parsed.files.items) |*file| {
        try files.append(allocator, try createFile(
            allocator,
            file,
            proto_root,
            target_root,
        ));
    }

    // Resolve cross-file references
    try resolveReferences(&files);

    // Generate code for each file
    try generateCode(allocator, &files);
}

/// Resolves cross-file references between all generated files.
///
/// Parameters:
///   - files: List of ZigFile instances to process
fn resolveReferences(files: *std.ArrayList(ZigFile)) !void {
    // Resolve imports between files
    for (files.items) |*file| {
        try file.resolveImports(files.items);
    }

    // Resolve internal references
    for (files.items) |*file| {
        try file.resolveRefs();
    }
}

/// Generates code for all files and writes to disk.
///
/// Parameters:
///   - allocator: Memory allocator for file operations
///   - files: List of ZigFile instances to generate code for
fn generateCode(allocator: std.mem.Allocator, files: *std.ArrayList(ZigFile)) !void {
    for (files.items) |*file| {
        var out_file = try FileOutput.init(allocator, file.out_path);
        try file.write(&out_file);
        try out_file.close();
    }
}
