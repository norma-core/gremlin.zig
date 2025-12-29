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
// Created by ab, 10.06.2024

const std = @import("std");
const ParserBuffer = @import("buffer.zig").ParserBuffer;
const Error = @import("errors.zig").Error;

/// Represents a service definition in a protobuf file.
/// A service definition contains RPC method definitions.
/// Format:
/// ```protobuf
/// service Greeter {
///     rpc SayHello (HelloRequest) returns (HelloResponse);
///     rpc SayGoodbye (GoodbyeRequest) returns (GoodbyeResponse);
/// }
/// ```
pub const Service = struct {
    /// Attempts to parse a service definition from the given buffer.
    /// Returns null if the buffer doesn't start with a service definition.
    /// Returns error for malformed service definitions.
    ///
    /// The parser currently skips the entire service body, counting braces
    /// to ensure proper nesting. Future versions should parse the RPC methods.
    ///
    /// Errors:
    /// - Error.UnexpectedEOF: Buffer ends before service definition is complete
    /// - Error.InvalidCharacter: Unexpected character in service definition
    pub fn parse(buf: *ParserBuffer) Error!?Service {
        try buf.skipSpaces();

        if (!buf.checkStrWithSpaceAndShift("service")) {
            return null;
        }

        // Count opening and closing braces to handle nested blocks
        var brace_count: usize = 0;
        while (true) {
            const c = try buf.shouldShiftNext();
            switch (c) {
                '{' => {
                    brace_count += 1;
                },
                '}' => {
                    if (brace_count == 0) {
                        return Error.UnexpectedEOF;
                    }
                    brace_count -= 1;
                    if (brace_count == 0) {
                        break;
                    }
                },
                else => {},
            }
        }

        return Service{};
    }
};

test "service parsing" {
    // Test case 1: Not a service definition
    {
        var buf = ParserBuffer{ .buf = "message Test {}" };
        try std.testing.expectEqual(null, try Service.parse(&buf));
    }

    // Test case 2: Simple empty service
    {
        var buf = ParserBuffer{ .buf = "service Test {}" };
        const result = try Service.parse(&buf);
        try std.testing.expect(result != null);
    }

    // Test case 3: Service with nested braces
    {
        var buf = ParserBuffer{ .buf = 
            \\service Test {
            \\    rpc Method1 (Request) { option deprecated = true; }
            \\    rpc Method2 (Request) returns (Response) { option idempotency_level = "NO_SIDE_EFFECTS"; }
            \\}
        };
        const result = try Service.parse(&buf);
        try std.testing.expect(result != null);
    }

    // Test case 4: Invalid brace matching
    {
        var buf = ParserBuffer{ .buf = "service Test {{}" };
        try std.testing.expectError(Error.UnexpectedEOF, Service.parse(&buf));
    }

    // Test case 5: Unexpected EOF
    {
        var buf = ParserBuffer{ .buf = "service Test {" };
        try std.testing.expectError(Error.UnexpectedEOF, Service.parse(&buf));
    }
}
