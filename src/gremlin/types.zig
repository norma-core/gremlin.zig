//! Core protocol buffer wire format types and error definitions
//! Provides type definitions for protocol buffer wire format encoding/decoding

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
// Created by ab, 14.08.2024

/// Field number in protocol buffer message
pub const ProtoWireNumber = i32;

/// Wire types defined by protocol buffer specification
pub const ProtoWireType = enum(u64) {
    varint = 0,
    fixed64 = 1,
    bytes = 2,
    startGroup = 3,
    endGroup = 4,
    fixed32 = 5,
};

/// Complete tag information for a protocol buffer field
pub const ProtoTag = struct {
    number: ProtoWireNumber,
    wire: ProtoWireType,
    size: usize,
};

/// Generic sized value wrapper
fn Sized(comptime T: type) type {
    return struct {
        size: usize,
        value: T,
    };
}

// Basic numeric types with size information
pub const SizedU32 = Sized(u32);
pub const SizedU64 = Sized(u64);
pub const SizedI32 = Sized(i32);
pub const SizedI64 = Sized(i64);
pub const SizedF32 = Sized(f32);
pub const SizedF64 = Sized(f64);

// Other sized basic types
pub const SizedBool = Sized(bool);
pub const SizedBytes = Sized([]const u8);

/// Protocol buffer encoding/decoding errors
pub const Error = error{ InvalidVarInt, // Invalid variable integer encoding
    InvalidTag, // Invalid field tag
    InvalidData, // Data doesn't match expected format
    OutOfMemory // Memory allocation failed
    };
