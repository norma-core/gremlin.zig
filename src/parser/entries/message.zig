//! Message parser module for Protocol Buffer definitions.
//! Handles parsing of message declarations including all nested elements
//! like fields, oneofs, maps, enums, and nested messages.

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
const Error = @import("errors.zig").Error;
const lex = @import("lexems.zig");
const Option = @import("option.zig").Option;
const Reserved = @import("reserved.zig").Reserved;
const Extensions = @import("extensions.zig").Extensions;
const Extend = @import("extend.zig").Extend;
const fields = @import("field.zig");
const Enum = @import("enum.zig").Enum;
const Group = @import("group.zig").Group;
const ScopedName = @import("scoped-name.zig").ScopedName;

/// Represents a Protocol Buffer message definition.
/// Messages can contain fields, nested messages/enums, options,
/// and other elements that define the message structure.
pub const Message = struct {
    /// Starting byte offset in source
    start: usize,
    /// Ending byte offset in source
    end: usize,

    /// Fully qualified name of the message
    name: ScopedName,

    /// Message options (e.g., deprecated = true)
    options: std.ArrayList(Option),
    /// Oneof field groups
    oneofs: std.ArrayList(fields.MessageOneOfField),
    /// Map fields
    maps: std.ArrayList(fields.MessageMapField),
    /// Regular fields
    fields: std.ArrayList(fields.NormalField),
    /// Reserved field numbers/names
    reserved: std.ArrayList(Reserved),
    /// Extension ranges
    extensions: std.ArrayList(Extensions),
    /// Extend blocks
    extends: std.ArrayList(Extend),
    /// Proto2 groups (deprecated)
    groups: std.ArrayList(Group),

    /// Nested enum definitions
    enums: std.ArrayList(Enum),
    /// Nested message definitions
    messages: std.ArrayList(Message),

    /// Parent message (if nested)
    parent: ?*Message = null,

    allocator: std.mem.Allocator,

    /// Parses a message definition including all its contents.
    /// Handles nested messages, enums, fields, and all other valid
    /// message elements.
    ///
    /// # Arguments
    /// * `allocator` - Allocator for dynamic memory
    /// * `buf` - Parser buffer containing the message
    /// * `parent` - Parent scope if this is a nested message
    ///
    /// # Returns
    /// The parsed message or null if input doesn't start with a message
    ///
    /// # Errors
    /// Returns error on invalid syntax or allocation failure
    pub fn parse(allocator: std.mem.Allocator, buf: *ParserBuffer, parent: ?ScopedName) Error!?Message {
        try buf.skipSpaces();
        const start = buf.offset;

        // Check for message keyword
        if (!buf.checkStrWithSpaceAndShift("message")) {
            return null;
        }

        // Parse message name and opening brace
        const name = try lex.ident(buf);
        try buf.openBracket();

        // Build scoped name
        var scoped: ScopedName = undefined;
        if (parent) |*p| {
            scoped = try p.child(name);
        } else {
            scoped = try ScopedName.init(allocator, name);
        }

        // Initialize storage for message elements
        var options = try std.ArrayList(Option).initCapacity(allocator, 32);
        var oneofs = try std.ArrayList(fields.MessageOneOfField).initCapacity(allocator, 32);
        var maps = try std.ArrayList(fields.MessageMapField).initCapacity(allocator, 32);
        var mfields = try std.ArrayList(fields.NormalField).initCapacity(allocator, 32);
        var enums = try std.ArrayList(Enum).initCapacity(allocator, 32);
        var messages = try std.ArrayList(Message).initCapacity(allocator, 32);
        var reserved = try std.ArrayList(Reserved).initCapacity(allocator, 32);
        var extensions = try std.ArrayList(Extensions).initCapacity(allocator, 32);
        var extends = try std.ArrayList(Extend).initCapacity(allocator, 32);
        var groups = try std.ArrayList(Group).initCapacity(allocator, 32);
        // Parse message contents until closing brace
        while (true) {
            try buf.skipSpaces();
            const c = try buf.char();
            if (c == '}') {
                buf.offset += 1;
                break;
            } else if (c == ';') {
                buf.offset += 1;
                continue;
            }

            // Try parsing each possible message element
            if (try Option.parse(buf)) |opt| {
                try options.append(allocator, opt);
            } else if (try fields.MessageOneOfField.parse(allocator, scoped, buf)) |oneof| {
                try oneofs.append(allocator, oneof);
            } else if (try fields.MessageMapField.parse(allocator, scoped, buf)) |map| {
                try maps.append(allocator, map);
            } else if (try Reserved.parse(allocator, buf)) |res| {
                try reserved.append(allocator, res);
            } else if (try Extensions.parse(allocator, buf)) |res| {
                try extensions.append(allocator, res);
            } else if (try Extend.parse(allocator, buf)) |res| {
                try extends.append(allocator, res);
            } else if (try Group.parse(buf)) |res| {
                try groups.append(allocator, res);
            } else if (try Enum.parse(allocator, buf, scoped)) |en| {
                try enums.append(allocator, en);
            } else if (try Message.parse(allocator, buf, scoped)) |msg| {
                try messages.append(allocator, msg);
            } else {
                // If none of the above, must be a normal field
                try mfields.append(allocator, try fields.NormalField.parse(allocator, scoped, buf));
            }
        }

        return Message{
            .start = start,
            .end = buf.offset,
            .name = scoped,
            .options = options,
            .oneofs = oneofs,
            .maps = maps,
            .fields = mfields,
            .reserved = reserved,
            .extensions = extensions,
            .extends = extends,
            .groups = groups,
            .enums = enums,
            .messages = messages,
            .allocator = allocator,
        };
    }

    /// Frees all resources owned by the message
    pub fn deinit(self: *@This()) void {
        for (self.oneofs.items) |*oneof| {
            oneof.deinit();
        }
        for (self.maps.items) |*map| {
            map.deinit();
        }
        for (self.fields.items) |*field| {
            field.deinit();
        }
        for (self.reserved.items) |*res| {
            res.deinit();
        }
        for (self.extensions.items) |*ext| {
            ext.deinit();
        }
        for (self.enums.items) |*en| {
            en.deinit();
        }
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        for (self.extends.items) |*ext| {
            ext.deinit();
        }

        self.name.deinit();
        self.options.deinit(self.allocator);
        self.oneofs.deinit(self.allocator);
        self.maps.deinit(self.allocator);
        self.fields.deinit(self.allocator);
        self.reserved.deinit(self.allocator);
        self.enums.deinit(self.allocator);
        self.messages.deinit(self.allocator);
        self.extensions.deinit(self.allocator);
        self.extends.deinit(self.allocator);
        self.groups.deinit(self.allocator);
    }

    /// Returns whether the message has any field definitions
    pub fn has_fields(self: *const @This()) bool {
        return self.fields.items.len != 0 or
            self.oneofs.items.len != 0 or
            self.maps.items.len != 0;
    }
};

test "basic message" {
    var buf = ParserBuffer.init(
        \\message Outer {
        \\    option (my_option).a = true;
        \\    message Inner {   // Level 2
        \\      int64 ival = 1;
        \\    }
        \\    map<int32, string> my_map = 2;
        \\}
    );
    var msg = try Message.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer msg.deinit();

    try std.testing.expectEqualStrings("Outer", msg.name.full);
    try std.testing.expectEqual(1, msg.options.items.len);
    try std.testing.expectEqualStrings("(my_option).a", msg.options.items[0].name);
    try std.testing.expectEqualStrings("true", msg.options.items[0].value);

    try std.testing.expectEqual(1, msg.messages.items.len);
    try std.testing.expectEqualStrings("Outer.Inner", msg.messages.items[0].name.full);
    try std.testing.expectEqual(1, msg.messages.items[0].fields.items.len);
    try std.testing.expectEqualStrings("ival", msg.messages.items[0].fields.items[0].f_name);
    try std.testing.expectEqual(1, msg.messages.items[0].fields.items[0].index);

    try std.testing.expectEqual(1, msg.maps.items.len);
    try std.testing.expectEqualStrings("my_map", msg.maps.items[0].f_name);
    try std.testing.expectEqualStrings("int32", msg.maps.items[0].key_type);
    try std.testing.expectEqualStrings("string", msg.maps.items[0].value_type.src);
    try std.testing.expectEqual(2, msg.maps.items[0].index);
}

test "message with enum" {
    var buf = ParserBuffer.init(
        \\message Outer {
        \\    enum InnerEnum {
        \\        VAL1 = 1;
        \\        VAL2 = 2;
        \\    };
        \\    InnerEnum usage = 1;
        \\}
    );
    var msg = try Message.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer msg.deinit();

    try std.testing.expectEqualStrings("Outer", msg.name.full);
    try std.testing.expectEqual(1, msg.enums.items.len);
    try std.testing.expectEqualStrings("Outer.InnerEnum", msg.enums.items[0].name.full);
    try std.testing.expectEqual(2, msg.enums.items[0].fields.items.len);
    try std.testing.expectEqualStrings("VAL1", msg.enums.items[0].fields.items[0].name);
    try std.testing.expectEqual(1, msg.enums.items[0].fields.items[0].index);
    try std.testing.expectEqualStrings("VAL2", msg.enums.items[0].fields.items[1].name);
    try std.testing.expectEqual(2, msg.enums.items[0].fields.items[1].index);

    try std.testing.expectEqual(1, msg.fields.items.len);
    try std.testing.expectEqualStrings("usage", msg.fields.items[0].f_name);
    try std.testing.expectEqual(1, msg.fields.items[0].index);
}

test "just another message" {
    var buf = ParserBuffer.init(
        \\    message ConfirmEmailResponse {
        \\      enum ConfirmEmailError {
        \\        unknown_code = 0;
        \\      }
        \\      bool ok = 1;
        \\      ConfirmEmailError error = 2;
        \\    }
    );
    var msg = try Message.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer msg.deinit();

    try std.testing.expectEqualStrings("ConfirmEmailResponse", msg.name.name);
    try std.testing.expectEqual(0, msg.options.items.len);
    try std.testing.expectEqual(0, msg.oneofs.items.len);
    try std.testing.expectEqual(0, msg.maps.items.len);
    try std.testing.expectEqual(0, msg.reserved.items.len);
    try std.testing.expectEqual(0, msg.extensions.items.len);
    try std.testing.expectEqual(1, msg.enums.items.len);
    try std.testing.expectEqualStrings("ConfirmEmailResponse.ConfirmEmailError", msg.enums.items[0].name.full);
    try std.testing.expectEqual(1, msg.enums.items[0].fields.items.len);
    try std.testing.expectEqualStrings("unknown_code", msg.enums.items[0].fields.items[0].name);
    try std.testing.expectEqual(0, msg.enums.items[0].fields.items[0].index);
    try std.testing.expectEqual(2, msg.fields.items.len);
    try std.testing.expectEqualStrings("ok", msg.fields.items[0].f_name);
    try std.testing.expectEqual(1, msg.fields.items[0].index);
    try std.testing.expectEqualStrings("error", msg.fields.items[1].f_name);
    try std.testing.expectEqual(2, msg.fields.items[1].index);
}

test "oneof commas" {
    var buf = ParserBuffer.init(
        \\       message Outer {
        \\          message FieldValue {
        \\              oneof value {
        \\                  string string_value = 2 [json_name = "stringValue"];
        \\                  uint64 uint_value   = 3;
        \\                  string datetime_value = 4;
        \\                  bool   bool_value   = 5;
        \\              };
        \\          }
        \\      }
    );
    var msg = try Message.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer msg.deinit();

    try std.testing.expectEqualStrings("Outer", msg.name.full);
}

test "repeated group" {
    var buf = ParserBuffer.init(
        \\  message Message3672 {
        \\    optional .benchmarks.google_message3.Enum3476 field3727 = 1;
        \\    optional int32 field3728 = 11;
        \\    optional int32 field3729 = 2;
        \\    repeated group Message3673 = 3 {
        \\      required .benchmarks.google_message3.Enum3476 field3738 = 4;
        \\      required int32 field3739 = 5;
        \\    }
        \\    repeated group Message3674 = 6 {
        \\      required .benchmarks.google_message3.Enum3476 field3740 = 7;
        \\      required int32 field3741 = 8;
        \\    }
        \\    optional bool field3732 = 9;
        \\    optional int32 field3733 = 10;
        \\    optional .benchmarks.google_message3.Enum3476 field3734 = 20;
        \\    optional int32 field3735 = 21;
        \\    optional .benchmarks.google_message3.UnusedEmptyMessage field3736 = 50;
        \\    extend .benchmarks.google_message3.Message0 {
        \\      optional .benchmarks.google_message3.Message3672 field3737 = 3144435;
        \\    }
        \\  }
    );

    var msg = try Message.parse(std.testing.allocator, &buf, null) orelse unreachable;
    defer msg.deinit();
}
