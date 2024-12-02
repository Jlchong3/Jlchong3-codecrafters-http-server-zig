const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const conn = try listener.accept();
    defer conn.stream.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a_allocator = arena.allocator();

    const request = try a_allocator.alloc(u8, 1024);

    _ = try conn.stream.read(request);

    var it = std.mem.splitScalar(u8, request, ' ');

    _ = it.next();

    var route = it.peek().?;

    if (std.mem.eql(u8, route, "/")){
        try conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else if (std.mem.eql(u8, route[0..6], "/echo/")){
        const str = route[6..];
        const response = try std.fmt.allocPrint(a_allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConten-Length:{d}\r\n\r\n{s}", .{str.len, str});
        try conn.stream.writeAll(response);
    } else {
        try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }

}

