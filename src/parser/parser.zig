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

const ParserBuffer = @import("entries/buffer.zig").ParserBuffer;
const ProtoFile = @import("entries/file.zig").ProtoFile;
const Error = @import("entries/errors.zig").Error;
const Edition = @import("entries/edition.zig").Edition;
const Enum = @import("entries/enum.zig").Enum;

// Field-related types
const fields = @import("entries/field.zig");
const OneOfField = fields.OneOfField;
const MessageOneOfField = fields.MessageOneOfField;
const MessageMapField = fields.MessageMapField;
const NormalField = fields.NormalField;

// Protocol buffer elements
const Import = @import("entries/import.zig").Import;
const Message = @import("entries/message.zig").Message;
const Option = @import("entries/option.zig").Option;
const Package = @import("entries/package.zig").Package;
const Reserved = @import("entries/reserved.zig").Reserved;
const Service = @import("entries/service.zig").Service;
const Syntax = @import("entries/syntax.zig").Syntax;

// Internal imports
const paths = @import("fs/paths.zig");
const resolveImports = @import("fs/imports.zig").resolveImports;
const resolveReferences = @import("resolver.zig").resolveReferences;

/// Represents the result of parsing protocol buffer files
/// Owns all the parsed data and associated buffers
const ParseResult = struct {
    files: std.ArrayList(ProtoFile),
    bufs: std.ArrayList(ParserBuffer),
    root: []const u8,
    allocator: std.mem.Allocator,

    /// Frees all resources associated with the parse result
    pub fn deinit(self: *ParseResult) void {
        for (self.files.items) |*file| {
            file.deinit();
        }
        self.files.deinit(self.allocator);
        for (self.bufs.items) |*buf| {
            buf.deinit();
        }
        self.bufs.deinit(self.allocator);
    }
};

/// Formats and prints a parser error with context about where the error occurred
fn printError(allocator: std.mem.Allocator, path: []const u8, err: Error, buf: *ParserBuffer) !void {
    const err_line = buf.calcLineNumber();
    const line_start = buf.calcLineStart();
    const line_end = buf.calcLineEnd();
    const err_pos = buf.offset - line_start;
    const err_fragment = buf.buf[err_pos .. buf.offset + line_end];

    // Print error message with location context
    std.debug.print(
        \\Failed to parse file {s} [offset = {d}]:
        \\Error: {}
        \\{d}: {s}
    , .{ path, buf.offset, err, err_line, err_fragment });

    // Add error pointer alignment if needed
    if (line_start != 0) {
        const spaces = try allocator.alloc(u8, line_start - 1);
        defer allocator.free(spaces);

        @memset(spaces, ' ');
        std.debug.print(
            \\
            \\{s}^
            \\
        , .{spaces});
    } else {
        std.debug.print("\n", .{});
    }
}

/// Parse protocol buffer files starting from the given base path
/// Returns a ParseResult containing all parsed files and their buffers
/// Caller owns the returned ParseResult and must call deinit() on it
pub fn parse(allocator: std.mem.Allocator, base_path: []const u8, ignore_masks: ?[]const []const u8) !ParseResult {
    var proto_files = try paths.findProtoFiles(allocator, base_path, ignore_masks);
    defer {
        for (proto_files.items) |file| {
            allocator.free(file);
        }
        proto_files.deinit(allocator);
    }

    const root = if (!std.fs.path.isAbsolute(base_path))
        try std.fs.cwd().realpathAlloc(allocator, base_path)
    else
        try allocator.dupe(u8, base_path);
    defer allocator.free(root);

    // Parse each file
    var parsed_files = try std.ArrayList(ProtoFile).initCapacity(allocator, proto_files.items.len);
    errdefer {
        for (parsed_files.items) |*file| {
            file.deinit();
        }
        parsed_files.deinit(allocator);
    }

    var parser_buffers = try std.ArrayList(ParserBuffer).initCapacity(allocator, proto_files.items.len);
    errdefer {
        for (parser_buffers.items) |*buf| {
            buf.deinit();
        }
        parser_buffers.deinit(allocator);
    }

    // Process each proto file
    for (proto_files.items) |file_path| {
        var buffer = try ParserBuffer.initFile(allocator, file_path);
        errdefer buffer.deinit();

        var result = ProtoFile.parse(allocator, &buffer);
        if (result) |*proto_file| {
            proto_file.path = try allocator.dupe(u8, file_path);
            try parsed_files.append(allocator, proto_file.*);
            try parser_buffers.append(allocator, buffer);
        } else |err| {
            try printError(allocator, file_path, err, &buffer);
            buffer.deinit();
        }
    }

    // Resolve imports and references
    try resolveImports(allocator, root, &parsed_files);
    try resolveReferences(&parsed_files);

    return ParseResult{
        .files = parsed_files,
        .bufs = parser_buffers,
        .root = base_path,
        .allocator = allocator,
    };
}
