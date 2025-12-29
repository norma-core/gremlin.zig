//! Provides functionality for generating Zig source files from Protocol Buffer definitions.
//! This module handles the conversion of .proto files into Zig code, managing imports,
//! type definitions, and code generation.

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
const ProtoFile = @import("../../parser/main.zig").ProtoFile;
const Enum = @import("../../parser/main.zig").Enum;
const Message = @import("../../parser/main.zig").Message;

const ZigEnum = @import("./enum.zig").ZigEnum;
const ZigStruct = @import("./struct.zig").ZigStruct;
const import = @import("./import.zig");
const ImportCollector = @import("./imports.zig").ImportCollector;
const FileOutput = @import("./output.zig").FileOutput;
const naming = @import("./fields/naming.zig");

/// Errors that can occur during ZigFile operations
pub const ZigFileError = error{
    /// Enum type reference could not be resolved
    EnumNotFound,
    /// Message type reference could not be resolved
    MessageNotFound,
    /// Import dependency could not be resolved
    ImportNotResolved,
};

/// Represents a generated Zig source file from a Protocol Buffer definition.
/// Manages the conversion of Protocol Buffer types to Zig types and handles
/// code generation for the complete file.
pub const ZigFile = struct {
    out_path: []const u8, // Output file path
    allocator: std.mem.Allocator,
    imports: std.ArrayList(import.ZigImport),
    enums: std.ArrayList(ZigEnum),
    structs: std.ArrayList(ZigStruct),
    file: *const ProtoFile, // Reference to source proto definition

    /// Initialize a new ZigFile from a Protocol Buffer definition.
    /// Sets up all necessary components for code generation including imports,
    /// enum definitions, and struct definitions.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for string and list allocations
    ///   - out_path: Path where the generated Zig file will be written
    ///   - file: Source Protocol Buffer file definition
    ///   - proto_root: Root directory of proto files
    ///   - target_root: Root directory for generated Zig files
    ///   - project_root: Root directory of the project
    ///
    /// Returns: A new ZigFile instance or an error if initialization fails
    pub fn init(
        allocator: std.mem.Allocator,
        out_path: []const u8,
        file: *const ProtoFile,
        proto_root: []const u8,
        target_root: []const u8,
        project_root: []const u8,
    ) !ZigFile {
        // Track names to avoid conflicts
        var names = try std.ArrayList([]const u8).initCapacity(allocator, 128);
        defer names.deinit(allocator);

        // Initialize components with proper cleanup on error
        var imports = try initImports(allocator, file, proto_root, target_root, project_root, &names);
        errdefer {
            for (imports.items) |*import_ref| import_ref.deinit();
            imports.deinit(allocator);
        }

        var enums = try initEnums(allocator, file, &names);
        errdefer {
            for (enums.items) |*enum_item| enum_item.deinit();
            enums.deinit(allocator);
        }

        var structs = try initStructs(allocator, file, &names);
        errdefer {
            for (structs.items) |*struct_item| struct_item.deinit();
            structs.deinit(allocator);
        }

        return ZigFile{
            .allocator = allocator,
            .out_path = try allocator.dupe(u8, out_path),
            .imports = imports,
            .enums = enums,
            .structs = structs,
            .file = file,
        };
    }

    /// Write the generated Zig code to the output file.
    /// Generates code for imports, enums, and structs in the correct order.
    ///
    /// Parameters:
    ///   - out_file: Output file handler to write the generated code
    pub fn write(self: *const ZigFile, out_file: *FileOutput) !void {
        try self.writeImports(out_file);
        try self.writeEnums(out_file);
        try self.writeStructs(out_file);
    }

    /// Resolve imports between files after all files have been initialized.
    /// This step is necessary to establish cross-file type references.
    ///
    /// Parameters:
    ///   - files: Slice of all generated Zig files for cross-reference resolution
    pub fn resolveImports(self: *ZigFile, files: []ZigFile) !void {
        for (self.imports.items) |*i| {
            try i.resolve(files);
        }
    }

    /// Resolve internal references within the file.
    /// This should be called after imports are resolved to establish all type references.
    pub fn resolveRefs(self: *ZigFile) !void {
        for (self.structs.items) |*s| {
            try s.resolve(self);
        }
    }

    /// Clean up all allocated resources associated with this file.
    pub fn deinit(self: *ZigFile) void {
        for (self.imports.items) |*import_ref| import_ref.deinit();
        self.imports.deinit(self.allocator);

        for (self.enums.items) |*enum_item| enum_item.deinit();
        self.enums.deinit(self.allocator);

        for (self.structs.items) |*struct_item| struct_item.deinit();
        self.structs.deinit(self.allocator);

        self.allocator.free(self.out_path);
    }

    /// Find methods for type resolution
    /// Finds the fully qualified name of an enum type within this file.
    /// Searches both top-level enums and nested enums within structs.
    ///
    /// Parameters:
    ///   - target: The enum definition to find
    ///
    /// Returns: The fully qualified name of the enum or an error if not found
    pub fn findEnumName(self: *const ZigFile, target: *const Enum) !?[]const u8 {
        // Check top-level enums
        for (self.enums.items) |*enum_item| {
            if (enum_item.src == target) {
                return try self.allocator.dupe(u8, enum_item.full_name);
            }
        }
        // Check nested enums in structs
        for (self.structs.items) |*struct_item| {
            if (struct_item.findEnum(target)) |found| {
                return try self.allocator.dupe(u8, found.full_name);
            }
        }
        return ZigFileError.EnumNotFound;
    }

    /// Finds the fully qualified name of an imported enum type.
    /// Searches through imports to locate the enum in another file.
    ///
    /// Parameters:
    ///   - target_file: The proto file containing the enum
    ///   - target_enum: The enum definition to find
    ///
    /// Returns: The fully qualified name including import alias or an error if not found
    pub fn findImportedEnumName(
        self: *const ZigFile,
        target_file: *const ProtoFile,
        target_enum: *const Enum,
    ) !?[]const u8 {
        for (self.imports.items) |*import_ref| {
            if (import_ref.is_system) continue;

            if (import_ref.target.?.file == target_file) {
                if (try import_ref.target.?.findEnumName(target_enum)) |found| {
                    defer self.allocator.free(found);
                    return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                        import_ref.alias, ".", found,
                    });
                }
            }
        }
        return ZigFileError.EnumNotFound;
    }

    /// Finds the fully qualified name of a message type within this file.
    /// Searches both top-level messages and nested messages within structs.
    ///
    /// Parameters:
    ///   - target: The message definition to find
    ///
    /// Returns: The fully qualified name or an error if not found
    pub fn findMessageName(self: *const ZigFile, target: *const Message) !?[]const u8 {
        for (self.structs.items) |*struct_item| {
            if (struct_item.source == target) {
                return try self.allocator.dupe(u8, struct_item.full_writer_name);
            }
            if (struct_item.findMessage(target)) |found| {
                return try self.allocator.dupe(u8, found.full_writer_name);
            }
        }
        return ZigFileError.MessageNotFound;
    }

    /// Finds the fully qualified name of an imported message type.
    /// Searches through imports to locate the message in another file.
    ///
    /// Parameters:
    ///   - target_file: The proto file containing the message
    ///   - target_msg: The message definition to find
    ///
    /// Returns: The fully qualified name including import alias or an error if not found
    pub fn findImportedMessageName(
        self: *const ZigFile,
        target_file: *const ProtoFile,
        target_msg: *const Message,
    ) !?[]const u8 {
        for (self.imports.items) |*import_ref| {
            if (import_ref.is_system) continue;

            if (import_ref.target.?.file == target_file) {
                if (try import_ref.target.?.findMessageName(target_msg)) |found| {
                    defer self.allocator.free(found);
                    return try std.mem.concat(self.allocator, u8, &[_][]const u8{
                        import_ref.alias, ".", found,
                    });
                }
            }
        }
        return ZigFileError.ImportNotResolved;
    }

    // Private helper functions

    /// Initialize system imports (std and gremlin)
    fn initSystemImports(
        allocator: std.mem.Allocator,
        imports: *std.ArrayList(import.ZigImport),
        names: *std.ArrayList([]const u8),
    ) !void {
        var std_import = try import.ZigImport.init(allocator, null, "std", "std");
        errdefer std_import.deinit();

        var gremlin_import = try import.ZigImport.init(allocator, null, "gremlin", "gremlin");
        errdefer gremlin_import.deinit();

        try imports.append(allocator, std_import);
        try imports.append(allocator, gremlin_import);

        try names.append(allocator, std_import.alias);
        try names.append(allocator, gremlin_import.alias);
    }

    /// Initialize all imports for the file
    fn initImports(
        allocator: std.mem.Allocator,
        file: *const ProtoFile,
        proto_root: []const u8,
        target_root: []const u8,
        project_root: []const u8,
        names: *std.ArrayList([]const u8),
    ) !std.ArrayList(import.ZigImport) {
        var imports = try std.ArrayList(import.ZigImport).initCapacity(allocator, 16);
        errdefer imports.deinit(allocator);

        if (file.messages.items.len > 0) {
            try initSystemImports(allocator, &imports, names);
        }

        const used_imports = try ImportCollector.collectFromFile(allocator, file);
        defer allocator.free(used_imports);

        for (used_imports) |import_file| {
            const resolved = try import.importResolve(
                allocator,
                import_file,
                proto_root,
                target_root,
                project_root,
                import_file.path.?,
                file.path.?,
                names,
            );
            try imports.append(allocator, resolved);
        }

        return imports;
    }

    /// Initialize enum definitions from the proto file
    fn initEnums(
        allocator: std.mem.Allocator,
        file: *const ProtoFile,
        names: *std.ArrayList([]const u8),
    ) !std.ArrayList(ZigEnum) {
        var enums = try std.ArrayList(ZigEnum).initCapacity(allocator, 128);
        for (file.enums.items) |*enum_item| {
            const zig_enum = try ZigEnum.init(allocator, enum_item, "", names);
            try enums.append(allocator, zig_enum);
        }
        return enums;
    }

    /// Initialize struct definitions from the proto file
    fn initStructs(
        allocator: std.mem.Allocator,
        file: *const ProtoFile,
        names: *std.ArrayList([]const u8),
    ) !std.ArrayList(ZigStruct) {
        var structs = try std.ArrayList(ZigStruct).initCapacity(allocator, 128);
        for (file.messages.items) |*msg| {
            const zig_struct = try ZigStruct.init(allocator, msg, names, "");
            try structs.append(allocator, zig_struct);
        }
        return structs;
    }

    /// Write import statements to the output file
    fn writeImports(self: *const ZigFile, out_file: *FileOutput) !void {
        for (self.imports.items) |*import_ref| {
            const import_str = try import_ref.code();
            defer self.allocator.free(import_str);
            try out_file.writeString(import_str);
        }
    }

    /// Write enum definitions to the output file
    fn writeEnums(self: *const ZigFile, out_file: *FileOutput) !void {
        if (self.enums.items.len == 0) return;

        try out_file.linebreak();
        try out_file.writeComment("enums");

        for (self.enums.items) |*enum_item| {
            const code = try enum_item.createEnumDef(self.allocator);
            defer self.allocator.free(code);
            try out_file.writeString(code);
        }
    }

    /// Write struct definitions to the output file
    fn writeStructs(self: *const ZigFile, out_file: *FileOutput) !void {
        if (self.structs.items.len == 0) return;

        try out_file.linebreak();
        try out_file.writeComment("structs");

        for (self.structs.items) |*struct_item| {
            try struct_item.code(out_file);
        }
    }
};
