//! Protocol buffer wire format writer
//! Handles encoding of protocol buffer messages according to wire format specification

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
const ProtoWireNumber = @import("types.zig").ProtoWireNumber;
const ProtoWireType = @import("types.zig").ProtoWireType;

/// Writes protocol buffer encoded data to a buffer
pub const Writer = struct {
    buf: []u8,
    pos: usize,

    /// Initialize writer with output buffer
    pub fn init(buf: []u8) Writer {
        return .{ .buf = buf, .pos = 0 };
    }

    /// Reset writer position
    pub fn reset(self: *Writer) void {
        self.pos = 0;
    }

    // Basic types
    /// Write length-delimited bytes with tag
    pub fn appendBytes(self: *Writer, tag: ProtoWireNumber, data: []const u8) void {
        self.appendTag(tag, .bytes);
        self.appendVarInt(@as(u64, data.len));
        self.writeBytes(data);
    }

    /// Write bytes length prefix only
    pub fn appendBytesTag(self: *Writer, tag: ProtoWireNumber, len: usize) void {
        self.appendTag(tag, .bytes);
        self.appendVarInt(@as(u64, len));
    }

    /// Write boolean value with tag
    pub fn appendBool(self: *Writer, tag: ProtoWireNumber, data: bool) void {
        self.appendTag(tag, .varint);
        self.appendBoolWithoutTag(data);
    }

    /// Write boolean value without tag
    pub fn appendBoolWithoutTag(self: *Writer, data: bool) void {
        self.appendVarInt(if (data) @as(u64, 1) else @as(u64, 0));
    }

    // Integer types
    /// Write signed 32-bit integer with tag
    pub fn appendInt32(self: *Writer, tag: ProtoWireNumber, data: i32) void {
        self.appendTag(tag, .varint);
        self.appendInt32WithoutTag(data);
    }

    /// Write signed 32-bit integer without tag
    pub fn appendInt32WithoutTag(self: *Writer, data: i32) void {
        const value = @as(i64, data);
        self.appendVarInt(@as(u64, @bitCast(value)));
    }

    /// Write signed 64-bit integer with tag
    pub fn appendInt64(self: *Writer, tag: ProtoWireNumber, data: i64) void {
        self.appendTag(tag, .varint);
        self.appendInt64WithoutTag(data);
    }

    /// Write signed 64-bit integer without tag
    pub fn appendInt64WithoutTag(self: *Writer, data: i64) void {
        self.appendVarInt(@as(u64, @bitCast(data)));
    }

    /// Write unsigned 32-bit integer with tag
    pub fn appendUint32(self: *Writer, tag: ProtoWireNumber, data: u32) void {
        self.appendTag(tag, .varint);
        self.appendUint32WithoutTag(data);
    }

    /// Write unsigned 32-bit integer without tag
    pub fn appendUint32WithoutTag(self: *Writer, data: u32) void {
        self.appendVarInt(@as(u64, data));
    }

    /// Write unsigned 64-bit integer with tag
    pub fn appendUint64(self: *Writer, tag: ProtoWireNumber, data: u64) void {
        self.appendTag(tag, .varint);
        self.appendUint64WithoutTag(data);
    }

    /// Write unsigned 64-bit integer without tag
    pub fn appendUint64WithoutTag(self: *Writer, data: u64) void {
        self.appendVarInt(data);
    }

    // Signed varint types (zigzag encoded)
    /// Write zigzag encoded 32-bit integer with tag
    pub fn appendSint32(self: *Writer, tag: ProtoWireNumber, data: i32) void {
        self.appendTag(tag, .varint);
        self.appendSint32WithoutTag(data);
    }

    /// Write zigzag encoded 32-bit integer without tag
    pub fn appendSint32WithoutTag(self: *Writer, data: i32) void {
        self.appendSignedVarInt(@as(i64, data));
    }

    /// Write zigzag encoded 64-bit integer with tag
    pub fn appendSint64(self: *Writer, tag: ProtoWireNumber, data: i64) void {
        self.appendTag(tag, .varint);
        self.appendSint64WithoutTag(data);
    }

    /// Write zigzag encoded 64-bit integer without tag
    pub fn appendSint64WithoutTag(self: *Writer, data: i64) void {
        self.appendSignedVarInt(data);
    }

    // Fixed-width types
    /// Write fixed-width 32-bit unsigned integer with tag
    pub fn appendFixed32(self: *Writer, tag: ProtoWireNumber, data: u32) void {
        self.appendTag(tag, .fixed32);
        self.appendFixed32WithoutTag(data);
    }

    /// Write fixed-width 32-bit unsigned integer without tag
    pub fn appendFixed32WithoutTag(self: *Writer, data: u32) void {
        self.internalAppendFixed32(data);
    }

    /// Write fixed-width 64-bit unsigned integer with tag
    pub fn appendFixed64(self: *Writer, tag: ProtoWireNumber, data: u64) void {
        self.appendTag(tag, .fixed64);
        self.appendFixed64WithoutTag(data);
    }

    /// Write fixed-width 64-bit unsigned integer without tag
    pub fn appendFixed64WithoutTag(self: *Writer, data: u64) void {
        self.internalAppendFixed64(data);
    }

    /// Write fixed-width 32-bit signed integer with tag
    pub fn appendSfixed32(self: *Writer, tag: ProtoWireNumber, data: i32) void {
        self.appendTag(tag, .fixed32);
        self.appendSfixed32WithoutTag(data);
    }

    /// Write fixed-width 32-bit signed integer without tag
    pub fn appendSfixed32WithoutTag(self: *Writer, data: i32) void {
        self.internalAppendFixed32(@as(u32, @bitCast(data)));
    }

    /// Write fixed-width 64-bit signed integer with tag
    pub fn appendSfixed64(self: *Writer, tag: ProtoWireNumber, data: i64) void {
        self.appendTag(tag, .fixed64);
        self.appendSfixed64WithoutTag(data);
    }

    /// Write fixed-width 64-bit signed integer without tag
    pub fn appendSfixed64WithoutTag(self: *Writer, data: i64) void {
        self.internalAppendFixed64(@as(u64, @bitCast(data)));
    }

    // Floating point types
    /// Write 32-bit float with tag
    pub fn appendFloat32(self: *Writer, tag: ProtoWireNumber, data: f32) void {
        self.appendTag(tag, .fixed32);
        self.appendFloat32WithoutTag(data);
    }

    /// Write 32-bit float without tag
    pub fn appendFloat32WithoutTag(self: *Writer, data: f32) void {
        self.internalAppendFixed32(@as(u32, @bitCast(data)));
    }

    /// Write 64-bit float with tag
    pub fn appendFloat64(self: *Writer, tag: ProtoWireNumber, data: f64) void {
        self.appendTag(tag, .fixed64);
        self.appendFloat64WithoutTag(data);
    }

    /// Write 64-bit float without tag
    pub fn appendFloat64WithoutTag(self: *Writer, data: f64) void {
        self.internalAppendFixed64(@as(u64, @bitCast(data)));
    }

    // Internal methods
    /// Write field tag (field number and wire type)
    fn appendTag(self: *Writer, tag: ProtoWireNumber, wire_type: ProtoWireType) void {
        const tag_varint = (@as(u64, @intCast(@as(u32, @bitCast(tag)))) << 3) | @intFromEnum(wire_type);
        self.appendVarInt(tag_varint);
    }

    /// Write fixed 32-bit value in little-endian
    fn internalAppendFixed32(self: *Writer, v: u32) void {
        self.writeByte(@as(u8, @truncate(v >> 0)));
        self.writeByte(@as(u8, @truncate(v >> 8)));
        self.writeByte(@as(u8, @truncate(v >> 16)));
        self.writeByte(@as(u8, @truncate(v >> 24)));
    }

    /// Write fixed 64-bit value in little-endian
    fn internalAppendFixed64(self: *Writer, v: u64) void {
        self.writeByte(@as(u8, @truncate(v >> 0)));
        self.writeByte(@as(u8, @truncate(v >> 8)));
        self.writeByte(@as(u8, @truncate(v >> 16)));
        self.writeByte(@as(u8, @truncate(v >> 24)));
        self.writeByte(@as(u8, @truncate(v >> 32)));
        self.writeByte(@as(u8, @truncate(v >> 40)));
        self.writeByte(@as(u8, @truncate(v >> 48)));
        self.writeByte(@as(u8, @truncate(v >> 56)));
    }

    /// Write zigzag encoded signed integer
    fn appendSignedVarInt(self: *Writer, v: i64) void {
        const value = (@as(u64, @bitCast(v)) << 1) ^ @as(u64, @bitCast(v >> 63));
        self.appendVarInt(value);
    }

    /// Write varint value
    fn appendVarInt(self: *Writer, v: u64) void {
        var value = v;
        while (value >= 0x80) {
            self.writeByte(@as(u8, @truncate(value)) | 0x80);
            value >>= 7;
        }
        self.writeByte(@as(u8, @truncate(value)));
    }

    /// Write single byte to buffer
    fn writeByte(self: *Writer, byte: u8) void {
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    /// Write byte slice to buffer
    fn writeBytes(self: *Writer, bytes: []const u8) void {
        @memcpy(self.buf[self.pos..][0..bytes.len], bytes);
        self.pos += bytes.len;
    }
};

test "writer test" {
    const expect = std.testing.expect;
    const expectEqualSlices = std.testing.expectEqualSlices;

    // General tests for different types
    var buf: [100]u8 = undefined;
    var writer = Writer.init(&buf);

    // String
    writer.appendBytes(1, "hello");
    try expectEqualSlices(u8, &[_]u8{ 0x0A, 0x05, 'h', 'e', 'l', 'l', 'o' }, buf[0..7]);
    try expect(writer.pos == 7);
    writer.reset();

    // Bool
    writer.appendBool(2, true);
    writer.appendBool(3, false);
    try expectEqualSlices(u8, &[_]u8{ 0x10, 0x01, 0x18, 0x00 }, buf[0..4]);
    try expect(writer.pos == 4);
    writer.reset();

    // Int32
    writer.appendInt32(4, 150);
    try expectEqualSlices(u8, &[_]u8{ 0x20, 0x96, 0x01 }, buf[0..3]);
    try expect(writer.pos == 3);
    writer.reset();

    // Int64
    writer.appendInt64(5, 1500);
    try expectEqualSlices(u8, &[_]u8{ 0x28, 0xdc, 0x0b }, buf[0..3]);
    try expect(writer.pos == 3);
    writer.reset();

    // UInt32
    writer.appendUint32(6, 150);
    try expectEqualSlices(u8, &[_]u8{ 0x30, 0x96, 0x01 }, buf[0..3]);
    try expect(writer.pos == 3);
    writer.reset();

    // UInt64
    writer.appendUint64(7, 1500);
    try expectEqualSlices(u8, &[_]u8{ 0x38, 0xdc, 0x0b }, buf[0..3]);
    try expect(writer.pos == 3);
    writer.reset();

    // SInt32 (zigzag encoding)
    writer.appendSint32(8, -1);
    try expectEqualSlices(u8, &[_]u8{ 0x40, 0x01 }, buf[0..2]);
    try expect(writer.pos == 2);
    writer.reset();

    // SInt64 (zigzag encoding)
    writer.appendSint64(9, -1);
    try expectEqualSlices(u8, &[_]u8{ 0x48, 0x01 }, buf[0..2]);
    try expect(writer.pos == 2);
    writer.reset();

    // Fixed32
    writer.appendFixed32(10, 0x12345678);
    try expectEqualSlices(u8, &[_]u8{ 0x55, 0x78, 0x56, 0x34, 0x12 }, buf[0..5]);
    try expect(writer.pos == 5);
    writer.reset();

    // Fixed64
    writer.appendFixed64(11, 0x1234567890ABCDEF);
    try expectEqualSlices(u8, &[_]u8{ 0x59, 0xEF, 0xCD, 0xAB, 0x90, 0x78, 0x56, 0x34, 0x12 }, buf[0..9]);
    try expect(writer.pos == 9);
    writer.reset();

    // SFixed32
    writer.appendSfixed32(12, -1);
    try expectEqualSlices(u8, &[_]u8{ 0x65, 0xFF, 0xFF, 0xFF, 0xFF }, buf[0..5]);
    try expect(writer.pos == 5);
    writer.reset();

    // SFixed64
    writer.appendSfixed64(13, -1);
    try expectEqualSlices(u8, &[_]u8{ 0x69, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, buf[0..9]);
    try expect(writer.pos == 9);
    writer.reset();

    // Float32
    writer.appendFloat32(14, 3.14);
    try expectEqualSlices(u8, &[_]u8{ 0x75, 0xC3, 0xF5, 0x48, 0x40 }, buf[0..5]);
    try expect(writer.pos == 5);
    writer.reset();

    // Float64
    writer.appendFloat64(15, 3.14);
    try expectEqualSlices(u8, &[_]u8{ 0x79, 0x1F, 0x85, 0xEB, 0x51, 0xB8, 0x1E, 0x09, 0x40 }, buf[0..9]);
    try expect(writer.pos == 9);
    writer.reset();
}

test "writer append string" {
    const test_cases = .{
        .{
            .name = "empty string",
            .tag = @as(ProtoWireNumber, 1),
            .data = "",
            .want = &[_]u8{ 0x0a, 0x00 },
        },
        .{
            .name = "hello world",
            .tag = @as(ProtoWireNumber, 1),
            .data = "hello world",
            .want = &[_]u8{ 0x0a, 0x0b, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendBytes(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append int32" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, 0),
            .want = &[_]u8{ 0x08, 0x00 },
        },
        .{
            .name = "positive small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, 127),
            .want = &[_]u8{ 0x08, 0x7f },
        },
        .{
            .name = "negative small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, -127),
            .want = &[_]u8{ 0x08, 0x81, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 },
        },
        .{
            .name = "max int32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(i32),
            .want = &[_]u8{ 0x08, 0xff, 0xff, 0xff, 0xff, 0x07 },
        },
        .{
            .name = "min int32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.minInt(i32),
            .want = &[_]u8{ 0x08, 0x80, 0x80, 0x80, 0x80, 0xf8, 0xff, 0xff, 0xff, 0xff, 0x01 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendInt32(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append sint32" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, 0),
            .want = &[_]u8{ 0x08, 0x00 },
        },
        .{
            .name = "positive small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, 127),
            .want = &[_]u8{ 0x08, 0xfe, 0x01 },
        },
        .{
            .name = "negative small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, -127),
            .want = &[_]u8{ 0x08, 0xfd, 0x01 },
        },
        .{
            .name = "max int32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(i32),
            .want = &[_]u8{ 0x08, 0xfe, 0xff, 0xff, 0xff, 0x0f },
        },
        .{
            .name = "min int32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.minInt(i32),
            .want = &[_]u8{ 0x08, 0xff, 0xff, 0xff, 0xff, 0x0f },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendSint32(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append sint64" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, 0),
            .want = &[_]u8{ 0x08, 0x00 },
        },
        .{
            .name = "positive small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, 127),
            .want = &[_]u8{ 0x08, 0xfe, 0x01 },
        },
        .{
            .name = "negative small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, -127),
            .want = &[_]u8{ 0x08, 0xfd, 0x01 },
        },
        .{
            .name = "max int64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(i64),
            .want = &[_]u8{ 0x08, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 },
        },
        .{
            .name = "min int64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.minInt(i64),
            .want = &[_]u8{ 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendSint64(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append sfixed32" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, 0),
            .want = &[_]u8{ 0x0d, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "positive",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, 127),
            .want = &[_]u8{ 0x0d, 0x7f, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "negative",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i32, -127),
            .want = &[_]u8{ 0x0d, 0x81, 0xff, 0xff, 0xff },
        },
        .{
            .name = "max int32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(i32),
            .want = &[_]u8{ 0x0d, 0xff, 0xff, 0xff, 0x7f },
        },
        .{
            .name = "min int32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.minInt(i32),
            .want = &[_]u8{ 0x0d, 0x00, 0x00, 0x00, 0x80 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendSfixed32(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append sfixed64" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, 0),
            .want = &[_]u8{ 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "positive",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, 127),
            .want = &[_]u8{ 0x09, 0x7f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "negative",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, -127),
            .want = &[_]u8{ 0x09, 0x81, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        },
        .{
            .name = "max int64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(i64),
            .want = &[_]u8{ 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f },
        },
        .{
            .name = "min int64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.minInt(i64),
            .want = &[_]u8{ 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendSfixed64(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append int64" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, 0),
            .want = &[_]u8{ 0x08, 0x00 },
        },
        .{
            .name = "positive small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, 127),
            .want = &[_]u8{ 0x08, 0x7f },
        },
        .{
            .name = "negative small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(i64, -127),
            .want = &[_]u8{ 0x08, 0x81, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 },
        },
        .{
            .name = "max int64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(i64),
            .want = &[_]u8{ 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f },
        },
        .{
            .name = "min int64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.minInt(i64),
            .want = &[_]u8{ 0x08, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendInt64(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append float32" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(f32, 0.0),
            .want = &[_]u8{ 0x0d, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "positive small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(f32, 3.14),
            .want = &[_]u8{ 0x0d, 0xc3, 0xf5, 0x48, 0x40 },
        },
        .{
            .name = "negative small",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(f32, -3.14),
            .want = &[_]u8{ 0x0d, 0xc3, 0xf5, 0x48, 0xc0 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendFloat32(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append float64" {
    const test_cases = .{ .{
        .name = "zero",
        .tag = @as(ProtoWireNumber, 1),
        .data = @as(f64, 0.0),
        .want = &[_]u8{ 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
    }, .{
        .name = "positive small",
        .tag = @as(ProtoWireNumber, 1),
        .data = @as(f64, 3.14159265359),
        .want = &[_]u8{ 0x09, 0xea, 0x2e, 0x44, 0x54, 0xfb, 0x21, 0x09, 0x40 },
    }, .{
        .name = "negative small",
        .tag = @as(ProtoWireNumber, 1),
        .data = @as(f64, -3.14159265359),
        .want = &[_]u8{ 0x09, 0xea, 0x2e, 0x44, 0x54, 0xfb, 0x21, 0x09, 0xc0 },
    } };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendFloat64(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append bool" {
    const test_cases = .{
        .{
            .name = "true",
            .tag = @as(ProtoWireNumber, 1),
            .data = true,
            .want = &[_]u8{ 0x08, 0x01 },
        },
        .{
            .name = "false",
            .tag = @as(ProtoWireNumber, 1),
            .data = false,
            .want = &[_]u8{ 0x08, 0x00 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendBool(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append fixed32" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u32, 0),
            .want = &[_]u8{ 0x0d, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "small value",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u32, 127),
            .want = &[_]u8{ 0x0d, 0x7f, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "max uint32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(u32),
            .want = &[_]u8{ 0x0d, 0xff, 0xff, 0xff, 0xff },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendFixed32(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append fixed64" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u64, 0),
            .want = &[_]u8{ 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "small value",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u64, 127),
            .want = &[_]u8{ 0x09, 0x7f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        },
        .{
            .name = "max uint64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(u64),
            .want = &[_]u8{ 0x09, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendFixed64(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append uint32" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u32, 0),
            .want = &[_]u8{ 0x08, 0x00 },
        },
        .{
            .name = "small value",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u32, 127),
            .want = &[_]u8{ 0x08, 0x7f },
        },
        .{
            .name = "max uint32",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(u32),
            .want = &[_]u8{ 0x08, 0xff, 0xff, 0xff, 0xff, 0x0f },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendUint32(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}

test "writer append uint64" {
    const test_cases = .{
        .{
            .name = "zero",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u64, 0),
            .want = &[_]u8{ 0x08, 0x00 },
        },
        .{
            .name = "small value",
            .tag = @as(ProtoWireNumber, 1),
            .data = @as(u64, 127),
            .want = &[_]u8{ 0x08, 0x7f },
        },
        .{
            .name = "max uint64",
            .tag = @as(ProtoWireNumber, 1),
            .data = std.math.maxInt(u64),
            .want = &[_]u8{ 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 },
        },
    };

    var buf: [64]u8 = undefined;
    inline for (test_cases) |tc| {
        var writer = Writer.init(&buf);
        writer.appendUint64(tc.tag, tc.data);
        try std.testing.expectEqualSlices(u8, tc.want, buf[0..writer.pos]);
    }
}
