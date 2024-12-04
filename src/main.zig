const std = @import("std");
const net = std.net;
const linux = std.os.linux;
const posix = std.posix;
const HttpRequest = @import("http_request.zig").HttpRequest;
const RouteHandler = @import("handlers.zig").RouteHandler;

const Client = struct {
    socket: posix.socket_t,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const page_alloc = std.heap.page_allocator;
    var allocator: std.heap.ThreadSafeAllocator = .{.child_allocator = page_alloc};

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{
        .allocator = allocator.child_allocator,
        .n_jobs = 16,
    });
    defer pool.deinit();


    const listener_fd = listener.stream.handle;
    _ = try posix.fcntl(listener_fd, posix.F.SETFL, posix.SOCK.NONBLOCK);

    const epfd = posix.epoll_create1(0) catch {
        std.debug.print("Unable to create epoll", .{});
        std.process.exit(0);
    };
    defer posix.close(epfd);

    var ev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .ptr = 0 }};
    try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, listener_fd, &ev);

    var ready_list: [128]linux.epoll_event = undefined;

    while(true){
        const ready_count = posix.epoll_wait(epfd, &ready_list, -1);
        for(ready_list[0..ready_count]) |ready| {
            try pool.spawn(handleConnection, .{stdout, epfd, ready, allocator.allocator(), &listener});
        }
    }
}

fn handleConnection(log: std.fs.File.Writer, epfd: i32, event: linux.epoll_event, allocator: std.mem.Allocator, listener: *net.Server) void {
    switch(event.data.ptr){
        0 => {
            const conn = listener.accept() catch {
                std.debug.print("Error connection\n", .{});
                std.process.exit(1);
            };
            errdefer conn.stream.close();

            const client = allocator.create(Client) catch {
                std.debug.print("Failed allocation", .{});
                std.process.exit(1);
            };
            errdefer allocator.destroy(client);

            client.* = .{.socket = conn.stream.handle};

            log.print("client connected {any}\n", .{conn.stream.handle}) catch handleError(client);

            var client_ev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .ptr  = @intFromPtr(client) }};
            posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, conn.stream.handle, &client_ev) catch handleError(client);
        },
        else => |ptr| {
            var closed = false;

            const client: *Client = @ptrFromInt(ptr);

            const request = allocator.alloc(u8, 1024) catch {
                std.debug.print("Failed allocation", .{});
                std.process.exit(1);
            };

            const read = posix.read(client.socket, request) catch 0;
            if (read == 0) {
                closed = true;
            }
            else {
                var httpRequest = HttpRequest.init(allocator);
                defer httpRequest.deinit();
                httpRequest.parseRequest(request) catch handleError(client);

                var handler: RouteHandler = undefined;
                handler = RouteHandler.getHandler(&httpRequest, allocator, client.socket);
                log.print("Sent response to {any}\n", .{client.socket}) catch handleError(client);

                handler.handle(&httpRequest) catch handleError(client);
            }

            if (closed or (event.events & linux.EPOLL.RDHUP) == linux.EPOLL.RDHUP) {
                posix.close(client.socket);
            }

        }
    }
}

fn handleError(client: *Client) void {
    _ = posix.write(client.socket, "HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
}
