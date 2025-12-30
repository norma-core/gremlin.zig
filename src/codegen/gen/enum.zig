//! Provides functionality for generating Zig enum types from Protocol Buffer definitions.
//! This module handles the conversion of protobuf enum definitions into their Zig counterparts,
//! ensuring proper naming conventions and value handling.

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
const naming = @import("fields/naming.zig");
const Enum = @import("../../parser/main.zig").Enum;

/// Represents a single entry in a Zig enum definition.
/// Each entry contains a constant name and its associated integer value.
pub const ZigEnumEntry = struct {
    allocator: std.mem.Allocator,
    constName: []const u8,
    value: i32,

    /// Creates a new enum entry with the given name and value.
    /// The name will be owned by this entry and must be freed using deinit().
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for string allocation
    ///   - constName: Name of the enum constant (will be copied)
    ///   - value: Integer value associated with this enum entry
    ///
    /// Returns: A new ZigEnumEntry instance or an error if allocation fails
    pub fn init(allocator: std.mem.Allocator, constName: []const u8, value: i32) !ZigEnumEntry {
        return ZigEnumEntry{
            .allocator = allocator,
            .constName = constName,
            .value = value,
        };
    }

    /// Frees resources associated with this enum entry.
    pub fn deinit(self: *ZigEnumEntry) void {
        self.allocator.free(self.constName);
    }
};

/// Represents a complete Zig enum type definition.
/// Manages the generation of enum types from Protocol Buffer definitions,
/// including handling of entries, naming, and code generation.
pub const ZigEnum = struct {
    allocator: std.mem.Allocator,
    const_name: []const u8, // The name of the enum type
    full_name: []const u8, // Fully qualified name including scope
    entries: std.ArrayList(ZigEnumEntry),
    src: *const Enum, // Reference to source enum definition

    /// Initialize a new ZigEnum from a Protocol Buffer enum definition.
    /// Handles conversion of names, ensures a zero value exists, and manages
    /// naming conflicts.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for string and list allocations
    ///   - src: Source Protocol Buffer enum definition
    ///   - scope_name: Namespace scope for this enum (empty string for root scope)
    ///   - names: List of existing names to avoid conflicts
    ///
    /// Returns: A new ZigEnum instance or an error if initialization fails
    pub fn init(
        allocator: std.mem.Allocator,
        src: *const Enum,
        scope_name: []const u8,
        names: *std.ArrayList([]const u8),
    ) !ZigEnum {
        var entriesList = try std.ArrayList(ZigEnumEntry).initCapacity(allocator, src.fields.items.len);
        errdefer {
            for (entriesList.items) |*entry| entry.deinit();
            entriesList.deinit(allocator);
        }

        // Process enum fields
        const has_zero_value = try processEnumFields(allocator, src, &entriesList);

        // Ensure zero value exists
        if (!has_zero_value) {
            try addDefaultUnknownField(allocator, &entriesList);
        }

        // Generate enum type name and full path
        const const_name = try naming.structName(allocator, src.name.name, names);
        const full_name = try buildFullyQualifiedName(allocator, scope_name, const_name);

        return ZigEnum{
            .src = src,
            .allocator = allocator,
            .const_name = const_name,
            .full_name = full_name,
            .entries = entriesList,
        };
    }

    /// Generates the Zig code representation of this enum.
    /// Creates a properly formatted enum definition including all entries
    /// with their associated values.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for string building
    ///
    /// Returns: A newly allocated string containing the Zig enum code
    pub fn createEnumDef(self: *const ZigEnum, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = try std.ArrayList(u8).initCapacity(allocator, 1024);
        errdefer buffer.deinit(allocator);
        var writer = buffer.writer(allocator);

        try writer.print("pub const {s} = enum(i32) {{\n", .{self.const_name});

        // Write entries with consistent formatting
        for (self.entries.items) |entry| {
            try writer.print("    {s} = {d},\n", .{ entry.constName, entry.value });
        }

        try writer.writeAll("};\n");
        return buffer.toOwnedSlice(allocator);
    }

    /// Frees all resources associated with this enum definition.
    pub fn deinit(self: *ZigEnum) void {
        for (self.entries.items) |*entry| {
            entry.deinit();
        }
        self.allocator.free(self.const_name);
        self.allocator.free(self.full_name);
        self.entries.deinit(self.allocator);
    }

    // Internal helper functions

    /// Process fields from the source enum definition.
    /// Converts Protocol Buffer enum fields into Zig enum entries.
    fn processEnumFields(
        allocator: std.mem.Allocator,
        src: *const Enum,
        entriesList: *std.ArrayList(ZigEnumEntry),
    ) !bool {
        var entries_names = try std.ArrayList([]const u8).initCapacity(allocator, src.fields.items.len);
        defer entries_names.deinit(allocator);

        var has_zero_value = false;

        for (src.fields.items) |field| {
            if (field.index == 0) {
                has_zero_value = true;
            }
            const field_name = try naming.enumFieldName(allocator, field.name, &entries_names);
            try entriesList.append(allocator, try ZigEnumEntry.init(allocator, field_name, field.index));
        }

        return has_zero_value;
    }

    /// Adds a default unknown field with value 0 if no zero value exists.
    fn addDefaultUnknownField(
        allocator: std.mem.Allocator,
        entriesList: *std.ArrayList(ZigEnumEntry),
    ) !void {
        var entries_names = try std.ArrayList([]const u8).initCapacity(allocator, 1);
        defer entries_names.deinit(allocator);

        try entriesList.append(allocator, ZigEnumEntry{
            .allocator = allocator,
            .constName = try naming.enumFieldName(allocator, "___protobuf_unknown", &entries_names),
            .value = 0,
        });
    }

    /// Builds the fully qualified name for the enum type.
    fn buildFullyQualifiedName(
        allocator: std.mem.Allocator,
        scope_name: []const u8,
        const_name: []const u8,
    ) ![]const u8 {
        return if (scope_name.len > 0)
            try std.mem.concat(allocator, u8, &[_][]const u8{ scope_name, ".", const_name })
        else
            try allocator.dupe(u8, const_name);
    }
};

test "enum generation" {
    const ParserBuffer = @import("../../parser/main.zig").ParserBuffer;
    var buf = ParserBuffer.init(
        \\enum ForeignEnum {
        \\    FOREIGN_FOO = 0;
        \\    FOREIGN_BAR = 1;
        \\    FOREIGN_BAZ = 2;
        \\}
    );
    var result = try Enum.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer result.deinit();

    var names = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 16);
    defer names.deinit(std.testing.allocator);

    var zig_enum = try ZigEnum.init(std.testing.allocator, &result, "", &names);
    const code = try zig_enum.createEnumDef(std.testing.allocator);
    defer std.testing.allocator.free(code);
    defer zig_enum.deinit();

    try std.testing.expectEqualStrings(
        \\pub const ForeignEnum = enum(i32) {
        \\    FOREIGN_FOO = 0,
        \\    FOREIGN_BAR = 1,
        \\    FOREIGN_BAZ = 2,
        \\};
        \\
    , code);
}
