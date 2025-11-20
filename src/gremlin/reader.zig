//! Protocol buffer wire format reader
//! Provides functionality for decoding protocol buffer encoded messages

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
const types = @import("types.zig");
const ProtoWireNumber = types.ProtoWireNumber;
const ProtoWireType = types.ProtoWireType;
const ProtoTag = types.ProtoTag;
const Error = types.Error;

/// Reader for decoding protocol buffer wire format
pub const Reader = struct {
    buf: []const u8,

    /// Initialize a new reader with given data buffer
    pub fn init(data: []const u8) Reader {
        return .{ .buf = data };
    }

    /// Get underlying buffer
    pub fn bytes(self: Reader) []const u8 {
        return self.buf;
    }

    /// Read tag information at given offset
    pub fn readTagAt(self: Reader, offset: usize) Error!ProtoTag {
        const tag_data = try self.readVarIntAt(offset);
        if (tag_data.value >> 3 > std.math.maxInt(i32)) {
            return Error.InvalidTag;
        }

        return ProtoTag{
            .number = @as(ProtoWireNumber, @intCast(tag_data.value >> 3)),
            .wire = @as(ProtoWireType, @enumFromInt(@as(u3, @truncate(tag_data.value)))),
            .size = tag_data.size,
        };
    }

    /// Skip data of given wire type at offset
    pub fn skipData(self: Reader, offset: usize, wire: ProtoWireType) Error!usize {
        switch (wire) {
            .varint => {
                const size = try self.getVarIntSize(offset);
                return offset + size;
            },
            .fixed32 => return offset + 4,
            .fixed64 => return offset + 8,
            .bytes => {
                const size_data = try self.readVarIntAt(offset);
                return offset + size_data.size + @as(usize, @intCast(size_data.value));
            },
            .startGroup => {
                var current_offset = offset;
                while (true) {
                    const tag = try self.readTagAt(current_offset);
                    current_offset += tag.size;

                    if (tag.wire == .endGroup) return current_offset;
                    current_offset = try self.skipData(current_offset, tag.wire);
                }
            },
            else => return Error.InvalidTag,
        }
    }

    /// Get size of varint at offset
    fn getVarIntSize(self: Reader, offset: usize) Error!usize {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            if (!self.hasNext(offset, i)) return Error.InvalidVarInt;
            if (self.buf[offset + i] < 0x80) return i + 1;
        }
        return 10;
    }

    /// Read 32-bit fixed integer at offset
    fn readFixed32At(self: Reader, offset: usize) Error!u32 {
        if (!self.hasNext(offset, 3)) return Error.InvalidData;
        return @as(u32, self.buf[offset]) |
            @as(u32, self.buf[offset + 1]) << 8 |
            @as(u32, self.buf[offset + 2]) << 16 |
            @as(u32, self.buf[offset + 3]) << 24;
    }

    /// Read 64-bit fixed integer at offset
    fn readFixed64At(self: Reader, offset: usize) Error!u64 {
        if (!self.hasNext(offset, 7)) return Error.InvalidData;
        return @as(u64, self.buf[offset]) |
            @as(u64, self.buf[offset + 1]) << 8 |
            @as(u64, self.buf[offset + 2]) << 16 |
            @as(u64, self.buf[offset + 3]) << 24 |
            @as(u64, self.buf[offset + 4]) << 32 |
            @as(u64, self.buf[offset + 5]) << 40 |
            @as(u64, self.buf[offset + 6]) << 48 |
            @as(u64, self.buf[offset + 7]) << 56;
    }

    // String and bytes
    /// Read length-delimited bytes at offset
    pub fn readBytes(self: Reader, offset: usize) Error!types.SizedBytes {
        const size_data = try self.readVarIntAt(offset);
        const start = offset + size_data.size;
        const end = start + @as(usize, @intCast(size_data.value));
        return .{
            .value = self.buf[start..end],
            .size = size_data.size + @as(usize, @intCast(size_data.value)),
        };
    }

    // Varint types
    /// Read raw varint at offset
    pub fn readVarInt(self: Reader, offset: usize) Error!types.SizedU64 {
        return self.readVarIntAt(offset);
    }

    /// Read unsigned 64-bit integer at offset
    pub fn readUInt64(self: Reader, offset: usize) Error!types.SizedU64 {
        return self.readVarInt(offset);
    }

    /// Read unsigned 32-bit integer at offset
    pub fn readUInt32(self: Reader, offset: usize) Error!types.SizedU32 {
        const result = try self.readVarIntAt(offset);
        return .{
            .value = @as(u32, @truncate(result.value)),
            .size = result.size,
        };
    }

    /// Read signed 64-bit integer at offset
    pub fn readInt64(self: Reader, offset: usize) Error!types.SizedI64 {
        const result = try self.readVarIntAt(offset);
        return .{
            .value = @as(i64, @bitCast(result.value)),
            .size = result.size,
        };
    }

    /// Read signed 32-bit integer at offset
    pub fn readInt32(self: Reader, offset: usize) Error!types.SizedI32 {
        const result = try self.readVarIntAt(offset);
        return .{
            .value = @as(i32, @truncate(@as(i64, @bitCast(result.value)))),
            .size = result.size,
        };
    }

    /// Read zigzag encoded signed 64-bit integer at offset
    pub fn readSInt64(self: Reader, offset: usize) Error!types.SizedI64 {
        return self.readSignedVarIntAt(offset);
    }

    /// Read zigzag encoded signed 32-bit integer at offset
    pub fn readSInt32(self: Reader, offset: usize) Error!types.SizedI32 {
        const result = try self.readSignedVarIntAt(offset);
        return .{
            .value = @as(i32, @truncate(result.value)),
            .size = result.size,
        };
    }

    /// Read boolean value at offset
    pub fn readBool(self: Reader, offset: usize) Error!types.SizedBool {
        const result = try self.readVarIntAt(offset);
        return .{
            .value = result.value != 0,
            .size = result.size,
        };
    }

    /// Read 32-bit float at offset
    pub fn readFloat32(self: Reader, offset: usize) Error!types.SizedF32 {
        const value = try self.readFixed32At(offset);
        return .{
            .value = @as(f32, @bitCast(value)),
            .size = 4,
        };
    }

    /// Read 64-bit float at offset
    pub fn readFloat64(self: Reader, offset: usize) Error!types.SizedF64 {
        const value = try self.readFixed64At(offset);
        return .{
            .value = @as(f64, @bitCast(value)),
            .size = 8,
        };
    }

    // Fixed types
    /// Read fixed 32-bit unsigned integer at offset
    pub fn readFixed32(self: Reader, offset: usize) Error!types.SizedU32 {
        return .{
            .value = try self.readFixed32At(offset),
            .size = 4,
        };
    }

    /// Read fixed 64-bit unsigned integer at offset
    pub fn readFixed64(self: Reader, offset: usize) Error!types.SizedU64 {
        return .{
            .value = try self.readFixed64At(offset),
            .size = 8,
        };
    }

    /// Read fixed 32-bit signed integer at offset
    pub fn readSFixed32(self: Reader, offset: usize) Error!types.SizedI32 {
        return .{
            .value = @as(i32, @bitCast(try self.readFixed32At(offset))),
            .size = 4,
        };
    }

    /// Read fixed 64-bit signed integer at offset
    pub fn readSFixed64(self: Reader, offset: usize) Error!types.SizedI64 {
        return .{
            .value = @as(i64, @bitCast(try self.readFixed64At(offset))),
            .size = 8,
        };
    }

    /// Check if offset + size is within buffer bounds
    pub fn hasNext(self: Reader, offset: usize, size: usize) bool {
        return (offset + size) < self.buf.len;
    }

    /// Read zigzag encoded signed varint at offset
    fn readSignedVarIntAt(self: Reader, offset: usize) Error!types.SizedI64 {
        const result = try self.readVarIntAt(offset);
        // ZigZag decoding using only bit operations
        const value = @as(i64, @bitCast((result.value >> 1) ^ (~(result.value & 1) +% 1)));
        return .{
            .value = value,
            .size = result.size,
        };
    }

    /// Read raw varint at offset
    fn readVarIntAt(self: Reader, offset: usize) Error!types.SizedU64 {
        var value: u64 = 0;
        var shift: u6 = 0;
        var i: usize = 0;

        while (i < 10) : (i += 1) {
            if (!self.hasNext(offset, i)) return Error.InvalidVarInt;

            const b = self.buf[offset + i];
            if (shift >= 64) return Error.InvalidVarInt;

            value |= @as(u64, b & 0x7F) << @intCast(shift);

            if (b < 0x80) {
                return .{
                    .value = value,
                    .size = i + 1,
                };
            }

            if (shift > 57) return Error.InvalidVarInt; // 64 - 7
            shift += 7;
        }

        return Error.InvalidVarInt;
    }
};

test "decode sint64" {
    // Test decoding a specific sint64 value (106)
    const data = [_]u8{ 212, 1 };
    const reader = Reader.init(&data);

    const result = try reader.readSInt64(0);
    try std.testing.expectEqual(@as(i64, 106), result.value);
}

test "read negative int64" {
    // Expected value should be encoded as unsigned 18446744073709551584
    // Buffer should contain [8 224 255 255 255 255 255 255 255 255 1]
    const expected_buf = [_]u8{ 8, 224, 255, 255, 255, 255, 255, 255, 255, 255, 1 };

    // Now read it back
    const reader = Reader.init(&expected_buf);
    const tag_result = try reader.readTagAt(0);
    try std.testing.expectEqual(@as(types.ProtoWireNumber, 1), tag_result.number);
    try std.testing.expectEqual(types.ProtoWireType.varint, tag_result.wire);

    const read_result = try reader.readInt64(tag_result.size);
    try std.testing.expectEqual(@as(i64, -32), read_result.value);
}

test "read vector of enums" {
    // Hex: 0a03000102
    const data = [_]u8{ 0x0a, 0x03, 0x00, 0x01, 0x02 };

    // Read and verify the data
    const reader = Reader.init(&data);
    var offset: usize = 0;

    while (reader.hasNext(offset, 0)) {
        // Read tag
        const tag = try reader.readTagAt(offset);
        offset += tag.size;

        // Read bytes content
        const content = try reader.readBytes(offset);
        offset += content.size;

        // Verify the content is [0, 1, 2]
        try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 1, 2 }, content.value);
    }
}
