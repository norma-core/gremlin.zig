//! Provides functionality for collecting and managing import dependencies in Protocol Buffer files.
//! This module analyzes message definitions to identify all required imports across nested messages,
//! fields, oneofs, and maps.

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
const ProtoFile = @import("../../parser/main.zig").ProtoFile;
const Message = @import("../../parser/main.zig").Message;

/// ImportCollector analyzes Protocol Buffer definitions to gather all required imports.
/// It tracks unique dependencies and ensures no duplicate imports are included.
pub const ImportCollector = struct {
    /// List of unique ProtoFile references that need to be imported
    targets: std.ArrayList(*const ProtoFile),
    allocator: std.mem.Allocator,

    /// Creates a new ImportCollector and analyzes the given file for imports.
    /// Processes all messages and their nested components to find dependencies.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for the targets list
    ///   - file: Protocol Buffer file to analyze
    ///
    /// Returns: Owned slice of ProtoFile pointers representing required imports
    pub fn collectFromFile(allocator: std.mem.Allocator, file: *const ProtoFile) ![]*const ProtoFile {
        var collector = ImportCollector{
            .targets = try std.ArrayList(*const ProtoFile).initCapacity(allocator, 64),
            .allocator = allocator,
        };
        errdefer collector.targets.deinit(allocator);

        // Process all top-level messages
        for (file.messages.items) |*msg| {
            try collector.collectFromMessage(msg);
        }

        return collector.targets.toOwnedSlice(allocator);
    }

    /// Adds a new import target if it's not already present.
    /// Maintains uniqueness of imports to prevent duplicates.
    ///
    /// Parameters:
    ///   - import_target: ProtoFile to add as an import
    ///
    /// Returns: Error if append operation fails
    fn addImport(self: *ImportCollector, import_target: *const ProtoFile) !void {
        // Check for existing import
        for (self.targets.items) |target| {
            if (target == import_target) return;
        }
        try self.targets.append(self.allocator, import_target);
    }

    /// Recursively collects imports from a message and all its components.
    /// Processes nested messages, fields, oneofs, and maps to find all dependencies.
    ///
    /// Parameters:
    ///   - msg: Message to analyze for imports
    ///
    /// Returns: Error if collection operations fail
    fn collectFromMessage(self: *ImportCollector, msg: *const Message) anyerror!void {
        // Process nested messages recursively
        try self.collectNestedMessageImports(msg);

        // Process different types of fields
        try self.collectFieldImports(msg);
        try self.collectOneofImports(msg);
        try self.collectMapImports(msg);
    }

    // Helper functions for different types of imports

    /// Processes nested messages within a message.
    fn collectNestedMessageImports(self: *ImportCollector, msg: *const Message) !void {
        for (msg.messages.items) |*sub_msg| {
            try self.collectFromMessage(sub_msg);
        }
    }

    /// Processes regular fields within a message.
    fn collectFieldImports(self: *ImportCollector, msg: *const Message) !void {
        for (msg.fields.items) |*field| {
            if (field.f_type.ref_import) |ref_import| {
                try self.addImport(ref_import);
            }
            // Also collect from scope_ref (for extended fields)
            if (field.f_type.scope_ref) |scope_ref| {
                try self.addImport(scope_ref);
            }
        }
    }

    /// Processes oneof fields within a message.
    fn collectOneofImports(self: *ImportCollector, msg: *const Message) !void {
        for (msg.oneofs.items) |*oneof| {
            for (oneof.fields.items) |*field| {
                if (field.f_type.ref_import) |ref_import| {
                    try self.addImport(ref_import);
                }
                // Also collect from scope_ref (for extended fields)
                if (field.f_type.scope_ref) |scope_ref| {
                    try self.addImport(scope_ref);
                }
            }
        }
    }

    /// Processes map fields within a message.
    fn collectMapImports(self: *ImportCollector, msg: *const Message) !void {
        for (msg.maps.items) |*map| {
            if (map.value_type.ref_import) |ref_import| {
                try self.addImport(ref_import);
            }
            // Also collect from scope_ref (for extended fields)
            if (map.value_type.scope_ref) |scope_ref| {
                try self.addImport(scope_ref);
            }
        }
    }
};
