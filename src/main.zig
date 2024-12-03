const std = @import("std");
const net = std.net;
const os = std.os;
const HttpRequest = @import("http_request.zig").HttpRequest;
const RouteHandler = @import("handlers.zig").RouteHandler;

fn sigchldHandler(sig: i32) callconv (.c) void {
    _ = sig;
    var status: u32 = 0;
    _ = std.os.linux.waitpid(-1, &status, std.posix.W.NOHANG);
}

fn sigintHandler(sig: i32) callconv (.c) void {
    _ = sig;
    std.debug.print("bye\n", .{});
    std.process.exit(0);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    const actchld = os.linux.Sigaction {
        .handler = .{ .handler = sigchldHandler },
        .mask = os.linux.empty_sigset,
        .flags = 0,
    };

    const actint = os.linux.Sigaction {
        .handler = .{ .handler = sigintHandler },
        .mask = os.linux.empty_sigset,
        .flags = 0,
    };

    _ = os.linux.sigaction(os.linux.SIG.CHLD, &actchld, null);
    _ = os.linux.sigaction(os.linux.SIG.INT, &actint, null);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        var conn = try listener.accept();
        defer conn.stream.close();

        const pid: std.posix.pid_t = std.posix.fork() catch {
            std.debug.print("Failed to create child", .{});
            std.process.exit(1);
        };

        if(pid == 0) {
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
            std.process.exit(0);
        }
     }
}

