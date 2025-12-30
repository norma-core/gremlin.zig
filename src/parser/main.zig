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
const parser = @import("./parser.zig");

pub const parse = parser.parse;
pub const ParseResult = parser.ParseResult;
pub const ParserBuffer = @import("entries/buffer.zig").ParserBuffer;

pub const ProtoFile = @import("entries/file.zig").ProtoFile;
pub const Import = @import("entries/import.zig").Import;
pub const ImportType = @import("entries/import.zig").ImportType;
pub const Enum = @import("entries/enum.zig").Enum;
pub const Message = @import("entries/message.zig").Message;
pub const fields = @import("entries/field.zig");
pub const FieldType = @import("entries/field-type.zig").FieldType;
pub const ScopedName = @import("entries/scoped-name.zig").ScopedName;
pub const Option = @import("entries/option.zig").Option;

test {
    std.testing.refAllDecls(parser);
}
