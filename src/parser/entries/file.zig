//! Protocol Buffer file parser module.
//! Handles parsing complete .proto files, including all definitions like
//! packages, imports, messages, enums, services, and options.

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
// Created by ab, 12.06.2024

const std = @import("std");
const ParserBuffer = @import("buffer.zig").ParserBuffer;
const Error = @import("errors.zig").Error;
const Syntax = @import("syntax.zig").Syntax;
const Enum = @import("enum.zig").Enum;
const Message = @import("message.zig").Message;
const Import = @import("import.zig").Import;
const Package = @import("package.zig").Package;
const Option = @import("option.zig").Option;
const Service = @import("service.zig").Service;
const Edition = @import("edition.zig").Edition;
const Extend = @import("extend.zig").Extend;
const ScopedName = @import("scoped-name.zig").ScopedName;

/// Represents a complete Protocol Buffer definition file.
/// Contains all declarations and definitions found in a .proto file.
pub const ProtoFile = struct {
    /// Protocol buffer syntax version (proto2/proto3)
    syntax: ?Syntax,
    /// Package declaration (e.g., "foo.bar")
    package: ?Package,
    /// Edition declaration (e.g., "2023")
    edition: ?Edition,
    /// File path for imports
    path: ?[]const u8,

    /// Allocator for dynamic memory
    allocator: std.mem.Allocator,
    /// File-level options
    options: std.ArrayList(Option),
    /// Import statements
    imports: std.ArrayList(Import),
    /// Enum definitions
    enums: std.ArrayList(Enum),
    /// Message definitions
    messages: std.ArrayList(Message),
    /// Extend blocks
    extends: std.ArrayList(Extend),

    /// Parses a complete Protocol Buffer file.
    /// Handles all top-level declarations including syntax, package, imports,
    /// messages, enums, services, and options.
    ///
    /// The parser processes declarations in any order and validates that
    /// certain declarations (syntax, package, edition) appear only once.
    ///
    /// # Errors
    /// - PackageAlreadyDefined if multiple package statements
    /// - EditionAlreadyDefined if multiple edition statements
    /// - UnexpectedToken if unknown content encountered
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer) Error!ProtoFile {
        try buf.skipSpaces();

        // Initialize storage for all possible declarations
        var syntax: ?Syntax = null;
        var package: ?Package = null;
        var edition: ?Edition = null;
        var imports = try std.ArrayList(Import).initCapacity(allocator, 32);
        var enums = try std.ArrayList(Enum).initCapacity(allocator, 32);
        var messages = try std.ArrayList(Message).initCapacity(allocator, 32);
        var options = try std.ArrayList(Option).initCapacity(allocator, 32);
        var extends = try std.ArrayList(Extend).initCapacity(allocator, 32);

        // Parse syntax version if present
        if (try Syntax.parse(buf)) |s| {
            syntax = s;
        }

        // Start with empty scope
        var scope: ScopedName = try ScopedName.init(allocator, "");

        // Parse declarations until end of file
        while (true) {
            try buf.skipSpaces();
            var found = false;

            // Try parsing each type of declaration
            if (try Package.parse(allocator, buf)) |p| {
                if (package != null) {
                    return Error.PackageAlreadyDefined;
                }
                package = p;
                scope = p.name;
                found = true;
            }

            if (try Edition.parse(buf)) |e| {
                if (edition != null) {
                    return Error.EditionAlreadyDefined;
                }
                edition = e;
                found = true;
            }

            if (try Import.parse(buf)) |i| {
                try imports.append(allocator, i);
                found = true;
            }

            if (try Message.parse(allocator, buf, scope)) |m| {
                try messages.append(allocator, m);
                found = true;
            }

            if (try Enum.parse(allocator, buf, scope)) |e| {
                try enums.append(allocator, e);
                found = true;
            }

            if (try Option.parse(buf)) |o| {
                try options.append(allocator, o);
                found = true;
            }

            if (try Service.parse(buf)) |_| {
                found = true;
            }

            if (try Extend.parse(allocator, buf)) |e| {
                try extends.append(allocator, e);
                found = true;
            }

            // Handle end of declarations
            const c = try buf.char();
            if (c == ';') {
                buf.offset += 1;
                found = true;
            } else if (c == null) {
                break;
            }

            if (!found) {
                return Error.UnexpectedToken;
            }
        }

        return ProtoFile{
            .allocator = allocator,
            .path = null,
            .syntax = syntax,
            .package = package,
            .options = options,
            .edition = edition,
            .imports = imports,
            .enums = enums,
            .extends = extends,
            .messages = messages,
        };
    }

    /// Frees all resources owned by the ProtoFile
    pub fn deinit(self: *ProtoFile) void {
        for (self.enums.items) |*i| {
            i.deinit();
        }
        for (self.messages.items) |*i| {
            i.deinit();
        }
        for (self.extends.items) |*e| {
            e.deinit();
        }
        if (self.path) |p| {
            self.allocator.free(p);
        }
        if (self.package) |*p| {
            p.deinit();
        }

        self.options.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.enums.deinit(self.allocator);
        self.messages.deinit(self.allocator);
        self.extends.deinit(self.allocator);
    }
};

test "basic proto file" {
    var buf = ParserBuffer.init("syntax = \"proto3\"; package foo; message Bar {}");
    var result = try ProtoFile.parse(
        std.testing.allocator,
        &buf,
    );
    defer result.deinit();

    try std.testing.expect(result.syntax != null);
    try std.testing.expect(result.package != null);
    try std.testing.expectEqualStrings(".foo", result.package.?.name.full);
    try std.testing.expect(result.options.items.len == 0);
    try std.testing.expect(result.imports.items.len == 0);
    try std.testing.expect(result.enums.items.len == 0);
    try std.testing.expect(result.messages.items.len == 1);
}

test "golden proto3" {
    const file_content = @embedFile("test/proto3.proto");
    var buf = ParserBuffer.init(file_content);
    var pf = try ProtoFile.parse(std.testing.allocator, &buf);
    defer pf.deinit();

    try std.testing.expectEqualStrings("2023", pf.edition.?.edition);
    try std.testing.expectEqualStrings(".protobuf_test_messages.editions.proto3", pf.package.?.name.full);

    try std.testing.expectEqual(6, pf.imports.items.len);
    try std.testing.expectEqualStrings("protobuf/any.proto", pf.imports.items[0].path);
    try std.testing.expectEqualStrings("protobuf/duration.proto", pf.imports.items[1].path);
    try std.testing.expectEqualStrings("protobuf/field_mask.proto", pf.imports.items[2].path);
    try std.testing.expectEqualStrings("protobuf/struct.proto", pf.imports.items[3].path);
    try std.testing.expectEqualStrings("protobuf/timestamp.proto", pf.imports.items[4].path);
    try std.testing.expectEqualStrings("protobuf/wrappers.proto", pf.imports.items[5].path);

    try std.testing.expectEqual(4, pf.options.items.len);
    // option features.field_presence = IMPLICIT;
    try std.testing.expectEqualStrings("features.field_presence", pf.options.items[0].name);
    try std.testing.expectEqualStrings("IMPLICIT", pf.options.items[0].value);
    // option java_package = "com.google.protobuf_test_messages.editions.proto3";
    try std.testing.expectEqualStrings("java_package", pf.options.items[1].name);
    try std.testing.expectEqualStrings("\"com.google.protobuf_test_messages.editions.proto3\"", pf.options.items[1].value);
    // option objc_class_prefix = "EditionsProto3";
    try std.testing.expectEqualStrings("objc_class_prefix", pf.options.items[2].name);
    try std.testing.expectEqualStrings("\"EditionsProto3\"", pf.options.items[2].value);
    // option optimize_for = SPEED;
    try std.testing.expectEqualStrings("optimize_for", pf.options.items[3].name);
    try std.testing.expectEqualStrings("SPEED", pf.options.items[3].value);

    //enum ForeignEnum {
    //     FOREIGN_FOO = 0;
    //     FOREIGN_BAR = 1;
    //     FOREIGN_BAZ = 2;
    // }
    try std.testing.expectEqual(1, pf.enums.items.len);
    try std.testing.expectEqualStrings("ForeignEnum", pf.enums.items[0].name.name);
    try std.testing.expectEqual(3, pf.enums.items[0].fields.items.len);
    try std.testing.expectEqualStrings("FOREIGN_FOO", pf.enums.items[0].fields.items[0].name);
    try std.testing.expectEqual(0, pf.enums.items[0].fields.items[0].index);
    try std.testing.expectEqualStrings("FOREIGN_BAR", pf.enums.items[0].fields.items[1].name);
    try std.testing.expectEqual(1, pf.enums.items[0].fields.items[1].index);
    try std.testing.expectEqualStrings("FOREIGN_BAZ", pf.enums.items[0].fields.items[2].name);
    try std.testing.expectEqual(2, pf.enums.items[0].fields.items[2].index);

    //message ForeignMessage {
    //    int32 c = 1;
    //}
    const fm = pf.messages.items[1];
    try std.testing.expectEqualStrings("ForeignMessage", fm.name.name);
    try std.testing.expectEqual(1, fm.fields.items.len);
    try std.testing.expectEqualStrings("c", fm.fields.items[0].f_name);
    try std.testing.expectEqualStrings("int32", fm.fields.items[0].f_type.src);
    try std.testing.expect(fm.fields.items[0].f_type.is_scalar);
    try std.testing.expectEqual(1, fm.fields.items[0].index);

    //message NullHypothesisProto3 {}
    const nm = pf.messages.items[2];
    try std.testing.expectEqualStrings("NullHypothesisProto3", nm.name.name);
    try std.testing.expectEqual(0, nm.fields.items.len);

    //message EnumOnlyProto3 {
    //    enum Bool {
    //      kFalse = 0;
    //      kTrue = 1;
    //    }
    //}
    const em = pf.messages.items[3];
    try std.testing.expectEqualStrings("EnumOnlyProto3", em.name.name);
    try std.testing.expectEqual(1, em.enums.items.len);
    try std.testing.expectEqualStrings(".protobuf_test_messages.editions.proto3.EnumOnlyProto3.Bool", em.enums.items[0].name.full);
    try std.testing.expectEqual(2, em.enums.items[0].fields.items.len);
    try std.testing.expectEqualStrings("kFalse", em.enums.items[0].fields.items[0].name);
    try std.testing.expectEqual(0, em.enums.items[0].fields.items[0].index);
    try std.testing.expectEqualStrings("kTrue", em.enums.items[0].fields.items[1].name);
    try std.testing.expectEqual(1, em.enums.items[0].fields.items[1].index);

    //message TestAllTypesProto3
    const am = pf.messages.items[0];
    try std.testing.expectEqualStrings("TestAllTypesProto3", am.name.name);

    //message NestedMessage {
    //    int32 a = 1;
    //    TestAllTypesProto3 corecursive = 2;
    //}
    const nm2 = am.messages.items[0];
    try std.testing.expectEqualStrings(".protobuf_test_messages.editions.proto3.TestAllTypesProto3.NestedMessage", nm2.name.full);
    try std.testing.expectEqual(2, nm2.fields.items.len);
    try std.testing.expectEqualStrings("a", nm2.fields.items[0].f_name);
    try std.testing.expectEqualStrings("int32", nm2.fields.items[0].f_type.src);
    try std.testing.expect(nm2.fields.items[0].f_type.is_scalar);
    try std.testing.expectEqual(1, nm2.fields.items[0].index);
    try std.testing.expectEqualStrings("corecursive", nm2.fields.items[1].f_name);
    try std.testing.expectEqualStrings("TestAllTypesProto3", nm2.fields.items[1].f_type.src);
    try std.testing.expect(!nm2.fields.items[1].f_type.is_scalar);
    try std.testing.expectEqual(2, nm2.fields.items[1].index);

    //enum NestedEnum {
    //    FOO = 0;
    //    BAR = 1;
    //    BAZ = 2;
    //    NEG = -1; // Intentionally negative.
    //}
    const ne = am.enums.items[0];
    try std.testing.expectEqualStrings(".protobuf_test_messages.editions.proto3.TestAllTypesProto3.NestedEnum", ne.name.full);
    try std.testing.expectEqual(4, ne.fields.items.len);
    try std.testing.expectEqualStrings("FOO", ne.fields.items[0].name);
    try std.testing.expectEqual(0, ne.fields.items[0].index);
    try std.testing.expectEqualStrings("BAR", ne.fields.items[1].name);
    try std.testing.expectEqual(1, ne.fields.items[1].index);
    try std.testing.expectEqualStrings("BAZ", ne.fields.items[2].name);
    try std.testing.expectEqual(2, ne.fields.items[2].index);
    try std.testing.expectEqualStrings("NEG", ne.fields.items[3].name);
    try std.testing.expectEqual(-1, ne.fields.items[3].index);

    //enum AliasedEnum {
    //    option allow_alias = true;
    //
    //    ALIAS_FOO = 0;
    //    ALIAS_BAR = 1;
    //    ALIAS_BAZ = 2;
    //    MOO = 2;
    //    moo = 2;
    //    bAz = 2;
    //}
    const ae = am.enums.items[1];
    try std.testing.expectEqualStrings(".protobuf_test_messages.editions.proto3.TestAllTypesProto3.AliasedEnum", ae.name.full);
    try std.testing.expectEqual(6, ae.fields.items.len);
    try std.testing.expectEqualStrings("ALIAS_FOO", ae.fields.items[0].name);
    try std.testing.expectEqual(0, ae.fields.items[0].index);
    try std.testing.expectEqualStrings("ALIAS_BAR", ae.fields.items[1].name);
    try std.testing.expectEqual(1, ae.fields.items[1].index);
    try std.testing.expectEqualStrings("ALIAS_BAZ", ae.fields.items[2].name);
    try std.testing.expectEqual(2, ae.fields.items[2].index);
    try std.testing.expectEqualStrings("MOO", ae.fields.items[3].name);
    try std.testing.expectEqual(2, ae.fields.items[3].index);
    try std.testing.expectEqualStrings("moo", ae.fields.items[4].name);
    try std.testing.expectEqual(2, ae.fields.items[4].index);
    try std.testing.expectEqualStrings("bAz", ae.fields.items[5].name);
    try std.testing.expectEqual(2, ae.fields.items[5].index);
    try std.testing.expectEqual(1, ae.options.items.len);
    try std.testing.expectEqualStrings("allow_alias", ae.options.items[0].name);
    try std.testing.expectEqualStrings("true", ae.options.items[0].value);

    //int32 optional_int32 = 1;
    //int64 optional_int64 = 2;
    //uint32 optional_uint32 = 3;
    //uint64 optional_uint64 = 4;
    //sint32 optional_sint32 = 5;
    //sint64 optional_sint64 = 6;
    //fixed32 optional_fixed32 = 7;
    //fixed64 optional_fixed64 = 8;
    //sfixed32 optional_sfixed32 = 9;
    //sfixed64 optional_sfixed64 = 10;
    //float optional_float = 11;
    //double optional_double = 12;
    //bool optional_bool = 13;
    //string optional_string = 14;
    //bytes optional_bytes = 15;
    //NestedMessage optional_nested_message = 18;
    //ForeignMessage optional_foreign_message = 19;
    //NestedEnum optional_nested_enum = 21;
    //ForeignEnum optional_foreign_enum = 22;
    //AliasedEnum optional_aliased_enum = 23;

    try std.testing.expectEqualStrings("optional_int32", am.fields.items[0].f_name);
    try std.testing.expectEqualStrings("int32", am.fields.items[0].f_type.src);
    try std.testing.expectEqual(1, am.fields.items[0].index);
    try std.testing.expectEqualStrings("optional_int64", am.fields.items[1].f_name);
    try std.testing.expectEqualStrings("int64", am.fields.items[1].f_type.src);
    try std.testing.expectEqual(2, am.fields.items[1].index);
    try std.testing.expectEqualStrings("optional_uint32", am.fields.items[2].f_name);
    try std.testing.expectEqualStrings("uint32", am.fields.items[2].f_type.src);
    try std.testing.expectEqual(3, am.fields.items[2].index);
    try std.testing.expectEqualStrings("optional_uint64", am.fields.items[3].f_name);
    try std.testing.expectEqualStrings("uint64", am.fields.items[3].f_type.src);
    try std.testing.expectEqual(4, am.fields.items[3].index);
    try std.testing.expectEqualStrings("optional_sint32", am.fields.items[4].f_name);
    try std.testing.expectEqualStrings("sint32", am.fields.items[4].f_type.src);
    try std.testing.expectEqual(5, am.fields.items[4].index);
    try std.testing.expectEqualStrings("optional_sint64", am.fields.items[5].f_name);
    try std.testing.expectEqualStrings("sint64", am.fields.items[5].f_type.src);
    try std.testing.expectEqual(6, am.fields.items[5].index);
    try std.testing.expectEqualStrings("optional_fixed32", am.fields.items[6].f_name);
    try std.testing.expectEqualStrings("fixed32", am.fields.items[6].f_type.src);
    try std.testing.expectEqual(7, am.fields.items[6].index);
    try std.testing.expectEqualStrings("optional_fixed64", am.fields.items[7].f_name);
    try std.testing.expectEqualStrings("fixed64", am.fields.items[7].f_type.src);
    try std.testing.expectEqual(8, am.fields.items[7].index);
    try std.testing.expectEqualStrings("optional_sfixed32", am.fields.items[8].f_name);
    try std.testing.expectEqualStrings("sfixed32", am.fields.items[8].f_type.src);
    try std.testing.expectEqual(9, am.fields.items[8].index);
    try std.testing.expectEqualStrings("optional_sfixed64", am.fields.items[9].f_name);
    try std.testing.expectEqualStrings("sfixed64", am.fields.items[9].f_type.src);
    try std.testing.expectEqual(10, am.fields.items[9].index);
    try std.testing.expectEqualStrings("optional_float", am.fields.items[10].f_name);
    try std.testing.expectEqualStrings("float", am.fields.items[10].f_type.src);
    try std.testing.expectEqual(11, am.fields.items[10].index);
    try std.testing.expectEqualStrings("optional_double", am.fields.items[11].f_name);
    try std.testing.expectEqualStrings("double", am.fields.items[11].f_type.src);
    try std.testing.expectEqual(12, am.fields.items[11].index);
    try std.testing.expectEqualStrings("optional_bool", am.fields.items[12].f_name);
    try std.testing.expectEqualStrings("bool", am.fields.items[12].f_type.src);
    try std.testing.expectEqual(13, am.fields.items[12].index);
    try std.testing.expectEqualStrings("optional_string", am.fields.items[13].f_name);
    try std.testing.expectEqualStrings("string", am.fields.items[13].f_type.src);
    try std.testing.expectEqual(14, am.fields.items[13].index);
    try std.testing.expectEqualStrings("optional_bytes", am.fields.items[14].f_name);
    try std.testing.expectEqualStrings("bytes", am.fields.items[14].f_type.src);
    try std.testing.expectEqual(15, am.fields.items[14].index);
    try std.testing.expectEqualStrings("optional_nested_message", am.fields.items[15].f_name);
    try std.testing.expectEqualStrings("NestedMessage", am.fields.items[15].f_type.src);
    try std.testing.expectEqual(18, am.fields.items[15].index);
    try std.testing.expectEqualStrings("optional_foreign_message", am.fields.items[16].f_name);
    try std.testing.expectEqualStrings("ForeignMessage", am.fields.items[16].f_type.src);
    try std.testing.expectEqual(19, am.fields.items[16].index);
    try std.testing.expectEqualStrings("optional_nested_enum", am.fields.items[17].f_name);
    try std.testing.expectEqualStrings("NestedEnum", am.fields.items[17].f_type.src);
    try std.testing.expectEqual(21, am.fields.items[17].index);
    try std.testing.expectEqualStrings("optional_foreign_enum", am.fields.items[18].f_name);
    try std.testing.expectEqualStrings("ForeignEnum", am.fields.items[18].f_type.src);
    try std.testing.expectEqual(22, am.fields.items[18].index);
    try std.testing.expectEqualStrings("optional_aliased_enum", am.fields.items[19].f_name);
    try std.testing.expectEqualStrings("AliasedEnum", am.fields.items[19].f_type.src);
    try std.testing.expectEqual(23, am.fields.items[19].index);

    //string optional_string_piece = 24 [
    //  ctype = STRING_PIECE
    //];
    //
    //string optional_cord = 25 [
    //  ctype = CORD
    //];
    //
    //TestAllTypesProto3 recursive_message = 27;

    try std.testing.expectEqualStrings("optional_string_piece", am.fields.items[20].f_name);
    try std.testing.expectEqualStrings("string", am.fields.items[20].f_type.src);
    try std.testing.expectEqual(24, am.fields.items[20].index);
    try std.testing.expectEqual(1, am.fields.items[20].options.?.items.len);
    try std.testing.expectEqualStrings("ctype", am.fields.items[20].options.?.items[0].name);
    try std.testing.expectEqualStrings("STRING_PIECE", am.fields.items[20].options.?.items[0].value);

    try std.testing.expectEqualStrings("optional_cord", am.fields.items[21].f_name);
    try std.testing.expectEqualStrings("string", am.fields.items[21].f_type.src);
    try std.testing.expectEqual(25, am.fields.items[21].index);
    try std.testing.expectEqual(1, am.fields.items[21].options.?.items.len);
    try std.testing.expectEqualStrings("ctype", am.fields.items[21].options.?.items[0].name);
    try std.testing.expectEqualStrings("CORD", am.fields.items[21].options.?.items[0].value);

    try std.testing.expectEqualStrings("recursive_message", am.fields.items[22].f_name);
    try std.testing.expectEqualStrings("TestAllTypesProto3", am.fields.items[22].f_type.src);
    try std.testing.expectEqual(27, am.fields.items[22].index);

    //repeated int32 repeated_int32 = 31;
    //repeated int64 repeated_int64 = 32;
    //repeated uint32 repeated_uint32 = 33;
    //repeated uint64 repeated_uint64 = 34;
    //repeated sint32 repeated_sint32 = 35;
    //repeated sint64 repeated_sint64 = 36;
    //repeated fixed32 repeated_fixed32 = 37;
    //repeated fixed64 repeated_fixed64 = 38;
    //repeated sfixed32 repeated_sfixed32 = 39;
    //repeated sfixed64 repeated_sfixed64 = 40;
    //repeated float repeated_float = 41;
    //repeated double repeated_double = 42;
    //repeated bool repeated_bool = 43;
    //repeated string repeated_string = 44;
    //repeated bytes repeated_bytes = 45;
    //repeated NestedMessage repeated_nested_message = 48;
    //repeated ForeignMessage repeated_foreign_message = 49;
    //repeated NestedEnum repeated_nested_enum = 51;
    //repeated ForeignEnum repeated_foreign_enum = 52;
    //repeated string repeated_string_piece = 54 [
    //  ctype = STRING_PIECE
    //];
    //repeated string repeated_cord = 55 [
    //  ctype = CORD
    //];

    try std.testing.expectEqualStrings("repeated_int32", am.fields.items[23].f_name);
    try std.testing.expectEqualStrings("int32", am.fields.items[23].f_type.src);
    try std.testing.expectEqual(31, am.fields.items[23].index);
    try std.testing.expect(am.fields.items[23].repeated);

    try std.testing.expectEqualStrings("repeated_int64", am.fields.items[24].f_name);
    try std.testing.expectEqualStrings("int64", am.fields.items[24].f_type.src);
    try std.testing.expectEqual(32, am.fields.items[24].index);
    try std.testing.expect(am.fields.items[24].repeated);

    try std.testing.expectEqualStrings("repeated_uint32", am.fields.items[25].f_name);
    try std.testing.expectEqualStrings("uint32", am.fields.items[25].f_type.src);
    try std.testing.expectEqual(33, am.fields.items[25].index);
    try std.testing.expect(am.fields.items[25].repeated);

    try std.testing.expectEqualStrings("repeated_uint64", am.fields.items[26].f_name);
    try std.testing.expectEqualStrings("uint64", am.fields.items[26].f_type.src);
    try std.testing.expectEqual(34, am.fields.items[26].index);
    try std.testing.expect(am.fields.items[26].repeated);

    try std.testing.expectEqualStrings("repeated_sint32", am.fields.items[27].f_name);
    try std.testing.expectEqualStrings("sint32", am.fields.items[27].f_type.src);
    try std.testing.expectEqual(35, am.fields.items[27].index);
    try std.testing.expect(am.fields.items[27].repeated);

    try std.testing.expectEqualStrings("repeated_sint64", am.fields.items[28].f_name);
    try std.testing.expectEqualStrings("sint64", am.fields.items[28].f_type.src);
    try std.testing.expectEqual(36, am.fields.items[28].index);
    try std.testing.expect(am.fields.items[28].repeated);

    try std.testing.expectEqualStrings("repeated_fixed32", am.fields.items[29].f_name);
    try std.testing.expectEqualStrings("fixed32", am.fields.items[29].f_type.src);
    try std.testing.expectEqual(37, am.fields.items[29].index);
    try std.testing.expect(am.fields.items[29].repeated);

    try std.testing.expectEqualStrings("repeated_fixed64", am.fields.items[30].f_name);
    try std.testing.expectEqualStrings("fixed64", am.fields.items[30].f_type.src);
    try std.testing.expectEqual(38, am.fields.items[30].index);
    try std.testing.expect(am.fields.items[30].repeated);

    try std.testing.expectEqualStrings("repeated_sfixed32", am.fields.items[31].f_name);
    try std.testing.expectEqualStrings("sfixed32", am.fields.items[31].f_type.src);
    try std.testing.expectEqual(39, am.fields.items[31].index);
    try std.testing.expect(am.fields.items[31].repeated);

    try std.testing.expectEqualStrings("repeated_sfixed64", am.fields.items[32].f_name);
    try std.testing.expectEqualStrings("sfixed64", am.fields.items[32].f_type.src);
    try std.testing.expectEqual(40, am.fields.items[32].index);
    try std.testing.expect(am.fields.items[32].repeated);

    try std.testing.expectEqualStrings("repeated_float", am.fields.items[33].f_name);
    try std.testing.expectEqualStrings("float", am.fields.items[33].f_type.src);
    try std.testing.expectEqual(41, am.fields.items[33].index);
    try std.testing.expect(am.fields.items[33].repeated);

    try std.testing.expectEqualStrings("repeated_double", am.fields.items[34].f_name);
    try std.testing.expectEqualStrings("double", am.fields.items[34].f_type.src);
    try std.testing.expectEqual(42, am.fields.items[34].index);
    try std.testing.expect(am.fields.items[34].repeated);

    try std.testing.expectEqualStrings("repeated_bool", am.fields.items[35].f_name);
    try std.testing.expectEqualStrings("bool", am.fields.items[35].f_type.src);
    try std.testing.expectEqual(43, am.fields.items[35].index);
    try std.testing.expect(am.fields.items[35].repeated);

    try std.testing.expectEqualStrings("repeated_string", am.fields.items[36].f_name);
    try std.testing.expectEqualStrings("string", am.fields.items[36].f_type.src);
    try std.testing.expectEqual(44, am.fields.items[36].index);
    try std.testing.expect(am.fields.items[36].repeated);

    try std.testing.expectEqualStrings("repeated_bytes", am.fields.items[37].f_name);
    try std.testing.expectEqualStrings("bytes", am.fields.items[37].f_type.src);
    try std.testing.expectEqual(45, am.fields.items[37].index);
    try std.testing.expect(am.fields.items[37].repeated);

    try std.testing.expectEqualStrings("repeated_nested_message", am.fields.items[38].f_name);
    try std.testing.expectEqualStrings("NestedMessage", am.fields.items[38].f_type.src);
    try std.testing.expectEqual(48, am.fields.items[38].index);
    try std.testing.expect(am.fields.items[38].repeated);

    try std.testing.expectEqualStrings("repeated_foreign_message", am.fields.items[39].f_name);
    try std.testing.expectEqualStrings("ForeignMessage", am.fields.items[39].f_type.src);
    try std.testing.expectEqual(49, am.fields.items[39].index);
    try std.testing.expect(am.fields.items[39].repeated);

    try std.testing.expectEqualStrings("repeated_nested_enum", am.fields.items[40].f_name);
    try std.testing.expectEqualStrings("NestedEnum", am.fields.items[40].f_type.src);
    try std.testing.expectEqual(51, am.fields.items[40].index);
    try std.testing.expect(am.fields.items[40].repeated);

    try std.testing.expectEqualStrings("repeated_foreign_enum", am.fields.items[41].f_name);
    try std.testing.expectEqualStrings("ForeignEnum", am.fields.items[41].f_type.src);
    try std.testing.expectEqual(52, am.fields.items[41].index);
    try std.testing.expect(am.fields.items[41].repeated);

    try std.testing.expectEqualStrings("repeated_string_piece", am.fields.items[42].f_name);
    try std.testing.expectEqualStrings("string", am.fields.items[42].f_type.src);
    try std.testing.expectEqual(54, am.fields.items[42].index);
    try std.testing.expect(am.fields.items[42].repeated);
    try std.testing.expectEqual(1, am.fields.items[42].options.?.items.len);
    try std.testing.expectEqualStrings("ctype", am.fields.items[42].options.?.items[0].name);
    try std.testing.expectEqualStrings("STRING_PIECE", am.fields.items[42].options.?.items[0].value);

    try std.testing.expectEqualStrings("repeated_cord", am.fields.items[43].f_name);
    try std.testing.expectEqualStrings("string", am.fields.items[43].f_type.src);
    try std.testing.expectEqual(55, am.fields.items[43].index);
    try std.testing.expect(am.fields.items[43].repeated);
    try std.testing.expectEqual(1, am.fields.items[43].options.?.items.len);
    try std.testing.expectEqualStrings("ctype", am.fields.items[43].options.?.items[0].name);
    try std.testing.expectEqualStrings("CORD", am.fields.items[43].options.?.items[0].value);

    //repeated int32 packed_int32 = 75;
    //repeated int64 packed_int64 = 76;
    //repeated uint32 packed_uint32 = 77;
    //repeated uint64 packed_uint64 = 78;
    //repeated sint32 packed_sint32 = 79;
    //repeated sint64 packed_sint64 = 80;
    //repeated fixed32 packed_fixed32 = 81;
    //repeated fixed64 packed_fixed64 = 82;
    //repeated sfixed32 packed_sfixed32 = 83;
    //repeated sfixed64 packed_sfixed64 = 84;
    //repeated float packed_float = 85;
    //repeated double packed_double = 86;
    //repeated bool packed_bool = 87;
    //repeated NestedEnum packed_nested_enum = 88;

    try std.testing.expectEqualStrings("packed_int32", am.fields.items[44].f_name);
    try std.testing.expectEqualStrings("int32", am.fields.items[44].f_type.src);
    try std.testing.expectEqual(75, am.fields.items[44].index);
    try std.testing.expect(am.fields.items[44].repeated);

    try std.testing.expectEqualStrings("packed_int64", am.fields.items[45].f_name);
    try std.testing.expectEqualStrings("int64", am.fields.items[45].f_type.src);
    try std.testing.expectEqual(76, am.fields.items[45].index);
    try std.testing.expect(am.fields.items[45].repeated);

    try std.testing.expectEqualStrings("packed_uint32", am.fields.items[46].f_name);
    try std.testing.expectEqualStrings("uint32", am.fields.items[46].f_type.src);
    try std.testing.expectEqual(77, am.fields.items[46].index);
    try std.testing.expect(am.fields.items[46].repeated);

    try std.testing.expectEqualStrings("packed_uint64", am.fields.items[47].f_name);
    try std.testing.expectEqualStrings("uint64", am.fields.items[47].f_type.src);
    try std.testing.expectEqual(78, am.fields.items[47].index);
    try std.testing.expect(am.fields.items[47].repeated);

    try std.testing.expectEqualStrings("packed_sint32", am.fields.items[48].f_name);
    try std.testing.expectEqualStrings("sint32", am.fields.items[48].f_type.src);
    try std.testing.expectEqual(79, am.fields.items[48].index);
    try std.testing.expect(am.fields.items[48].repeated);

    try std.testing.expectEqualStrings("packed_sint64", am.fields.items[49].f_name);
    try std.testing.expectEqualStrings("sint64", am.fields.items[49].f_type.src);
    try std.testing.expectEqual(80, am.fields.items[49].index);
    try std.testing.expect(am.fields.items[49].repeated);

    try std.testing.expectEqualStrings("packed_fixed32", am.fields.items[50].f_name);
    try std.testing.expectEqualStrings("fixed32", am.fields.items[50].f_type.src);
    try std.testing.expectEqual(81, am.fields.items[50].index);
    try std.testing.expect(am.fields.items[50].repeated);

    try std.testing.expectEqualStrings("packed_fixed64", am.fields.items[51].f_name);
    try std.testing.expectEqualStrings("fixed64", am.fields.items[51].f_type.src);
    try std.testing.expectEqual(82, am.fields.items[51].index);
    try std.testing.expect(am.fields.items[51].repeated);

    try std.testing.expectEqualStrings("packed_sfixed32", am.fields.items[52].f_name);
    try std.testing.expectEqualStrings("sfixed32", am.fields.items[52].f_type.src);
    try std.testing.expectEqual(83, am.fields.items[52].index);
    try std.testing.expect(am.fields.items[52].repeated);

    try std.testing.expectEqualStrings("packed_sfixed64", am.fields.items[53].f_name);
    try std.testing.expectEqualStrings("sfixed64", am.fields.items[53].f_type.src);
    try std.testing.expectEqual(84, am.fields.items[53].index);
    try std.testing.expect(am.fields.items[53].repeated);

    try std.testing.expectEqualStrings("packed_float", am.fields.items[54].f_name);
    try std.testing.expectEqualStrings("float", am.fields.items[54].f_type.src);
    try std.testing.expectEqual(85, am.fields.items[54].index);
    try std.testing.expect(am.fields.items[54].repeated);

    try std.testing.expectEqualStrings("packed_double", am.fields.items[55].f_name);
    try std.testing.expectEqualStrings("double", am.fields.items[55].f_type.src);
    try std.testing.expectEqual(86, am.fields.items[55].index);
    try std.testing.expect(am.fields.items[55].repeated);

    try std.testing.expectEqualStrings("packed_bool", am.fields.items[56].f_name);
    try std.testing.expectEqualStrings("bool", am.fields.items[56].f_type.src);
    try std.testing.expectEqual(87, am.fields.items[56].index);
    try std.testing.expect(am.fields.items[56].repeated);

    try std.testing.expectEqualStrings("packed_nested_enum", am.fields.items[57].f_name);
    try std.testing.expectEqualStrings("NestedEnum", am.fields.items[57].f_type.src);
    try std.testing.expectEqual(88, am.fields.items[57].index);
    try std.testing.expect(am.fields.items[57].repeated);

    // Unpacked
    //repeated int32 unpacked_int32 = 89 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated int64 unpacked_int64 = 90 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated uint32 unpacked_uint32 = 91 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated uint64 unpacked_uint64 = 92 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated sint32 unpacked_sint32 = 93 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated sint64 unpacked_sint64 = 94 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated fixed32 unpacked_fixed32 = 95 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated fixed64 unpacked_fixed64 = 96 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated sfixed32 unpacked_sfixed32 = 97 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated sfixed64 unpacked_sfixed64 = 98 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated float unpacked_float = 99 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated double unpacked_double = 100 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated bool unpacked_bool = 101 [
    //  features.repeated_field_encoding = EXPANDED
    //];
    //repeated NestedEnum unpacked_nested_enum = 102 [
    //  features.repeated_field_encoding = EXPANDED
    //];

    try std.testing.expectEqualStrings("unpacked_int32", am.fields.items[58].f_name);
    try std.testing.expectEqualStrings("int32", am.fields.items[58].f_type.src);
    try std.testing.expectEqual(89, am.fields.items[58].index);
    try std.testing.expect(am.fields.items[58].repeated);
    try std.testing.expectEqual(1, am.fields.items[58].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[58].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[58].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_int64", am.fields.items[59].f_name);
    try std.testing.expectEqualStrings("int64", am.fields.items[59].f_type.src);
    try std.testing.expectEqual(90, am.fields.items[59].index);
    try std.testing.expect(am.fields.items[59].repeated);
    try std.testing.expectEqual(1, am.fields.items[59].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[59].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[59].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_uint32", am.fields.items[60].f_name);
    try std.testing.expectEqualStrings("uint32", am.fields.items[60].f_type.src);
    try std.testing.expectEqual(91, am.fields.items[60].index);
    try std.testing.expect(am.fields.items[60].repeated);
    try std.testing.expectEqual(1, am.fields.items[60].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[60].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[60].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_uint64", am.fields.items[61].f_name);
    try std.testing.expectEqualStrings("uint64", am.fields.items[61].f_type.src);
    try std.testing.expectEqual(92, am.fields.items[61].index);
    try std.testing.expect(am.fields.items[61].repeated);
    try std.testing.expectEqual(1, am.fields.items[61].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[61].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[61].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_sint32", am.fields.items[62].f_name);
    try std.testing.expectEqualStrings("sint32", am.fields.items[62].f_type.src);
    try std.testing.expectEqual(93, am.fields.items[62].index);
    try std.testing.expect(am.fields.items[62].repeated);
    try std.testing.expectEqual(1, am.fields.items[62].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[62].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[62].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_sint64", am.fields.items[63].f_name);
    try std.testing.expectEqualStrings("sint64", am.fields.items[63].f_type.src);
    try std.testing.expectEqual(94, am.fields.items[63].index);
    try std.testing.expect(am.fields.items[63].repeated);
    try std.testing.expectEqual(1, am.fields.items[63].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[63].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[63].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_fixed32", am.fields.items[64].f_name);
    try std.testing.expectEqualStrings("fixed32", am.fields.items[64].f_type.src);
    try std.testing.expectEqual(95, am.fields.items[64].index);
    try std.testing.expect(am.fields.items[64].repeated);
    try std.testing.expectEqual(1, am.fields.items[64].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[64].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[64].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_fixed64", am.fields.items[65].f_name);
    try std.testing.expectEqualStrings("fixed64", am.fields.items[65].f_type.src);
    try std.testing.expectEqual(96, am.fields.items[65].index);
    try std.testing.expect(am.fields.items[65].repeated);
    try std.testing.expectEqual(1, am.fields.items[65].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[65].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[65].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_sfixed32", am.fields.items[66].f_name);
    try std.testing.expectEqualStrings("sfixed32", am.fields.items[66].f_type.src);
    try std.testing.expectEqual(97, am.fields.items[66].index);
    try std.testing.expect(am.fields.items[66].repeated);
    try std.testing.expectEqual(1, am.fields.items[66].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[66].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[66].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_sfixed64", am.fields.items[67].f_name);
    try std.testing.expectEqualStrings("sfixed64", am.fields.items[67].f_type.src);
    try std.testing.expectEqual(98, am.fields.items[67].index);
    try std.testing.expect(am.fields.items[67].repeated);
    try std.testing.expectEqual(1, am.fields.items[67].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[67].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[67].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_float", am.fields.items[68].f_name);
    try std.testing.expectEqualStrings("float", am.fields.items[68].f_type.src);
    try std.testing.expectEqual(99, am.fields.items[68].index);
    try std.testing.expect(am.fields.items[68].repeated);
    try std.testing.expectEqual(1, am.fields.items[68].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[68].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[68].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_double", am.fields.items[69].f_name);
    try std.testing.expectEqualStrings("double", am.fields.items[69].f_type.src);
    try std.testing.expectEqual(100, am.fields.items[69].index);
    try std.testing.expect(am.fields.items[69].repeated);
    try std.testing.expectEqual(1, am.fields.items[69].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[69].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[69].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_bool", am.fields.items[70].f_name);
    try std.testing.expectEqualStrings("bool", am.fields.items[70].f_type.src);
    try std.testing.expectEqual(101, am.fields.items[70].index);
    try std.testing.expect(am.fields.items[70].repeated);
    try std.testing.expectEqual(1, am.fields.items[70].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[70].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[70].options.?.items[0].value);

    try std.testing.expectEqualStrings("unpacked_nested_enum", am.fields.items[71].f_name);
    try std.testing.expectEqualStrings("NestedEnum", am.fields.items[71].f_type.src);
    try std.testing.expectEqual(102, am.fields.items[71].index);
    try std.testing.expect(am.fields.items[71].repeated);
    try std.testing.expectEqual(1, am.fields.items[71].options.?.items.len);
    try std.testing.expectEqualStrings("features.repeated_field_encoding", am.fields.items[71].options.?.items[0].name);
    try std.testing.expectEqualStrings("EXPANDED", am.fields.items[71].options.?.items[0].value);

    //map<int32, int32> map_int32_int32 = 56;
    //map<int64, int64> map_int64_int64 = 57;
    //map<uint32, uint32> map_uint32_uint32 = 58;
    //map<uint64, uint64> map_uint64_uint64 = 59;
    //map<sint32, sint32> map_sint32_sint32 = 60;
    //map<sint64, sint64> map_sint64_sint64 = 61;
    //map<fixed32, fixed32> map_fixed32_fixed32 = 62;
    //map<fixed64, fixed64> map_fixed64_fixed64 = 63;
    //map<sfixed32, sfixed32> map_sfixed32_sfixed32 = 64;
    //map<sfixed64, sfixed64> map_sfixed64_sfixed64 = 65;
    //map<int32, float> map_int32_float = 66;
    //map<int32, double> map_int32_double = 67;
    //map<bool, bool> map_bool_bool = 68;
    //map<string, string> map_string_string = 69;
    //map<string, bytes> map_string_bytes = 70;
    //map<string, NestedMessage> map_string_nested_message = 71;
    //map<string, ForeignMessage> map_string_foreign_message = 72;
    //map<string, NestedEnum> map_string_nested_enum = 73;
    //map<string, ForeignEnum> map_string_foreign_enum = 74;

    try std.testing.expectEqualStrings("map_int32_int32", am.maps.items[0].f_name);
    try std.testing.expectEqualStrings("int32", am.maps.items[0].key_type);
    try std.testing.expectEqualStrings("int32", am.maps.items[0].value_type.src);
    try std.testing.expectEqual(56, am.maps.items[0].index);

    try std.testing.expectEqualStrings("map_int64_int64", am.maps.items[1].f_name);
    try std.testing.expectEqualStrings("int64", am.maps.items[1].key_type);
    try std.testing.expectEqualStrings("int64", am.maps.items[1].value_type.src);
    try std.testing.expectEqual(57, am.maps.items[1].index);

    try std.testing.expectEqualStrings("map_uint32_uint32", am.maps.items[2].f_name);
    try std.testing.expectEqualStrings("uint32", am.maps.items[2].key_type);
    try std.testing.expectEqualStrings("uint32", am.maps.items[2].value_type.src);
    try std.testing.expectEqual(58, am.maps.items[2].index);

    try std.testing.expectEqualStrings("map_uint64_uint64", am.maps.items[3].f_name);
    try std.testing.expectEqualStrings("uint64", am.maps.items[3].key_type);
    try std.testing.expectEqualStrings("uint64", am.maps.items[3].value_type.src);
    try std.testing.expectEqual(59, am.maps.items[3].index);

    try std.testing.expectEqualStrings("map_sint32_sint32", am.maps.items[4].f_name);
    try std.testing.expectEqualStrings("sint32", am.maps.items[4].key_type);
    try std.testing.expectEqualStrings("sint32", am.maps.items[4].value_type.src);
    try std.testing.expectEqual(60, am.maps.items[4].index);

    try std.testing.expectEqualStrings("map_sint64_sint64", am.maps.items[5].f_name);
    try std.testing.expectEqualStrings("sint64", am.maps.items[5].key_type);
    try std.testing.expectEqualStrings("sint64", am.maps.items[5].value_type.src);
    try std.testing.expectEqual(61, am.maps.items[5].index);

    try std.testing.expectEqualStrings("map_fixed32_fixed32", am.maps.items[6].f_name);
    try std.testing.expectEqualStrings("fixed32", am.maps.items[6].key_type);
    try std.testing.expectEqualStrings("fixed32", am.maps.items[6].value_type.src);
    try std.testing.expectEqual(62, am.maps.items[6].index);

    try std.testing.expectEqualStrings("map_fixed64_fixed64", am.maps.items[7].f_name);
    try std.testing.expectEqualStrings("fixed64", am.maps.items[7].key_type);
    try std.testing.expectEqualStrings("fixed64", am.maps.items[7].value_type.src);
    try std.testing.expectEqual(63, am.maps.items[7].index);

    try std.testing.expectEqualStrings("map_sfixed32_sfixed32", am.maps.items[8].f_name);
    try std.testing.expectEqualStrings("sfixed32", am.maps.items[8].key_type);
    try std.testing.expectEqualStrings("sfixed32", am.maps.items[8].value_type.src);
    try std.testing.expectEqual(64, am.maps.items[8].index);

    try std.testing.expectEqualStrings("map_sfixed64_sfixed64", am.maps.items[9].f_name);
    try std.testing.expectEqualStrings("sfixed64", am.maps.items[9].key_type);
    try std.testing.expectEqualStrings("sfixed64", am.maps.items[9].value_type.src);
    try std.testing.expectEqual(65, am.maps.items[9].index);

    try std.testing.expectEqualStrings("map_int32_float", am.maps.items[10].f_name);
    try std.testing.expectEqualStrings("int32", am.maps.items[10].key_type);
    try std.testing.expectEqualStrings("float", am.maps.items[10].value_type.src);
    try std.testing.expectEqual(66, am.maps.items[10].index);

    try std.testing.expectEqualStrings("map_int32_double", am.maps.items[11].f_name);
    try std.testing.expectEqualStrings("int32", am.maps.items[11].key_type);
    try std.testing.expectEqualStrings("double", am.maps.items[11].value_type.src);
    try std.testing.expectEqual(67, am.maps.items[11].index);

    try std.testing.expectEqualStrings("map_bool_bool", am.maps.items[12].f_name);
    try std.testing.expectEqualStrings("bool", am.maps.items[12].key_type);
    try std.testing.expectEqualStrings("bool", am.maps.items[12].value_type.src);
    try std.testing.expectEqual(68, am.maps.items[12].index);

    try std.testing.expectEqualStrings("map_string_string", am.maps.items[13].f_name);
    try std.testing.expectEqualStrings("string", am.maps.items[13].key_type);
    try std.testing.expectEqualStrings("string", am.maps.items[13].value_type.src);
    try std.testing.expectEqual(69, am.maps.items[13].index);

    try std.testing.expectEqualStrings("map_string_bytes", am.maps.items[14].f_name);
    try std.testing.expectEqualStrings("string", am.maps.items[14].key_type);
    try std.testing.expectEqualStrings("bytes", am.maps.items[14].value_type.src);
    try std.testing.expectEqual(70, am.maps.items[14].index);

    try std.testing.expectEqualStrings("map_string_nested_message", am.maps.items[15].f_name);
    try std.testing.expectEqualStrings("string", am.maps.items[15].key_type);
    try std.testing.expectEqualStrings("NestedMessage", am.maps.items[15].value_type.src);
    try std.testing.expectEqual(71, am.maps.items[15].index);

    try std.testing.expectEqualStrings("map_string_foreign_message", am.maps.items[16].f_name);
    try std.testing.expectEqualStrings("string", am.maps.items[16].key_type);
    try std.testing.expectEqualStrings("ForeignMessage", am.maps.items[16].value_type.src);
    try std.testing.expectEqual(72, am.maps.items[16].index);

    try std.testing.expectEqualStrings("map_string_nested_enum", am.maps.items[17].f_name);
    try std.testing.expectEqualStrings("string", am.maps.items[17].key_type);
    try std.testing.expectEqualStrings("NestedEnum", am.maps.items[17].value_type.src);
    try std.testing.expectEqual(73, am.maps.items[17].index);

    try std.testing.expectEqualStrings("map_string_foreign_enum", am.maps.items[18].f_name);
    try std.testing.expectEqualStrings("string", am.maps.items[18].key_type);
    try std.testing.expectEqualStrings("ForeignEnum", am.maps.items[18].value_type.src);
    try std.testing.expectEqual(74, am.maps.items[18].index);

    //oneof oneof_field {
    //      uint32 oneof_uint32 = 111;
    //      NestedMessage oneof_nested_message = 112;
    //      string oneof_string = 113;
    //      bytes oneof_bytes = 114;
    //      bool oneof_bool = 115;
    //      uint64 oneof_uint64 = 116;
    //      float oneof_float = 117;
    //      double oneof_double = 118;
    //      NestedEnum oneof_enum = 119;
    //      google.protobuf.NullValue oneof_null_value = 120;
    //  }
    try std.testing.expectEqualStrings("oneof_field", am.oneofs.items[0].name);
    try std.testing.expectEqual(111, am.oneofs.items[0].fields.items[0].index);
    try std.testing.expectEqualStrings("oneof_uint32", am.oneofs.items[0].fields.items[0].f_name);
    try std.testing.expectEqualStrings("uint32", am.oneofs.items[0].fields.items[0].f_type.src);
    try std.testing.expectEqual(112, am.oneofs.items[0].fields.items[1].index);
    try std.testing.expectEqualStrings("oneof_nested_message", am.oneofs.items[0].fields.items[1].f_name);
    try std.testing.expectEqualStrings("NestedMessage", am.oneofs.items[0].fields.items[1].f_type.src);
    try std.testing.expectEqual(113, am.oneofs.items[0].fields.items[2].index);
    try std.testing.expectEqualStrings("oneof_string", am.oneofs.items[0].fields.items[2].f_name);
    try std.testing.expectEqualStrings("string", am.oneofs.items[0].fields.items[2].f_type.src);
    try std.testing.expectEqual(114, am.oneofs.items[0].fields.items[3].index);
    try std.testing.expectEqualStrings("oneof_bytes", am.oneofs.items[0].fields.items[3].f_name);
    try std.testing.expectEqualStrings("bytes", am.oneofs.items[0].fields.items[3].f_type.src);
    try std.testing.expectEqual(115, am.oneofs.items[0].fields.items[4].index);
    try std.testing.expectEqualStrings("oneof_bool", am.oneofs.items[0].fields.items[4].f_name);
    try std.testing.expectEqualStrings("bool", am.oneofs.items[0].fields.items[4].f_type.src);
    try std.testing.expectEqual(116, am.oneofs.items[0].fields.items[5].index);
    try std.testing.expectEqualStrings("oneof_uint64", am.oneofs.items[0].fields.items[5].f_name);
    try std.testing.expectEqualStrings("uint64", am.oneofs.items[0].fields.items[5].f_type.src);
    try std.testing.expectEqual(117, am.oneofs.items[0].fields.items[6].index);
    try std.testing.expectEqualStrings("oneof_float", am.oneofs.items[0].fields.items[6].f_name);
    try std.testing.expectEqualStrings("float", am.oneofs.items[0].fields.items[6].f_type.src);
    try std.testing.expectEqual(118, am.oneofs.items[0].fields.items[7].index);
    try std.testing.expectEqualStrings("oneof_double", am.oneofs.items[0].fields.items[7].f_name);
    try std.testing.expectEqualStrings("double", am.oneofs.items[0].fields.items[7].f_type.src);
    try std.testing.expectEqual(119, am.oneofs.items[0].fields.items[8].index);
    try std.testing.expectEqualStrings("oneof_enum", am.oneofs.items[0].fields.items[8].f_name);
    try std.testing.expectEqualStrings("NestedEnum", am.oneofs.items[0].fields.items[8].f_type.src);
    try std.testing.expectEqual(120, am.oneofs.items[0].fields.items[9].index);
    try std.testing.expectEqualStrings("oneof_null_value", am.oneofs.items[0].fields.items[9].f_name);
    try std.testing.expectEqualStrings("google.protobuf.NullValue", am.oneofs.items[0].fields.items[9].f_type.src);

    // reserved 501 to 510;
    try std.testing.expectEqualStrings("501 to 510", am.reserved.items[0].items.items[0]);
}
