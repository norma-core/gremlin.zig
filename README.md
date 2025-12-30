# gremlin

A zero-dependency, zero-allocation Google Protocol Buffers implementation in pure Zig (no protoc required)

## Installation & Setup

Single command setup:
```bash
zig fetch --save https://github.com/norma-core/gremlin.zig/archive/refs/heads/zig-0.15.zip
```

This command will:
1. Download gremlin
2. Add it to your `build.zig.zon`
3. Generate the correct dependency hash

In your `build.zig`:
```zig
const std = @import("std");
const ProtoGenStep = @import("gremlin").ProtoGenStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the gremlin dependency
    const gremlin_dep = b.dependency("gremlin", .{
        .target = target,
        .optimize = optimize,
    });

    // Get the gremlin module for imports
    const gremlin_module = gremlin_dep.module("gremlin");

    // Generate Zig code from .proto files
    // This will process all .proto files in the proto/ directory
    // and output generated Zig code to src/gen/
    const protobuf = ProtoGenStep.create(
        b,
        .{
            .name = "protobuf",                  // Name for the build step
            .proto_sources = b.path("proto"),    // Directory containing .proto files
            .target = b.path("src/gen"),         // Output directory for generated Zig code
        },
    );

    // Create binary
    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add the gremlin module
    exe.root_module.addImport("gremlin", gremlin_module);
    exe.step.dependOn(&protobuf.step);

    b.installArtifact(exe);
}
```

## Features

- Zero dependencies
- Pure Zig implementation (no protoc required)
- Compatible with Protocol Buffers version 2 and 3
- Simple integration with Zig build system
- Single allocation for serialization (including complex recursive messages)
- Zero-allocation readers with lazy parsing - parses only required complex fields
- Tested with Zig 0.15.2

## Generated code

See the complete working example in the [`example`](./example) folder.

Given a protobuf definition:
```protobuf
syntax = "proto3";

message User {
  string name = 1;
  uint64 id   = 2;
  repeated string tags = 10;
}
```

Gremlin will generate equivalent Zig code (see [example.proto.zig](./example/src/gen/example.proto.zig)):
```zig
const std = @import("std");
const gremlin = @import("gremlin");

// Wire numbers for fields
const UserWire = struct {
    const NAME_WIRE: gremlin.ProtoWireNumber = 1;
    const ID_WIRE: gremlin.ProtoWireNumber = 2;
    const TAGS_WIRE: gremlin.ProtoWireNumber = 10;
};

// Message struct
pub const User = struct {
    name: ?[]const u8 = null,
    id: u64 = 0,
    tags: ?[]const ?[]const u8 = null,
    
    // Calculate size for allocation
    pub fn calcProtobufSize(self: *const User) usize { ... }
    
    // Encode to new buffer
    pub fn encode(self: *const User, allocator: std.mem.Allocator) gremlin.Error![]const u8 { ... }
    
    // Encode to existing buffer
    pub fn encodeTo(self: *const User, target: *gremlin.Writer) void { ... }
};

// Reader for lazy parsing (zero allocations)
pub const UserReader = struct {
    buf: gremlin.Reader,
    _name: ?[]const u8 = null,
    _id: u64 = 0,
    ...

    pub fn init(src: []const u8) gremlin.Error!UserReader { ... }
    
    // Accessor methods
    pub inline fn getName(self: *const UserReader) []const u8 { ... }
    pub inline fn getId(self: *const UserReader) u64 { ... }
    
};
```

## Usage Example

```zig
const std = @import("std");
const proto = @import("gen/example.proto.zig");

pub fn main() !void {
    // Encoding
    const user = proto.User{
        .name = "Alice",
        .id = 12345,
        .tags = &[_]?[]const u8{ "admin", "verified" },
    };
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const encoded = try user.encode(allocator);
    defer allocator.free(encoded);
    
    // Decoding with zero-allocation reader
    var reader = try proto.UserReader.init(encoded);
    
    std.debug.print("Name: {s}\n", .{reader.getName()});
    std.debug.print("ID: {}\n", .{reader.getId()});
    
    // Iterate over repeated fields
    while (reader.tagsNext()) |tag| {
        std.debug.print("Tag: {s}\n", .{tag});
    }
}
```

### Reader API for Repeated Fields

The generated readers provide `next()` methods for iterating over repeated fields without allocations:

```zig
// For repeated string field 'tags'
pub fn tagsNext(self: *UserReader) ?[]const u8 {
    // Returns next value or null when done
}

// For repeated scalar fields (e.g., repeated int32 values)
pub fn valuesNext(self: *UserReader) gremlin.Error!?i32 {
    // Returns next value or null when done
}

// For repeated message fields
pub fn messagesNext(self: *UserReader) ?MessageReader {
    // Returns next message reader or null when done
}

// Optional: get count of repeated items
pub fn tagsCount(self: *const UserReader) usize {
    // Returns total count
}
```

This pattern applies to all repeated field types:
- Repeated scalars: `fieldNameNext()` returns `gremlin.Error!?T` where T is the scalar type
- Repeated messages: `fieldNameNext()` returns `?MessageReader`
- Repeated strings/bytes: `fieldNameNext()` returns `?[]const u8`

The readers maintain internal state for iteration, so you can call `next()` repeatedly to traverse all values. No allocations are required as the readers work directly with the underlying protobuf buffer.