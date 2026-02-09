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
// Created by ab, 10.06.2024

const std = @import("std");
const ProtoFile = @import("../entries/file.zig").ProtoFile;
const import = @import("../entries/import.zig");
const ParserBuffer = @import("../entries/buffer.zig").ParserBuffer;
const well_known_types = @import("../well_known_types.zig");

pub const ResolveError = error{
    TargetFileNotFound,
    OutOfMemory,
    CurrentWorkingDirectoryUnlinked,
    Unexpected,
};

/// ImportResolver handles resolving imports between protobuf files
const ImportResolver = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    files: *std.ArrayList(ProtoFile),
    files_map: std.StringHashMap(*ProtoFile),

    fn init(
        allocator: std.mem.Allocator,
        base_path: []const u8,
        files: *std.ArrayList(ProtoFile),
    ) !*ImportResolver {
        var self = try allocator.create(ImportResolver);
        self.* = .{
            .allocator = allocator,
            .base_path = base_path,
            .files = files,
            .files_map = std.StringHashMap(*ProtoFile).init(allocator),
        };

        try self.rebuildFilesMap();
        return self;
    }

    fn rebuildFilesMap(self: *ImportResolver) !void {
        self.files_map.clearRetainingCapacity();
        for (self.files.items) |*file| {
            if (file.path) |path| {
                try self.files_map.put(path, file);
            }
        }
    }

    fn deinit(self: *ImportResolver) void {
        self.files_map.deinit();
        self.allocator.destroy(self);
    }

    /// First pass: collect and parse all needed well-known types before resolving
    fn collectWellKnownTypes(self: *ImportResolver) !void {
        // Collect unique well-known import paths
        var needed = std.StringHashMap(void).init(self.allocator);
        defer needed.deinit();

        for (self.files.items) |*file| {
            for (file.imports.items) |*import_item| {
                if (well_known_types.isWellKnownImport(import_item.path)) {
                    try needed.put(import_item.path, {});
                }
            }
        }

        // Parse and add all needed well-known types
        var iter = needed.keyIterator();
        while (iter.next()) |path| {
            if (well_known_types.get(path.*)) |content| {
                var buffer = ParserBuffer.init(content);
                var proto_file = ProtoFile.parse(self.allocator, &buffer) catch continue;
                proto_file.path = try self.allocator.dupe(u8, path.*);
                try self.files.append(self.allocator, proto_file);
            }
        }

        // Rebuild the map now that all files are added
        try self.rebuildFilesMap();
    }

    fn resolveTargetFiles(self: *ImportResolver) ResolveError!void {
        for (self.files.items) |*file| {
            try self.resolveFileImports(file);
        }
    }

    fn resolveFileImports(self: *ImportResolver, file: *ProtoFile) ResolveError!void {
        const file_path = file.path orelse return;

        // Resolve each import
        for (file.imports.items) |*import_item| {
            try self.resolveImport(file_path, import_item);
        }
    }

    fn resolveImport(
        self: *ImportResolver,
        file_path: []const u8,
        import_item: *import.Import,
    ) ResolveError!void {
        // For well-known types, the path is the key directly
        if (well_known_types.isWellKnownImport(import_item.path)) {
            if (self.files_map.get(import_item.path)) |target| {
                import_item.target = target;
                return;
            }
        }

        // Build full target path for regular imports
        const target_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.base_path,
            import_item.path,
        });
        defer self.allocator.free(target_path);

        // Look up target file
        if (self.files_map.get(target_path)) |target| {
            import_item.target = target;
        } else {
            std.debug.print("cannot resolve import {s} from {s} with root {s}\n", .{ import_item.path, file_path, self.base_path });
            return ResolveError.TargetFileNotFound;
        }
    }

    fn resolvePublicImports(self: *ImportResolver) !void {
        for (self.files.items) |*file| {
            try self.resolveFilePublicImports(file);
        }
    }

    fn resolveFilePublicImports(self: *ImportResolver, file: *ProtoFile) !void {
        for (file.imports.items) |*import_item| {
            const target = import_item.target orelse continue;
            try self.propagatePublicImports(file, target);
        }
    }

    fn propagatePublicImports(
        self: *ImportResolver,
        file: *ProtoFile,
        target: *ProtoFile,
    ) !void {
        for (target.imports.items) |*target_import| {
            if (target_import.i_type != import.ImportType.public) continue;

            try file.imports.append(self.allocator, import.Import{
                .start = 0,
                .end = 0,
                .path = target_import.path,
                .i_type = import.ImportType.public,
                .target = target_import.target,
            });
        }
    }
};

/// Resolves imports between protobuf files
pub fn resolveImports(
    allocator: std.mem.Allocator,
    base: []const u8,
    files: *std.ArrayList(ProtoFile),
) ResolveError!void {
    var resolver = try ImportResolver.init(allocator, base, files);
    defer resolver.deinit();

    // First: parse and add all needed well-known types
    try resolver.collectWellKnownTypes();

    // Then: resolve all imports (safe now, no more appends to files)
    try resolver.resolveTargetFiles();
    try resolver.resolvePublicImports();
}
