//! This module handles type resolution and extension handling for Protocol Buffer files.
//! It provides functionality to:
//! - Find and resolve message and enum types across files
//! - Handle message extensions and field inheritance
//! - Set up parent-child relationships between nested types

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

// Type imports
const ProtoFile = @import("entries/file.zig").ProtoFile;
const Message = @import("entries/message.zig").Message;
const Enum = @import("entries/enum.zig").Enum;
const Extend = @import("entries/extend.zig").Extend;
const Error = @import("entries/errors.zig").Error;
const ScopedName = @import("entries/scoped-name.zig").ScopedName;
const ParserBuffer = @import("entries/buffer.zig").ParserBuffer;
const FieldType = @import("entries/field-type.zig").FieldType;

/// Resolve all type references and extensions across a set of proto files.
/// This is done in two passes:
/// 1. Resolve all extensions to handle field inheritance
/// 2. Resolve all type references to link fields to their type definitions
pub fn resolveReferences(files: *std.ArrayList(ProtoFile)) !void {
    // First pass: resolve all extensions
    for (files.items) |*file| {
        try resolveExtend(file);
    }

    // Second pass: resolve all type references
    for (files.items) |*file| {
        try resolveRefs(file);
    }
}

/// Find an enum definition within a message and its nested messages
fn findEnumInMessage(message: *Message, name: ScopedName) ?*Enum {
    // Check direct enums in this message
    for (message.enums.items) |*e| {
        if (e.name.eql(name)) return e;
    }

    // Recursively check nested messages
    for (message.messages.items) |*msg| {
        if (findEnumInMessage(msg, name)) |res| return res;
    }

    return null;
}

/// Find an enum definition within a proto file
fn findEnum(file: *const ProtoFile, name: ScopedName) ?*Enum {
    // Check top-level enums
    for (file.enums.items) |*e| {
        if (e.name.eql(name)) return e;
    }

    // Check enums in messages
    for (file.messages.items) |*msg| {
        if (findEnumInMessage(msg, name)) |res| return res;
    }

    return null;
}

/// Find a message definition within another message
fn findMessageInMessage(message: *Message, name: ScopedName) ?*Message {
    if (message.name.eql(name)) return message;

    // Recursively check nested messages
    for (message.messages.items) |*msg| {
        if (findMessageInMessage(msg, name)) |res| return res;
    }

    return null;
}

/// Find a message definition within a proto file
fn findMessage(file: *ProtoFile, name: ScopedName) ?*Message {
    for (file.messages.items) |*msg| {
        if (findMessageInMessage(msg, name)) |res| return res;
    }
    return null;
}

/// Find an extendable message within another message
fn findExtendInMessage(message: *Message, name: ScopedName) ?*Message {
    if (message.name.eql(name)) return message;

    for (message.messages.items) |*msg| {
        if (findExtendInMessage(msg, name)) |res| return res;
    }

    return null;
}

/// Find a message that can be extended within a proto file
fn findExtendMessage(file: *ProtoFile, name: ScopedName) ?*Message {
    for (file.messages.items) |*msg| {
        if (findExtendInMessage(msg, name)) |res| {
            // Only return if message hasn't been extended yet
            if (res.extends.items.len == 0) return res;
        }
    }
    return null;
}

/// Find a local message that is being extended within the same file
fn findLocalExtendSource(file: *ProtoFile, messageName: ScopedName, extendBase: ScopedName) Error!?*Message {
    var searchPath: ?ScopedName = try messageName.clone();
    defer if (searchPath) |*s| s.deinit();

    while (searchPath) |*s| {
        var name = try extendBase.toScope(s);
        defer name.deinit();

        for (file.messages.items) |*msg| {
            if (findExtendInMessage(msg, name)) |res| {
                return res;
            }
        }

        const nextPath = try s.getParent();
        s.deinit();
        searchPath = nextPath;
    }

    return null;
}

/// Represents a message that can be extended and its containing file
const ExtendBase = struct {
    message: *Message,
    file: *ProtoFile,
};

/// Find the base message that is being extended
fn findExtendBase(file: *ProtoFile, message: *Message, ext: *Extend) Error!?ExtendBase {
    const local = try findLocalExtendSource(file, message.name, ext.base);
    if (local) |res| {
        return ExtendBase{
            .message = res,
            .file = file,
        };
    }

    for (file.imports.items) |*import| {
        if (import.target) |target_file| {
            if (findExtendMessage(target_file, ext.base)) |res| {
                return ExtendBase{
                    .message = res,
                    .file = target_file,
                };
            }
        }
    }

    return null;
}

/// Copy fields from extended message into the extending message
fn copyExtendedFields(message: *Message, target: ExtendBase) Error!void {
    // Copy normal fields
    for (target.message.fields.items) |source_field| {
        const field_exists = for (message.fields.items) |existing_field| {
            if (std.mem.eql(u8, existing_field.f_name, source_field.f_name)) break true;
        } else false;

        if (!field_exists) {
            var new_field = try source_field.clone();
            new_field.f_type.scope_ref = target.file;
            try message.fields.append(message.allocator, new_field);
        }
    }

    // Copy map fields
    for (target.message.maps.items) |source_map| {
        const map_exists = for (message.maps.items) |existing_map| {
            if (std.mem.eql(u8, existing_map.f_name, source_map.f_name)) break true;
        } else false;

        if (!map_exists) {
            var new_map = try source_map.clone();
            new_map.value_type.scope_ref = target.file;
            try message.maps.append(message.allocator, new_map);
        }
    }

    // Copy oneof fields
    for (target.message.oneofs.items) |source_oneof| {
        const oneof_exists = for (message.oneofs.items) |existing_oneof| {
            if (std.mem.eql(u8, existing_oneof.name, source_oneof.name)) break true;
        } else false;

        if (!oneof_exists) {
            const new_oneof = try source_oneof.clone();
            for (source_oneof.fields.items) |field| {
                var new_field = try field.clone();
                new_field.f_type.scope_ref = target.file;
            }
            try message.oneofs.append(message.allocator, new_oneof);
        }
    }
}

/// Resolve message extension relationships
fn resolveMessageExtend(file: *ProtoFile, message: *Message) Error!void {
    // Process this message's extensions
    for (message.extends.items) |*ext| {
        const target = try findExtendBase(file, message, ext);

        if (target) |t| {
            try copyExtendedFields(message, t);
        } else {
            return Error.ExtendSourceNotFound;
        }
    }

    // Process nested message extensions
    for (message.messages.items) |*msg| {
        try resolveMessageExtend(file, msg);
    }
}

/// Attempt to resolve a type locally within the same file
fn resolveLocalType(file: *ProtoFile, ftype: *FieldType) Error!bool {
    if (ftype.name) |name_to_search| {
        const scope = ftype.scope;
        var search_path: ?ScopedName = try scope.clone();
        defer if (search_path) |*sp| sp.deinit();

        while (search_path) |*sp| {
            var name = try name_to_search.toScope(sp);
            defer name.deinit();

            const target_file: *ProtoFile = if (ftype.scope_ref) |f| f else file;

            if (findEnum(target_file, name)) |res| {
                ftype.ref_local_enum = res;
                return true;
            } else if (findMessage(target_file, name)) |res| {
                ftype.ref_local_message = res;
                return true;
            }

            // Get next path and clean up current one
            const next_path = try sp.getParent();
            sp.deinit();
            search_path = next_path;
        }

        return false;
    }

    return Error.TypeNotFound;
}

/// Attempt to resolve a type in imported files
fn resolveExternalType(file: *ProtoFile, ftype: *FieldType) Error!bool {
    if (ftype.name) |name_to_search| {
        const target_file: *ProtoFile = if (ftype.scope_ref) |f| f else file;
        const scope = ftype.scope;

        for (target_file.imports.items) |*import| {
            if (import.target) |imported_file| {
                var search_path: ?ScopedName = try scope.clone();
                defer if (search_path) |*sp| sp.deinit();

                while (search_path) |*sp| {
                    var local_name = try name_to_search.toScope(sp);
                    defer local_name.deinit();

                    if (findEnum(imported_file, local_name)) |res| {
                        ftype.ref_external_enum = res;
                        ftype.ref_import = imported_file;
                        return true;
                    } else if (findMessage(imported_file, local_name)) |res| {
                        ftype.ref_external_message = res;
                        ftype.ref_import = imported_file;
                        return true;
                    }

                    // Get next path and clean up current one
                    const next_path = try sp.getParent();
                    sp.deinit();
                    search_path = next_path;
                }
            }
        }

        return false;
    }

    return Error.TypeNotFound;
}

/// Resolve a field type to its definition
fn resolveType(file: *ProtoFile, ftype: *FieldType) Error!void {
    if (ftype.is_scalar or ftype.is_bytes) return;

    if (try resolveLocalType(file, ftype)) return;
    if (try resolveExternalType(file, ftype)) return;

    return Error.TypeNotFound;
}

/// Resolve all field types within a message and its nested messages
fn resolveMessageFields(file: *ProtoFile, message: *Message) Error!void {
    // Resolve normal fields
    for (message.fields.items) |*f| {
        try resolveType(file, &f.f_type);
    }

    // Resolve map fields
    for (message.maps.items) |*f| {
        try resolveType(file, &f.value_type);
    }

    // Resolve oneof fields
    for (message.oneofs.items) |*o| {
        for (o.fields.items) |*f| {
            try resolveType(file, &f.f_type);
        }
    }

    // Resolve nested message fields
    for (message.messages.items) |*msg| {
        try resolveMessageFields(file, msg);
    }
}

/// Set up parent-child relationships between messages and their nested types
fn resolveMessageParents(message: *Message) !void {
    for (message.messages.items) |*msg| {
        msg.parent = message;
        try resolveMessageParents(msg);
    }
    for (message.enums.items) |*e| {
        e.parent = message;
    }
}

/// Resolve extensions in a file
fn resolveExtend(file: *ProtoFile) !void {
    for (file.messages.items) |*message| {
        try resolveMessageExtend(file, message);
    }
}

/// Resolve all type references in a file
fn resolveRefs(file: *ProtoFile) !void {
    for (file.messages.items) |*message| {
        try resolveMessageFields(file, message);
        try resolveMessageParents(message);
    }
}

test "local extend" {
    var buf = ParserBuffer.init(
        \\message A {
        \\  message B {
        \\    extend C {
        \\    }
        \\  }
        \\
        \\  message C {
        \\  }
        \\}
    );
    var pf = try ProtoFile.parse(std.testing.allocator, &buf);
    defer pf.deinit();

    var extend = try ScopedName.init(std.testing.allocator, "C");
    defer extend.deinit();

    var target = try ScopedName.init(std.testing.allocator, "A.B.C");
    defer target.deinit();

    const msg = try findLocalExtendSource(&pf, target, extend) orelse unreachable;
    try std.testing.expectEqualStrings("C", msg.name.name);
    try std.testing.expectEqualStrings(".A.C", msg.name.full);
}

test "basic extend fields" {
    var buf = ParserBuffer.init(
        \\message A {
        \\  message B {
        \\    extend C {
        \\    }
        \\  }
        \\
        \\  message C {
        \\    D d = 1;
        \\  }
        \\  message D {
        \\  }
        \\}
    );
    var pf = try ProtoFile.parse(std.testing.allocator, &buf);
    defer pf.deinit();

    try resolveExtend(&pf);
    try resolveRefs(&pf);

    const fields = pf.messages.items[0].messages.items[0].fields.items;
    try std.testing.expect(fields.len == 1);
    try std.testing.expectEqualStrings("d", fields[0].f_name);
}

test "local enum resolve" {
    var buf = ParserBuffer.init(
        \\ package a.b.c;
        \\
        \\ enum E {
        \\   A = 1;
        \\ }
        \\
        \\ message M {
        \\   E e = 1;
        \\ }
    );
    var pf = try ProtoFile.parse(std.testing.allocator, &buf);
    defer pf.deinit();

    try resolveRefs(&pf);

    const f = pf.messages.items[0].fields.items[0];
    try std.testing.expect(f.f_type.ref_local_enum != null);
}

test "local msg reslove" {
    var buf = ParserBuffer.init(
        \\ package a.b.c;
        \\
        \\ message M {
        \\   message N {
        \\   }
        \\ }
        \\
        \\ message O {
        \\   M.N n = 1;
        \\ }
    );
    var pf = try ProtoFile.parse(std.testing.allocator, &buf);
    defer pf.deinit();

    try resolveRefs(&pf);

    const f = pf.messages.items[1].fields.items[0];
    try std.testing.expect(f.f_type.ref_local_message != null);
}

test "import enum resolve" {
    var buf1 = ParserBuffer.init(
        \\ package a.b.c;
        \\
        \\ enum E {
        \\   A = 1;
        \\ }
    );

    var buf2 = ParserBuffer.init(
        \\ package a.b.c;
        \\
        \\ import "c.proto";
        \\
        \\ message M {
        \\   E e = 1;
        \\ }
    );

    var pf1 = try ProtoFile.parse(std.testing.allocator, &buf1);
    defer pf1.deinit();

    var pf2 = try ProtoFile.parse(std.testing.allocator, &buf2);
    defer pf2.deinit();

    pf2.imports.items[0].target = &pf1;

    try resolveRefs(&pf2);

    const f = pf2.messages.items[0].fields.items[0];
    try std.testing.expect(f.f_type.ref_external_enum != null);
    try std.testing.expect(f.f_type.ref_import != null);
}

test "import enum package resolve" {
    var buf1 = ParserBuffer.init(
        \\ package p1;
        \\
        \\ enum E {
        \\   A = 1;
        \\ }
    );

    var buf2 = ParserBuffer.init(
        \\ package p2;
        \\
        \\ import "c.proto";
        \\
        \\ message M {
        \\   p1.E e = 1;
        \\ }
    );

    var pf1 = try ProtoFile.parse(std.testing.allocator, &buf1);
    defer pf1.deinit();

    var pf2 = try ProtoFile.parse(std.testing.allocator, &buf2);
    defer pf2.deinit();

    pf2.imports.items[0].target = &pf1;

    try resolveRefs(&pf2);

    const f = pf2.messages.items[0].fields.items[0];
    try std.testing.expect(f.f_type.ref_external_enum != null);
    try std.testing.expect(f.f_type.ref_import != null);
}

test "import same package resolve" {
    var buf1 = ParserBuffer.init(
        \\ package p1.p2;
        \\
        \\ enum E {
        \\   A = 1;
        \\ }
    );

    var buf2 = ParserBuffer.init(
        \\ package p1.p2;
        \\
        \\ import "c.proto";
        \\
        \\ message M {
        \\   .p1.p2.E e = 1;
        \\ }
    );

    var pf1 = try ProtoFile.parse(std.testing.allocator, &buf1);
    defer pf1.deinit();

    var pf2 = try ProtoFile.parse(std.testing.allocator, &buf2);
    defer pf2.deinit();

    pf2.imports.items[0].target = &pf1;

    try resolveRefs(&pf2);

    const f = pf2.messages.items[0].fields.items[0];
    try std.testing.expect(f.f_type.ref_external_enum != null);
    try std.testing.expect(f.f_type.ref_import != null);
}

test "local enum proto2 resolve" {
    var buf = ParserBuffer.init(
        \\ syntax = "proto2";
        \\
        \\ enum GGType {
        \\     gg_generic   = 1;
        \\     gg_other1    = 2;
        \\     gg_other2    = 3;
        \\ }
        \\ message Usage {
        \\    optional GGType     ggtype = 2 [default = gg_generic];
        \\ }
    );
    var pf = try ProtoFile.parse(std.testing.allocator, &buf);
    defer pf.deinit();

    try resolveRefs(&pf);

    const f = pf.messages.items[0].fields.items[0];
    try std.testing.expect(f.f_type.ref_local_enum != null);
}
