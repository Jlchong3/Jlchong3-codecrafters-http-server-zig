const std = @import("std");
const net = std.net;
const HttpRequest = @import("http_request.zig").HttpRequest;
const RouteHandler = @import("handlers.zig").RouteHandler;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var conn = try listener.accept();
    defer conn.stream.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var a_allocator = arena.allocator();

    const request = try a_allocator.alloc(u8, 1024);

    _ = try conn.stream.read(request);

    var httpRequest = HttpRequest.init(&a_allocator);
    try httpRequest.parseRequest(request);

    var handler: RouteHandler = undefined;
    handler = RouteHandler.getHandler(&httpRequest, &a_allocator, &conn);

    try handler.handle(&httpRequest);
}

