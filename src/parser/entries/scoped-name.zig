//! Scoped name handling module for Protocol Buffer definitions.
//! Provides utilities for parsing and manipulating fully qualified names
//! in Protocol Buffer definitions (e.g., "package.Message.SubMessage").

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

/// Possible errors when handling scoped names
pub const ScopedNameError = error{
    OutOfMemory,
};

/// Represents a fully qualified name in Protocol Buffer definitions.
/// Handles parsing and manipulation of names like "foo.bar.Baz".
pub const ScopedName = struct {
    /// Allocator for dynamic memory
    allocator: std.mem.Allocator,
    /// The local part of the name (rightmost component)
    name: []const u8,
    /// Parent components of the name (all but rightmost)
    parent: ?std.ArrayList([]const u8),

    /// Complete name including all parts
    full: []const u8,
    /// Whether full name was dynamically allocated
    full_owned: bool = false,

    /// Creates a new ScopedName from a string.
    /// Handles both simple names ("Message") and qualified names ("pkg.Message").
    ///
    /// # Arguments
    /// * `allocator` - Allocator for dynamic memory
    /// * `src` - Source string containing the name
    ///
    /// # Returns
    /// A new ScopedName instance
    ///
    /// # Errors
    /// Returns error.OutOfMemory if allocation fails
    pub fn init(allocator: std.mem.Allocator, src: []const u8) ScopedNameError!ScopedName {
        if (std.mem.containsAtLeast(u8, src, 1, ".")) {
            // Handle qualified names (contain dots)
            var iter = std.mem.splitBackwardsScalar(u8, src, '.');
            const name = iter.first();
            const rest = iter.rest();
            var rest_parts = std.mem.splitScalar(u8, rest, '.');

            var parent = try std.ArrayList([]const u8).initCapacity(allocator, 32);
            while (rest_parts.next()) |part| {
                try parent.append(allocator, part);
            }

            return ScopedName{
                .allocator = allocator,
                .name = name,
                .parent = parent,
                .full = src,
            };
        } else {
            // Handle simple names (no dots)
            return ScopedName{
                .allocator = allocator,
                .name = src,
                .parent = null,
                .full = src,
            };
        }
    }

    /// Creates a deep copy of the ScopedName
    pub fn clone(self: ScopedName) ScopedNameError!ScopedName {
        if (self.parent) |*p| {
            const parent = try p.clone(self.allocator);
            return ScopedName{
                .allocator = self.allocator,
                .name = self.name,
                .parent = parent,
                .full = try self.allocator.dupe(u8, self.full),
                .full_owned = true,
            };
        } else {
            return ScopedName{
                .allocator = self.allocator,
                .name = self.name,
                .parent = null,
                .full = try self.allocator.dupe(u8, self.full),
                .full_owned = true,
            };
        }
    }

    /// Creates a new ScopedName representing a child of this name
    /// For example: "foo.bar".child("baz") -> "foo.bar.baz"
    pub fn child(self: ScopedName, name: []const u8) ScopedNameError!ScopedName {
        const full = try std.mem.concat(self.allocator, u8, &[_][]const u8{ self.full, ".", name });

        if (self.parent) |*p| {
            var parent = try p.clone(self.allocator);
            try parent.append(self.allocator, self.name);

            return ScopedName{
                .allocator = self.allocator,
                .name = name,
                .parent = parent,
                .full = full,
                .full_owned = true,
            };
        } else {
            var parent = try std.ArrayList([]const u8).initCapacity(self.allocator, 1);
            try parent.append(self.allocator, self.name);

            return ScopedName{
                .allocator = self.allocator,
                .name = name,
                .parent = parent,
                .full = full,
                .full_owned = true,
            };
        }
    }

    /// Gets the parent scope of this name
    /// For example: "foo.bar.baz".getParent() -> "foo.bar"
    pub fn getParent(self: ScopedName) ScopedNameError!?ScopedName {
        if (self.parent) |*p| {
            if (p.items.len == 0) {
                return null;
            }

            var parent = try p.clone(self.allocator);
            const name = parent.pop().?;
            const full = try std.mem.join(self.allocator, ".", p.items);

            return ScopedName{
                .allocator = self.allocator,
                .name = name,
                .parent = parent,
                .full = full,
                .full_owned = true,
            };
        } else {
            return null;
        }
    }

    /// Checks if two scoped names are equivalent
    /// Handles both absolute paths (starting with dot) and relative paths
    pub fn eql(self: ScopedName, target: ScopedName) bool {
        if (std.mem.eql(u8, self.full, target.full)) {
            return true;
        }
        if (self.full[0] == '.' and target.full[0] == '.') {
            return false;
        }

        if (self.full[0] == '.' and std.mem.eql(u8, self.full[1..], target.full)) {
            return true;
        }
        if (target.full[0] == '.' and std.mem.eql(u8, self.full, target.full[1..])) {
            return true;
        }
        return false;
    }

    /// Resolves this name relative to a target scope
    /// For example: "Message".toScope("pkg.sub") -> "pkg.sub.Message"
    pub fn toScope(self: ScopedName, target: *ScopedName) ScopedNameError!ScopedName {
        if (target.full.len == 0) {
            return self.clone();
        }
        if (self.full[0] == '.') {
            return self.clone();
        }

        var path = try std.ArrayList([]const u8).initCapacity(self.allocator, 32);
        defer path.deinit(self.allocator);

        // Build full path by combining target scope and name
        if (target.parent) |*p| {
            try path.appendSlice(self.allocator, p.items);
        }
        if (target.name.len > 0) {
            try path.append(self.allocator, target.name);
        }
        if (self.parent) |*p| {
            try path.appendSlice(self.allocator, p.items);
        }
        try path.append(self.allocator, self.name);

        const full = try std.mem.join(self.allocator, ".", path.items);

        var res = try ScopedName.init(self.allocator, full);
        res.full_owned = true;

        return res;
    }

    /// Frees all resources owned by the ScopedName
    pub fn deinit(self: *ScopedName) void {
        if (self.parent) |*p| {
            p.deinit(self.allocator);
        }
        if (self.full_owned) {
            self.allocator.free(self.full);
        }
    }
};

test "basic scoped name" {
    var name = try ScopedName.init(std.testing.allocator, "foo");
    defer name.deinit();
    try std.testing.expectEqual(null, name.parent);
    try std.testing.expectEqualStrings("foo", name.name);
    try std.testing.expectEqualStrings("foo", name.full);
}

test "scoped name with parent" {
    var name = try ScopedName.init(std.testing.allocator, "foo.bar");
    defer name.deinit();
    try std.testing.expectEqualStrings("bar", name.name);
    try std.testing.expectEqualStrings("foo.bar", name.full);
    try std.testing.expectEqual(1, name.parent.?.items.len);
    try std.testing.expectEqualStrings("foo", name.parent.?.items[0]);
}

test "scoped name operations" {
    // Test child creation
    {
        var parent = try ScopedName.init(std.testing.allocator, "foo");
        defer parent.deinit();
        var child_name = try parent.child("bar");
        defer child_name.deinit();
        try std.testing.expectEqualStrings("foo.bar", child_name.full);
    }

    // Test parent retrieval
    {
        var name = try ScopedName.init(std.testing.allocator, "foo.bar.baz");
        defer name.deinit();
        var parent = try name.getParent();
        defer parent.?.deinit();
        try std.testing.expectEqualStrings("foo.bar", parent.?.full);
    }

    // Test scope resolution
    {
        var name = try ScopedName.init(std.testing.allocator, "Message");
        defer name.deinit();
        var scope = try ScopedName.init(std.testing.allocator, "pkg.sub");
        defer scope.deinit();
        var resolved = try name.toScope(&scope);
        defer resolved.deinit();
        try std.testing.expectEqualStrings("pkg.sub.Message", resolved.full);
    }
}
