//! Provides functionality for generating Zig structs from Protocol Buffer message definitions.
//! This module handles the generation of writer and reader structs, field definitions,
//! nested types, and type resolution for Protocol Buffer messages.

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
// Created by ab, 11.11.2024

const std = @import("std");
const Message = @import("../../parser/main.zig").Message;
const Enum = @import("../../parser/main.zig").Enum;
const FieldType = @import("../../parser/main.zig").FieldType;
const naming = @import("fields/naming.zig");
const ZigEnum = @import("enum.zig").ZigEnum;
const ZigFile = @import("file.zig").ZigFile;
const FileOutput = @import("output.zig").FileOutput;

const Field = @import("fields/struct-field.zig").Field;
const FieldBuilder = @import("fields/struct-field.zig").FieldBuilder;
const CodeGenerator = @import("struct-codegen.zig").CodeGenerator;

/// ZigStruct represents a Zig struct generated from a Protocol Buffer message.
/// It manages both the writer and reader variants of the struct, along with
/// any nested types (enums, structs) and fields.
pub const ZigStruct = struct {
    allocator: std.mem.Allocator,
    wire_enum_name: []const u8,
    writer_name: []const u8,
    reader_name: []const u8,

    enums: std.ArrayList(ZigEnum),
    structs: std.ArrayList(ZigStruct),
    fields: std.ArrayList(Field),

    full_writer_name: []const u8,
    full_reader_name: []const u8,
    full_wire_name: []const u8,

    source: *const Message,

    /// Initializes a new ZigStruct from a protobuf Message
    pub fn init(
        allocator: std.mem.Allocator,
        src: *const Message,
        names: *std.ArrayList([]const u8),
        scope_name: []const u8,
    ) !ZigStruct {
        const names_result = try NameGenerator.generate(
            allocator,
            src.name.name,
            scope_name,
            names,
        );

        var fields_result = try FieldsBuilder.build(allocator, src, names_result.full_writer_name, names_result.full_wire_name, names_result.writer_name, names_result.reader_name);
        errdefer fields_result.deinit();

        var scope_names = try std.ArrayList([]const u8).initCapacity(allocator, 32);
        try scope_names.append(allocator, "calcProtoubfSize");
        try scope_names.append(allocator, "encode");
        defer scope_names.deinit(allocator);

        return ZigStruct{
            .allocator = allocator,

            .wire_enum_name = names_result.wire_enum_name,
            .writer_name = names_result.writer_name,
            .reader_name = names_result.reader_name,
            .full_writer_name = names_result.full_writer_name,
            .full_reader_name = names_result.full_reader_name,
            .full_wire_name = names_result.full_wire_name,

            .enums = fields_result.enums,
            .structs = fields_result.structs,
            .fields = fields_result.fields,
            .source = src,
        };
    }

    /// Cleans up resources used by the struct
    pub fn deinit(self: *ZigStruct) void {
        self.allocator.free(self.wire_enum_name);
        self.allocator.free(self.writer_name);
        self.allocator.free(self.reader_name);
        self.allocator.free(self.full_writer_name);
        self.allocator.free(self.full_reader_name);
        self.allocator.free(self.full_wire_name);

        for (self.enums.items) |*e| e.deinit();
        self.enums.deinit(self.allocator);

        for (self.structs.items) |*s| s.deinit();
        self.structs.deinit(self.allocator);

        for (self.fields.items) |*f| f.deinit();
        self.fields.deinit(self.allocator);
    }

    /// Generates code for the struct
    pub fn code(self: *const ZigStruct, out_file: *FileOutput) anyerror!void {
        var code_gen = CodeGenerator.init(self.allocator, self, out_file);
        try code_gen.generate();
    }

    /// Finds an enum definition within this struct or its nested structs
    pub fn findEnum(self: *ZigStruct, enum_def: *const Enum) ?*ZigEnum {
        for (self.enums.items) |*e| {
            if (e.src == enum_def) return e;
        }

        for (self.structs.items) |*s| {
            if (s.findEnum(enum_def)) |found| return found;
        }

        return null;
    }

    /// Finds a message definition within this struct or its nested structs
    pub fn findMessage(self: *ZigStruct, msg_def: *const Message) ?*ZigStruct {
        for (self.structs.items) |*s| {
            if (s.source == msg_def) return s;
            if (s.findMessage(msg_def)) |found| return found;
        }
        return null;
    }

    /// Resolves type references in the struct's fields
    pub fn resolve(self: *ZigStruct, file: *const ZigFile) !void {
        // Resolve nested structs first
        for (self.structs.items) |*s| {
            try s.resolve(file);
        }

        // Resolve field types
        for (self.fields.items) |*field| {
            switch (field.*) {
                .enumeration => |*fe| {
                    if (try TypeResolver.resolveEnum(file, fe.target_type)) |enum_name| {
                        try fe.resolve(enum_name);
                        self.allocator.free(enum_name);
                    }
                },
                .repeated_enum => |*fe| {
                    if (try TypeResolver.resolveEnum(file, fe.target_type)) |enum_name| {
                        try fe.resolve(enum_name);
                        self.allocator.free(enum_name);
                    }
                },
                .message => |*fm| {
                    if (try TypeResolver.resolveMessage(file, fm.target_type)) |msg_name| {
                        const reader_name = try std.mem.concat(self.allocator, u8, &.{ msg_name, "Reader" });
                        try fm.resolve(msg_name, reader_name);
                        self.allocator.free(msg_name);
                        self.allocator.free(reader_name);
                    }
                },
                .repeated_message => |*fm| {
                    if (try TypeResolver.resolveMessage(file, fm.target_type)) |msg_name| {
                        const reader_name = try std.mem.concat(self.allocator, u8, &.{ msg_name, "Reader" });
                        try fm.resolve(msg_name, reader_name);
                        self.allocator.free(msg_name);
                        self.allocator.free(reader_name);
                    }
                },
                .map => |*mf| {
                    if (mf.value_type.isEnum()) {
                        if (try TypeResolver.resolveEnum(file, mf.value_type)) |enum_name| {
                            try mf.resolveEnumValue(enum_name);
                            self.allocator.free(enum_name);
                        }
                    } else if (mf.value_type.isMsg()) {
                        if (try TypeResolver.resolveMessage(file, mf.value_type)) |msg_name| {
                            const reader_name = try std.mem.concat(self.allocator, u8, &.{ msg_name, "Reader" });
                            try mf.resoveMessageValue(msg_name, reader_name);
                            self.allocator.free(msg_name);
                            self.allocator.free(reader_name);
                        }
                    }
                },
                else => {},
            }
        }
    }
};

/// Helper for generating struct names
const NameGenerator = struct {
    pub const Names = struct {
        wire_enum_name: []const u8,
        writer_name: []const u8,
        reader_name: []const u8,
        full_wire_name: []const u8,
        full_writer_name: []const u8,
        full_reader_name: []const u8,
    };

    pub fn generate(allocator: std.mem.Allocator, name: []const u8, scope_name: []const u8, names: *std.ArrayList([]const u8)) !Names {
        const const_name = try naming.structName(allocator, name, names);
        defer allocator.free(const_name);

        const wire_enum_name = try std.mem.concat(allocator, u8, &.{ const_name, "Wire" });
        errdefer allocator.free(wire_enum_name);

        const writer_name = try allocator.dupe(u8, const_name);
        errdefer allocator.free(writer_name);

        const reader_name = try std.mem.concat(allocator, u8, &.{ const_name, "Reader" });
        errdefer allocator.free(reader_name);

        const full_names = try generateFullNames(allocator, scope_name, const_name, wire_enum_name);

        return Names{
            .wire_enum_name = wire_enum_name,
            .writer_name = writer_name,
            .reader_name = reader_name,
            .full_wire_name = full_names.wire,
            .full_writer_name = full_names.writer,
            .full_reader_name = full_names.reader,
        };
    }

    const FullNames = struct { wire: []const u8, writer: []const u8, reader: []const u8 };

    fn generateFullNames(allocator: std.mem.Allocator, scope: []const u8, const_name: []const u8, wire_name: []const u8) !FullNames {
        if (scope.len == 0) {
            return FullNames{
                .wire = try allocator.dupe(u8, wire_name),
                .writer = try allocator.dupe(u8, const_name),
                .reader = try allocator.dupe(u8, const_name),
            };
        }

        return FullNames{
            .wire = try std.mem.concat(allocator, u8, &.{ scope, ".", wire_name }),
            .writer = try std.mem.concat(allocator, u8, &.{ scope, ".", const_name }),
            .reader = try std.mem.concat(allocator, u8, &.{ scope, ".", const_name }),
        };
    }
};

/// Helper for building fields and nested types
const FieldsBuilder = struct {
    pub const Result = struct {
        enums: std.ArrayList(ZigEnum),
        structs: std.ArrayList(ZigStruct),
        fields: std.ArrayList(Field),
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Result) void {
            for (self.enums.items) |*e| e.deinit();
            self.enums.deinit(self.allocator);

            for (self.structs.items) |*s| s.deinit();
            self.structs.deinit(self.allocator);

            for (self.fields.items) |*f| f.deinit();
            self.fields.deinit(self.allocator);
        }
    };

    pub fn build(
        allocator: std.mem.Allocator,
        src: *const Message,
        scope_name: []const u8,
        full_wire_name: []const u8,
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !Result {
        var scope_names = try std.ArrayList([]const u8).initCapacity(allocator, 4);
        try scope_names.append(allocator, "calcProtoubfSize");
        try scope_names.append(allocator, "encode");
        defer scope_names.deinit(allocator);

        var result = Result{
            .allocator = allocator,
            .enums = try std.ArrayList(ZigEnum).initCapacity(allocator, 16),
            .structs = try std.ArrayList(ZigStruct).initCapacity(allocator, 16),
            .fields = try std.ArrayList(Field).initCapacity(allocator, 32),
        };

        try buildNestedTypes(allocator, &result, src, scope_name, &scope_names);
        try buildFields(
            allocator,
            &result,
            src,
            &scope_names,
            full_wire_name,
            writer_struct_name,
            reader_struct_name,
        );

        return result;
    }

    fn buildNestedTypes(
        allocator: std.mem.Allocator,
        result: *Result,
        src: *const Message,
        scope_name: []const u8,
        scope_names: *std.ArrayList([]const u8),
    ) anyerror!void {
        for (src.enums.items) |*e| {
            try result.enums.append(allocator, try ZigEnum.init(allocator, e, scope_name, scope_names));
        }

        for (src.messages.items) |*m| {
            try result.structs.append(allocator, try ZigStruct.init(allocator, m, scope_names, scope_name));
        }
    }

    fn buildFields(
        allocator: std.mem.Allocator,
        result: *Result,
        src: *const Message,
        scope_names: *std.ArrayList([]const u8),
        full_wire_name: []const u8,
        writer_struct_name: []const u8,
        reader_struct_name: []const u8,
    ) !void {
        try FieldBuilder.createNormalFields(
            allocator,
            &result.fields,
            src,
            scope_names,
            full_wire_name,
            writer_struct_name,
            reader_struct_name,
        );
        try FieldBuilder.createOneOfFields(
            allocator,
            &result.fields,
            src,
            scope_names,
            full_wire_name,
            writer_struct_name,
            reader_struct_name,
        );
        try FieldBuilder.createMapFields(
            allocator,
            &result.fields,
            src,
            scope_names,
            full_wire_name,
            writer_struct_name,
            reader_struct_name,
        );
    }
};

/// Helper for resolving type references
const TypeResolver = struct {
    pub fn resolveEnum(file: *const ZigFile, target_type: FieldType) !?[]const u8 {
        if (target_type.ref_local_enum) |local_enum| {
            return try file.findEnumName(local_enum);
        } else if (target_type.ref_external_enum) |external_enum| {
            return try file.findImportedEnumName(target_type.ref_import.?, external_enum);
        }
        return null;
    }

    pub fn resolveMessage(file: *const ZigFile, target_type: FieldType) !?[]const u8 {
        if (target_type.ref_local_message) |local_message| {
            return try file.findMessageName(local_message);
        } else if (target_type.ref_external_message) |external_message| {
            return try file.findImportedMessageName(target_type.ref_import.?, external_message);
        }
        return null;
    }
};
