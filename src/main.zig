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
        .reuse_port = true,
    });
    defer listener.deinit();

    const listener_fd = listener.stream.handle;

    const epfd = posix.epoll_create1(0) catch {
        std.debug.print("Unable to create epoll", .{});
        std.process.exit(0);
    };
    defer posix.close(epfd);

    var ev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET, .data = .{ .fd = listener_fd }};
    try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, listener_fd, &ev);

    const page_allocator = std.heap.page_allocator;
    const allocator: std.heap.ThreadSafeAllocator = .{ .child_allocator = page_allocator };
    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{
        .allocator = allocator.child_allocator,
        .n_jobs = 4,
    });
    defer pool.deinit();

    try pool.spawn(handleConnection, .{epfd, &listener});

    handleConnection(epfd, &listener);
}

fn handleConnection(epfd: i32, listener: *net.Server) void {
    var ready_list: [64]linux.epoll_event = undefined;

    while (true) {
        const ready_count = posix.epoll_wait(epfd, &ready_list, -1);
        if (ready_count <= 0) {
            std.debug.print("Error in epoll_wait\n", .{});
            continue;
        }

        for (ready_list[0..ready_count]) |ready| {
            const ready_fd = ready.data.fd;
            if (ready_fd == listener.stream.handle) {

                epollAddListener(epfd, listener);

            } else {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                var a_allocator = arena.allocator();

                handleResquest(&a_allocator, ready_fd);

                if (ready.events & linux.EPOLL.RDHUP == linux.EPOLL.RDHUP) {
                    posix.close(ready_fd);
                }
            }
        }
    }
}

fn epollAddListener(epfd: i32, listener: *net.Server) void {
    while(true){
        const conn = listener.accept() catch {
            break;
        };

        var client_ev = linux.epoll_event{ .events = linux.EPOLL.IN | linux.EPOLL.ET | linux.EPOLL.ONESHOT, .data = .{ .fd = conn.stream.handle }};
        posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, conn.stream.handle, &client_ev) catch {
            std.debug.print("Failed registering\n", .{});
        };
    }
}

fn handleResquest(allocator: *std.mem.Allocator, ready_fd: i32) void {
    const request = allocator.alloc(u8, 1024) catch {
        std.debug.print("Not enough memory\n", .{});
        return;
    };
    defer allocator.free(request);
    const read = posix.read(ready_fd, request) catch 0;
    if (read == 0) {
        posix.close(ready_fd);
        return;
    }

    var bench = std.time.Timer.start() catch {
        return;
    };
    var httpRequest = HttpRequest.init(allocator.*);
    defer httpRequest.deinit();

    httpRequest.parseRequest(request) catch {
        std.debug.print("Failed Parsing\n", .{});
        return;
    };

    var handler = RouteHandler.getHandler(&httpRequest, allocator, ready_fd);
    handler.handle(&httpRequest) catch {
        std.debug.print("Failed Handle\n", .{});
        return;
    };
    std.debug.print("{d} ns\n", .{bench.lap()});
}
