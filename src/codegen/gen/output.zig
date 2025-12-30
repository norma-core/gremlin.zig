//! Provides string-based file output functionality for generating Zig source code files.
//! This module handles proper formatting of generated code including indentation,
//! comments, and multi-line strings. Content is accumulated in memory and written
//! to file only when closing.

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
const paths = @import("paths.zig");
const naming = @import("fields/naming.zig");

/// Configuration constants for output formatting
const Config = struct {
    /// Number of spaces per indentation level
    const INDENT_SIZE = 4;
    /// Comment prefix string
    const COMMENT_PREFIX = "// ";
};

/// FileOutput provides string-based output for generating formatted Zig source files.
/// Handles proper indentation, comments, and multi-line string output.
/// All content is accumulated in memory and written to file on close.
pub const FileOutput = struct {
    /// Memory allocator used for dynamic allocations
    allocator: std.mem.Allocator,
    /// Current indentation depth (each level is Config.INDENT_SIZE spaces)
    depth: u32,
    /// Output file path
    path: []const u8,
    /// String buffer to accumulate output
    content: std.ArrayList(u8),

    /// Initialize a new FileOutput with the given allocator and path.
    /// Creates a string buffer to accumulate content.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for buffer allocations
    ///   - path: Output file path
    ///
    /// Returns: Initialized FileOutput or an error
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !FileOutput {
        return FileOutput{
            .allocator = allocator,
            .depth = 0,
            .path = path,
            .content = try std.ArrayList(u8).initCapacity(allocator, 2096),
        };
    }

    /// Writes the current indentation prefix based on depth.
    /// Each indentation level adds Config.INDENT_SIZE spaces.
    ///
    /// Returns: Error if allocation fails
    pub fn writePrefix(self: *FileOutput) !void {
        const spaces = self.depth * Config.INDENT_SIZE;
        var i: usize = 0;
        while (i < spaces) : (i += 1) {
            try self.content.append(self.allocator, ' ');
        }
    }

    /// Writes a single-line comment with proper indentation.
    /// Automatically adds the comment prefix and a newline.
    ///
    /// Parameters:
    ///   - comment: Comment text to write
    ///
    /// Returns: Error if allocation fails
    pub fn writeComment(self: *FileOutput, comment: []const u8) !void {
        try self.writePrefix();
        try self.content.appendSlice(self.allocator, Config.COMMENT_PREFIX);
        try self.content.appendSlice(self.allocator, comment);
        try self.content.append(self.allocator, '\n');
    }

    /// Writes all accumulated content to file and closes it.
    /// Creates the necessary directory structure before writing.
    ///
    /// Returns: Error if file operations fail
    pub fn close(self: *FileOutput) !void {
        // Ensure directory exists
        const dir_path = std.fs.path.dirname(self.path) orelse return error.InvalidPath;
        try std.fs.cwd().makePath(dir_path);

        // Create or truncate output file
        const file = try std.fs.cwd().createFile(self.path, .{
            .truncate = true,
            .read = false,
        });
        defer file.close();

        // Write all content at once
        try file.writeAll(self.content.items);

        // Free the content buffer
        self.content.deinit(self.allocator);
    }

    /// Writes a single linebreak without any indentation.
    ///
    /// Returns: Error if allocation fails
    pub fn linebreak(self: *FileOutput) !void {
        try self.content.append(self.allocator, '\n');
    }

    /// Writes a multi-line string with proper indentation for each line.
    /// Maintains consistent indentation across line breaks.
    ///
    /// Parameters:
    ///   - value: String content to write
    ///
    /// Returns: Error if allocation operations fail
    pub fn writeString(self: *FileOutput, value: []const u8) !void {
        // Generate indentation prefix
        if (self.depth == 0) {
            // No indentation needed
            try self.writeIndentedLines(value, "");
            return;
        }
        var prefix = try self.createIndentPrefix();
        defer prefix.deinit(self.allocator);

        // Write lines with proper indentation
        try self.writeIndentedLines(value, prefix.items);
    }

    /// Continues writing a string without adding indentation or linebreaks.
    /// Useful for building complex strings across multiple write operations.
    ///
    /// Parameters:
    ///   - value: String content to write
    ///
    /// Returns: Error if allocation fails
    pub fn continueString(self: *FileOutput, value: []const u8) !void {
        try self.content.appendSlice(self.allocator, value);
    }

    // Private helper functions

    /// Creates an indentation prefix based on current depth
    fn createIndentPrefix(self: *FileOutput) !std.ArrayList(u8) {
        const spaces = self.depth * Config.INDENT_SIZE;
        var prefix_list = try std.ArrayList(u8).initCapacity(self.allocator, spaces);
        errdefer prefix_list.deinit(self.allocator);

        var i: usize = 0;
        while (i < spaces) : (i += 1) {
            try prefix_list.append(self.allocator, ' ');
        }

        return prefix_list;
    }

    /// Writes lines with consistent indentation
    fn writeIndentedLines(self: *FileOutput, content: []const u8, prefix: []const u8) !void {
        var line_iterator = std.mem.splitSequence(u8, content, "\n");

        while (line_iterator.next()) |line| {
            try self.content.appendSlice(self.allocator, prefix);
            try self.content.appendSlice(self.allocator, line);
            try self.content.append(self.allocator, '\n');
        }
    }
};
