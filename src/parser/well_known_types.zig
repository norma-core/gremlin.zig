//! Embedded well-known Google Protocol Buffer types.
//! These are bundled at compile time so they can be used for import resolution
//! without requiring external file dependencies.

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
// Created by ab, 09.02.2026

const std = @import("std");

/// Well-known type entry containing the import path and embedded content
pub const WellKnownType = struct {
    path: []const u8,
    content: []const u8,
};

/// All embedded well-known Google protobuf types
pub const types = [_]WellKnownType{
    .{ .path = "google/protobuf/any.proto", .content = @embedFile("google/protobuf/any.proto") },
    .{ .path = "google/protobuf/api.proto", .content = @embedFile("google/protobuf/api.proto") },
    .{ .path = "google/protobuf/descriptor.proto", .content = @embedFile("google/protobuf/descriptor.proto") },
    .{ .path = "google/protobuf/duration.proto", .content = @embedFile("google/protobuf/duration.proto") },
    .{ .path = "google/protobuf/empty.proto", .content = @embedFile("google/protobuf/empty.proto") },
    .{ .path = "google/protobuf/field_mask.proto", .content = @embedFile("google/protobuf/field_mask.proto") },
    .{ .path = "google/protobuf/source_context.proto", .content = @embedFile("google/protobuf/source_context.proto") },
    .{ .path = "google/protobuf/struct.proto", .content = @embedFile("google/protobuf/struct.proto") },
    .{ .path = "google/protobuf/timestamp.proto", .content = @embedFile("google/protobuf/timestamp.proto") },
    .{ .path = "google/protobuf/type.proto", .content = @embedFile("google/protobuf/type.proto") },
    .{ .path = "google/protobuf/wrappers.proto", .content = @embedFile("google/protobuf/wrappers.proto") },
};

/// Look up a well-known type by its import path
pub fn get(path: []const u8) ?[]const u8 {
    for (types) |wkt| {
        if (std.mem.eql(u8, wkt.path, path)) {
            return wkt.content;
        }
    }
    return null;
}

/// Check if a path refers to a well-known Google protobuf type
pub fn isWellKnownImport(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "google/protobuf/");
}

test "get well-known type" {
    const any = get("google/protobuf/any.proto");
    try std.testing.expect(any != null);
    try std.testing.expect(std.mem.indexOf(u8, any.?, "message Any") != null);

    const missing = get("google/protobuf/nonexistent.proto");
    try std.testing.expect(missing == null);
}

test "isWellKnownImport" {
    try std.testing.expect(isWellKnownImport("google/protobuf/any.proto"));
    try std.testing.expect(isWellKnownImport("google/protobuf/timestamp.proto"));
    try std.testing.expect(!isWellKnownImport("my/custom.proto"));
    try std.testing.expect(!isWellKnownImport("google/api/annotations.proto"));
}
