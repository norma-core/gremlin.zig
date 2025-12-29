//! This module handles the conversion of Protocol Buffer identifiers to valid Zig identifiers.
//! It ensures proper naming conventions, handles keywords, and maintains uniqueness of names
//! across different contexts (constants, fields, methods, etc.).

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
// Created by ab, 10.11.2024

const std = @import("std");

/// List of Zig keywords that need special handling to avoid naming conflicts
const keywords = [_][]const u8{ "align", "and", "asm", "async", "await", "break", "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error", "export", "extern", "fn", "for", "if", "inline", "noalias", "noinline", "nosuspend", "opaque", "or", "orelse", "packed", "pub", "resume", "return", "struct", "suspend", "switch", "test", "threadlocal", "try", "union", "unreachable", "usingnamespace", "var", "volatile", "while", "void", "null" };

/// Check if a given name is a Zig keyword
fn isKeyword(name: []const u8) bool {
    for (keywords) |keyword| {
        if (std.mem.eql(u8, keyword, name)) {
            return true;
        }
    }
    return false;
}

/// Convert a name to SCREAMING_SNAKE_CASE for constants
fn makeZigConstName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, name.len * 2);
    errdefer result.deinit(allocator);

    if (name.len == 0) return result.toOwnedSlice(allocator);

    // Handle first character - prefix with '_' if it starts with a digit
    if (std.ascii.isDigit(name[0])) {
        try result.append(allocator, '_');
    }
    try result.append(allocator, std.ascii.toUpper(name[0]));

    // Process remaining characters
    for (name[1..], 0..) |c, i| {
        const prev_was_upper = std.ascii.isUpper(name[i]); // check previous char in source

        // Add underscore before uppercase letters when needed
        if (std.ascii.isUpper(c) and
            result.items.len > 0 and
            result.items[result.items.len - 1] != '_' and
            !prev_was_upper)
        {
            try result.append(allocator, '_');
        }

        // Preserve single underscores
        if (c == '_' and
            result.items.len > 0 and
            result.items[result.items.len - 1] != '_')
        {
            try result.append(allocator, '_');
            continue;
        }

        // Convert alphanumeric chars to uppercase
        if (std.ascii.isAlphanumeric(c)) {
            try result.append(allocator, std.ascii.toUpper(c));
        }
    }

    // Remove trailing underscore if present
    if (result.items.len > 0 and result.items[result.items.len - 1] == '_') {
        _ = result.pop();
    }

    return result.toOwnedSlice(allocator);
}

/// Convert a name to snake_case for struct fields
fn makeZigSnakeCase(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, name.len * 2);
    defer result.deinit(allocator);

    // Convert input to snake_case
    for (name, 0..) |c, i| {
        if (i == 0) {
            // First character must be a-zA-Z_
            if (std.ascii.isDigit(c)) {
                try result.append(allocator, '_');
            }
            if (std.ascii.isAlphabetic(c) or std.ascii.isDigit(c) or c == '_') {
                try result.appendSlice(allocator, &.{std.ascii.toLower(c)});
            } else {
                try result.append(allocator, '_');
            }
            continue;
        }

        // Add underscore before capital letters (camelCase -> snake_case)
        if (std.ascii.isUpper(c) and i > 0 and result.items[result.items.len - 1] != '_') {
            try result.append(allocator, '_');
        }

        // Convert to lowercase and handle special characters
        if (std.ascii.isAlphanumeric(c)) {
            try result.appendSlice(allocator, &.{std.ascii.toLower(c)});
        } else {
            try result.append(allocator, '_');
        }

        // Collapse multiple underscores
        if (result.items.len >= 2 and
            result.items[result.items.len - 1] == '_' and
            result.items[result.items.len - 2] == '_')
        {
            _ = result.pop();
        }
    }

    // Append underscore to keyword names
    const slice = try result.toOwnedSlice(allocator);
    if (isKeyword(slice)) {
        const with_underscore = try std.fmt.allocPrint(allocator, "{s}_", .{slice});
        allocator.free(slice);
        return with_underscore;
    }
    return slice;
}

/// Convert a name to camelCase for methods or PascalCase for types
fn makeZigCamelCase(allocator: std.mem.Allocator, name: []const u8, start_upper: bool) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, name.len * 2);
    errdefer result.deinit(allocator);

    var capitalize_next = false;

    for (name, 0..) |c, i| {
        if (i == 0) {
            // Handle first character
            if (std.ascii.isDigit(c)) {
                try result.append(allocator, '_');
            }
            if (std.ascii.isAlphabetic(c) or std.ascii.isDigit(c) or c == '_') {
                if (start_upper) {
                    try result.appendSlice(allocator, &.{std.ascii.toUpper(c)});
                } else {
                    try result.appendSlice(allocator, &.{std.ascii.toLower(c)});
                }
            } else {
                try result.append(allocator, '_');
            }
            continue;
        }

        // Handle special characters and capitalization
        if (c == '_' or !std.ascii.isAlphanumeric(c)) {
            capitalize_next = true;
            continue;
        }

        if (capitalize_next) {
            try result.appendSlice(allocator, &.{std.ascii.toUpper(c)});
            capitalize_next = false;
        } else {
            try result.append(allocator, c);
        }
    }

    // Append underscore to keyword names
    const slice = try result.toOwnedSlice(allocator);
    if (isKeyword(slice)) {
        const with_underscore = try std.fmt.allocPrint(allocator, "{s}_", .{slice});
        allocator.free(slice);
        return with_underscore;
    }
    return slice;
}

/// Check if a name exists in the list of used names
fn containsName(used_names: *std.ArrayList([]const u8), name: []const u8) bool {
    for (used_names.items) |existing| {
        if (std.mem.eql(u8, existing, name)) {
            return true;
        }
    }
    return false;
}

/// Generate a unique name by appending numbers if needed
fn getUnusedName(allocator: std.mem.Allocator, used_names: *std.ArrayList([]const u8), base_name: []const u8) ![]const u8 {
    // Try base name first
    if (!containsName(used_names, base_name)) {
        const result = try allocator.dupe(u8, base_name);
        try used_names.append(allocator, result);
        return result;
    }

    // Append numbers until we find an unused name
    var counter: usize = 1;
    while (true) {
        const new_name = try std.fmt.allocPrint(allocator, "{s}{d}", .{ base_name, counter });

        if (!containsName(used_names, new_name)) {
            try used_names.append(allocator, new_name);
            return new_name;
        }

        allocator.free(new_name);
        counter += 1;
    }
}

// Public interface functions

/// Convert a Protocol Buffer name to a Zig constant name (SCREAMING_SNAKE_CASE)
pub fn constName(allocator: std.mem.Allocator, proto_name: []const u8, used_names: *std.ArrayList([]const u8)) ![]const u8 {
    const name = try makeZigConstName(allocator, proto_name);
    defer allocator.free(name);
    return try getUnusedName(allocator, used_names, name);
}

/// Convert a Protocol Buffer name to a Zig struct name (PascalCase)
pub fn structName(allocator: std.mem.Allocator, proto_name: []const u8, used_names: *std.ArrayList([]const u8)) ![]const u8 {
    const name = try makeZigCamelCase(allocator, proto_name, true);
    defer allocator.free(name);
    return try getUnusedName(allocator, used_names, name);
}

/// Convert a Protocol Buffer name to a Zig enum field name (SCREAMING_SNAKE_CASE)
pub fn enumFieldName(allocator: std.mem.Allocator, proto_name: []const u8, used_names: *std.ArrayList([]const u8)) ![]const u8 {
    const name = try makeZigConstName(allocator, proto_name);
    defer allocator.free(name);
    return try getUnusedName(allocator, used_names, name);
}

/// Convert a Protocol Buffer name to a Zig struct field name (snake_case)
pub fn structFieldName(allocator: std.mem.Allocator, proto_name: []const u8, used_names: *std.ArrayList([]const u8)) ![]const u8 {
    const name = try makeZigSnakeCase(allocator, proto_name);
    defer allocator.free(name);
    return try getUnusedName(allocator, used_names, name);
}

/// Convert a Protocol Buffer name to a Zig method name (camelCase)
pub fn structMethodName(allocator: std.mem.Allocator, proto_name: []const u8, used_names: *std.ArrayList([]const u8)) ![]const u8 {
    const name = try makeZigCamelCase(allocator, proto_name, false);
    defer allocator.free(name);
    return try getUnusedName(allocator, used_names, name);
}

/// Convert a Protocol Buffer name to a Zig import alias (snake_case)
pub fn importAlias(allocator: std.mem.Allocator, proto_name: []const u8, used_names: *std.ArrayList([]const u8)) ![]const u8 {
    const name = try makeZigSnakeCase(allocator, proto_name);
    defer allocator.free(name);
    return try getUnusedName(allocator, used_names, name);
}

test "naming conventions" {
    const allocator = std.testing.allocator;
    var used_names = try std.ArrayList([]const u8).initCapacity(allocator, 32);
    defer {
        used_names.deinit(allocator);
    }

    // Test constName
    const name_const = try constName(allocator, "testName", &used_names);
    defer allocator.free(name_const);
    try std.testing.expectEqualStrings("TEST_NAME", name_const);

    // Test CONST_NAME
    const name_const1 = try constName(allocator, "TEST_NAME", &used_names);
    defer allocator.free(name_const1);
    try std.testing.expectEqualStrings("TEST_NAME1", name_const1);

    // Test enumFieldName
    const name_ef = try enumFieldName(allocator, "testName", &used_names);
    defer allocator.free(name_ef);
    try std.testing.expectEqualStrings("TEST_NAME2", name_ef);

    // Test structFieldName
    const name_sf = try structFieldName(allocator, "testName", &used_names);
    defer allocator.free(name_sf);
    try std.testing.expectEqualStrings("test_name", name_sf);

    // Test structMethodName
    const name_sm = try structMethodName(allocator, "test_name", &used_names);
    defer allocator.free(name_sm);
    try std.testing.expectEqualStrings("testName", name_sm);

    // Test keyword handling
    const name_keyword = try structFieldName(allocator, "for", &used_names);
    defer allocator.free(name_keyword);
    try std.testing.expectEqualStrings("for_", name_keyword);

    const name_keyword2 = try structMethodName(allocator, "while", &used_names);
    defer allocator.free(name_keyword2);
    try std.testing.expectEqualStrings("while_", name_keyword2);
}
