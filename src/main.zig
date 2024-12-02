const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try stdout.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
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

    if (std.mem.eql(u8, it.peek().?, "/")){
        try success(conn);
    } else {
        try not_found(conn);
    }

}

pub fn success(conn: net.Server.Connection) !void {
    try conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
}

pub fn not_found(conn: net.Server.Connection) !void {
    try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
}
