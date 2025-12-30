//! Size calculation functions for protocol buffer wire format types
//! Used to determine byte size of encoded values before writing

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

const std = @import("std");
const types = @import("types.zig");

/// Calculate size of variable-length integer
pub fn sizeVarInt(value: u64) u32 {
    if (value < 1 << 7) return 1;
    if (value < 1 << 14) return 2;
    if (value < 1 << 21) return 3;
    if (value < 1 << 28) return 4;
    if (value < 1 << 35) return 5;
    if (value < 1 << 42) return 6;
    if (value < 1 << 49) return 7;
    if (value < 1 << 56) return 8;
    if (value < 1 << 63) return 9;
    return 10;
}

/// Calculate size of zigzag encoded signed integer
fn sizeSignedVarInt(value: i64) u32 {
    const encoded = @as(u64, @bitCast(value << 1)) ^ @as(u64, @bitCast(value >> 63));
    return sizeVarInt(encoded);
}

// Basic types
pub fn sizeBool(_: bool) u32 {
    return 1;
}

// Variable-length integer types
pub fn sizeI32(data: i32) u32 {
    const value = @as(i64, data);
    return sizeVarInt(@as(u64, @bitCast(value)));
}

pub fn sizeI64(value: i64) u32 {
    return sizeVarInt(@as(u64, @bitCast(value)));
}

pub fn sizeU32(value: u32) u32 {
    return sizeVarInt(@as(u64, value));
}

pub fn sizeU64(value: u64) u32 {
    return sizeVarInt(value);
}

pub fn sizeUsize(value: usize) u32 {
    return sizeVarInt(@as(u64, value));
}

// Zigzag encoded signed integer types
pub fn sizeSI32(value: i32) u32 {
    return sizeSignedVarInt(@as(i64, value));
}

pub fn sizeSI64(value: i64) u32 {
    return sizeSignedVarInt(value);
}

// Fixed-length integer types
pub fn sizeFixed32(_: u32) u32 {
    return 4;
}

pub fn sizeFixed64(_: u64) u32 {
    return 8;
}

pub fn sizeSFixed32(_: i32) u32 {
    return 4;
}

pub fn sizeSFixed64(_: i64) u32 {
    return 8;
}

// Floating point types
pub fn sizeFloat(_: f32) u32 {
    return 4;
}

pub fn sizeDouble(_: f64) u32 {
    return 8;
}

/// Calculate size of wire number tag
pub fn sizeWireNumber(comptime tag: types.ProtoWireNumber) usize {
    const tag_int: u64 = (tag << 3) | 0;
    return sizeU64(tag_int);
}

test "wire number size" {
    const wn: types.ProtoWireNumber = 10;
    const size = sizeWireNumber(wn);
    try std.testing.expectEqual(1, size);
}
