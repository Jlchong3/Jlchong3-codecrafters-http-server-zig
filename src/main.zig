const std = @import("std");
const net = std.net;
const linux = std.os.linux;
const posix = std.posix;
const HttpRequest = @import("http_request.zig").HttpRequest;
const RouteHandler = @import("handlers.zig").RouteHandler;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{
        .reuse_address = true,
        .force_nonblocking = true,
    });
    defer listener.deinit();

    const listener_fd = listener.stream.handle;

    const epfd = posix.epoll_create1(0) catch {
        std.debug.print("Unable to create epoll", .{});
        std.process.exit(0);
    };
    defer posix.close(epfd);

    var ev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = listener_fd }};
    try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, listener_fd, &ev);

    var ready_list: [128]linux.epoll_event = undefined;

    while(true){
        const ready_count = posix.epoll_wait(epfd, &ready_list, -1);
        for(ready_list[0..ready_count]) |ready| {
            const ready_fd = ready.data.fd;
            if (ready_fd == listener_fd) {
                var conn = try listener.accept();
                errdefer conn.stream.close();
                var client_ev = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = conn.stream.handle }};
                try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, conn.stream.handle, &client_ev);

            }else {
                var closed = false;
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                var a_allocator = arena.allocator();

                const request = try a_allocator.alloc(u8, 1024);

                const read = posix.read(ready_fd, request) catch 0;
                if (read == 0) {
                    closed = true;
                }
                else {
                    var httpRequest = HttpRequest.init(&a_allocator);
                    try httpRequest.parseRequest(request);

                    var handler: RouteHandler = undefined;
                    handler = RouteHandler.getHandler(&httpRequest, &a_allocator, ready_fd);

                    try handler.handle(&httpRequest);
                }

                if (closed or ready.events & linux.EPOLL.RDHUP == linux.EPOLL.RDHUP) {
                    posix.close(ready_fd);
                }

            }

        }
    }
}

