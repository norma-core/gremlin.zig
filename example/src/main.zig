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
// Created by ab, 14.11.2024

const std = @import("std");
const pb = @import("gen/example.proto.zig");

pub fn main() !void {
    const user = pb.User{
        .id = 1,
        .name = "Alice",
    };

    const allocator = std.heap.page_allocator;
    const encoded = try user.encode(allocator);
    defer allocator.free(encoded);

    const decoded = try pb.UserReader.init(encoded);
    std.debug.print("Decoded user: {d}\n", .{decoded.getId()});
}
