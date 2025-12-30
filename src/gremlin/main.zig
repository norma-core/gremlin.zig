//! Protocol buffer wire format encoder/decoder implementation
//! Provides functionality for reading and writing protocol buffer wire format messages
//!
//! Main components:
//! - Writer: Handles encoding messages to wire format
//! - Reader: Handles decoding wire format messages
//! - ProtoWireNumber: Field numbers for proto fields
//! - ProtoWireType: Wire types for proto fields

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
// Created by ab, 05.11.2024

const std = @import("std");

const types = @import("types.zig");
const writer = @import("writer.zig");
const reader = @import("reader.zig");

pub const ProtoWireNumber = types.ProtoWireNumber;
pub const ProtoWireType = types.ProtoWireType;
pub const sizes = @import("sizes.zig");
pub const Writer = writer.Writer;
pub const Reader = reader.Reader;
pub const Error = types.Error;

test {
    std.testing.refAllDecls(sizes);
    std.testing.refAllDecls(writer);
    std.testing.refAllDecls(reader);
}
