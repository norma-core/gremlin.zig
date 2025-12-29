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
// Created by ab, 13.06.2024

const std = @import("std");

/// Finds all .proto files recursively starting from the given base path
/// Returns an ArrayList containing the absolute paths to all found .proto files
/// Caller owns the returned ArrayList and must call deinit() on it
pub fn findProtoFiles(allocator: std.mem.Allocator, basePath: []const u8) !std.ArrayList([]const u8) {
    var dir = try std.fs.cwd().openDir(basePath, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var paths = try std.ArrayList([]const u8).initCapacity(allocator, 128);
    errdefer {
        for (paths.items) |path| {
            allocator.free(path);
        }
        paths.deinit(allocator);
    }

    // Walk through all files and directories recursively
    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, std.fs.path.extension(entry.basename), ".proto")) {
            const path = try dir.realpathAlloc(allocator, entry.path);
            try paths.append(allocator, path);
        }
    }

    return paths;
}

/// Represents a node in the filesystem tree
/// Used internally by findRoot to build a tree structure of the file paths
const FsNode = struct {
    allocator: ?std.mem.Allocator = null,
    path: []const u8,
    children: std.ArrayList(FsNode),
    files: usize, // Number of .proto files under this node

    /// Recursively frees all memory associated with this node and its children
    fn deinit(self: *FsNode) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit(self.allocator.?);
        if (self.allocator) |a| {
            a.free(self.path);
        }
    }

    /// Creates a new FsNode with the given path
    fn init(allocator: std.mem.Allocator, path: []const u8) !FsNode {
        return FsNode{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .children = try std.ArrayList(FsNode).initCapacity(allocator, 32),
            .files = 0,
        };
    }

    /// Finds or creates a child node with the given path part
    fn findOrCreateChild(self: *FsNode, part: []const u8) !*FsNode {
        const full_path = try std.fs.path.join(self.allocator.?, &[_][]const u8{ self.path, part });
        defer self.allocator.?.free(full_path);

        // Try to find existing child
        for (self.children.items) |*child| {
            if (std.mem.eql(u8, child.path, full_path)) {
                return child;
            }
        }

        // Create new child if not found
        const new_node = try FsNode.init(self.allocator.?, full_path);
        try self.children.append(self.allocator.?, new_node);
        return &self.children.items[self.children.items.len - 1];
    }
};

/// Possible errors that can occur during root finding
const Error = error{
    CannotFindRoot,
    NoCommonRoot,
    OutOfMemory,
    Unexpected,
    CurrentWorkingDirectoryUnlinked,
};

/// Finds the common root directory of all given paths
/// Returns the path to the deepest common directory
/// Caller owns the returned string and must free it
pub fn findRoot(
    allocator: std.mem.Allocator,
    paths: std.ArrayList([]const u8),
) Error![]const u8 {
    // Initialize root node with separator
    var root = try FsNode.init(allocator, std.fs.path.sep_str);
    defer root.deinit();

    // Build tree structure from paths
    for (paths.items) |path| {
        var current = &root;

        const dir = std.fs.path.dirname(path) orelse return Error.CannotFindRoot;

        // Split path into parts and create nodes
        var parts = std.mem.splitScalar(u8, dir, std.fs.path.sep);
        while (parts.next()) |part| {
            if (part.len == 0) continue;
            current = try current.findOrCreateChild(part);
        }
        current.files += 1;
    }

    // Find the deepest common directory
    var target = &root;
    while (target.children.items.len == 1 and target.files == 0) {
        target = &target.children.items[0];
    }

    if (target.children.items.len == 0) {
        return Error.NoCommonRoot;
    }

    return allocator.dupe(u8, target.path);
}

test "walk" {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fs.realpath(".", &path_buffer);

    var entries = try findProtoFiles(std.testing.allocator, path);
    defer {
        for (entries.items) |entry| {
            std.testing.allocator.free(entry);
        }
        entries.deinit(std.testing.allocator);
    }

    try std.testing.expect(entries.items.len > 0);
    for (entries.items) |entry| {
        try std.testing.expect(entry.len > 0);
        try std.testing.expectStringStartsWith(entry, path);
    }
}

test "find root" {
    var paths = try std.ArrayList([]const u8).initCapacity(std.testing.allocator, 2);
    defer paths.deinit(std.testing.allocator);

    try paths.append(std.testing.allocator, "/a/b/c/d");
    try paths.append(std.testing.allocator, "/a/b/d/c");

    const root = try findRoot(std.testing.allocator, paths);
    defer std.testing.allocator.free(root);

    try std.testing.expectEqualStrings("/a/b", root);
}
