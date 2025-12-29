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

        // Build lookup map of files by path
        for (files.items) |*file| {
            if (file.path) |path| {
                try self.files_map.put(path, file);
            }
        }

        return self;
    }

    fn deinit(self: *ImportResolver) void {
        self.files_map.deinit();
        self.allocator.destroy(self);
    }

    fn resolveTargetFiles(self: *ImportResolver) ResolveError!void {
        for (self.files.items) |*file| {
            try self.resolveFileImports(file);
        }
    }

    fn resolveFileImports(self: *ImportResolver, file: *ProtoFile) ResolveError!void {
        const file_path = file.path orelse return;

        // Get relative path from base to file
        const rel_path = try std.fs.path.relative(self.allocator, self.base_path, file_path);
        defer self.allocator.free(rel_path);

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
        // Build full target path
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

    try resolver.resolveTargetFiles();
    try resolver.resolvePublicImports();
}
