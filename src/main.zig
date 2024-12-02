const std = @import("std");
const net = std.net;

fn send_response(allocator: *std.mem.Allocator, stream: *net.Stream,
                status: []const u8, headers: ?[]const u8, body: ?[]const u8) !void{

    const response = try std.fmt.allocPrint(allocator.*, "{s}\r\n{s}\r\n{s}", .{status, headers orelse "", body orelse ""});
    try stream.writeAll(response);
}

const HttpRequest = struct {
    method: []const u8,
    route: []const u8,
    protocol_version: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator) HttpRequest {
        return .{
            .method = undefined,
            .route = undefined,
            .protocol_version = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator.*),
            .body = undefined,
            .allocator = allocator,
        };
    }

    pub fn parseRequest(self: *HttpRequest, request: []const u8) !void {
        var it = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = it.next().?;

        var it_request_line = std.mem.splitScalar(u8, request_line, ' ');

        self.method = it_request_line.next().?;
        self.route = it_request_line.next().?;
        self.protocol_version = it_request_line.next().?;

        while(!std.mem.eql(u8, it.peek().?, "")){
            var line = it.next().?;
            const colon_pos = std.mem.indexOf(u8, line, ":");
            if (colon_pos) |ind| {
                const key = line[0..ind];
                const value = line[ind + 1..];

                const trimmed_key = std.mem.trim(u8, key, " ");
                const trimmed_value = std.mem.trim(u8, value, " ");

                _ = try self.headers.put(trimmed_key, trimmed_value);
            }
        }

        _ = it.next();
        self.body = it.next();
    }
};

const RootHandler = struct {
    route: []const u8 = "/",
    allocator: *std.mem.Allocator,
    conn: *net.Server.Connection,

    const handlerRoute = "/";

    pub fn handle(self: RootHandler, request: *HttpRequest) !void {
        _ = request;
        try send_response(self.allocator, &self.conn.stream, "HTTP/1.1 200 OK", null, null);
    }

    pub fn matches(self: RootHandler, request: *HttpRequest) bool {
        return std.mem.eql(u8, request.route, self.route);
    }
};

const EchoHandler = struct {
    route: []const u8 = "/echo",
    allocator: *std.mem.Allocator,
    conn: *net.Server.Connection,

    pub fn handle(self: EchoHandler, request: *HttpRequest) !void {
        const response_body = request.route[6..];
        const header = try std.fmt.allocPrint(self.allocator.*, "Content-Type: text/plain\r\nContent-Length:{d}\r\n", .{response_body.len});
        try send_response(self.allocator, &self.conn.stream, "HTTP/1.1 200 OK", header, response_body);
    }

    pub fn matches(self: EchoHandler, request: *HttpRequest) bool {
        return std.mem.startsWith(u8, request.route, self.route);
    }
};

const UserAgentHandler = struct {
    route: []const u8 = "/user-agent",
    allocator: *std.mem.Allocator,
    conn: *net.Server.Connection,


    pub fn handle(self: UserAgentHandler, request: *HttpRequest) !void {
        const body = request.headers.get("User-Agent").?;
        const header = try std.fmt.allocPrint(self.allocator.*, "Content-Type: text/plain\r\nContent-Length:{d}\r\n", .{body.len});
        try send_response(self.allocator, &self.conn.stream, "HTTP/1.1 200 OK", header, body);
    }

    pub fn matches(self: UserAgentHandler, request: *HttpRequest) bool {
        return std.mem.startsWith(u8, request.route, self.route);
    }
};

const routeHandler = union(enum) {
    root: RootHandler,
    echo: EchoHandler,
    userAgent: UserAgentHandler,

    pub fn handle(self: routeHandler, request: *HttpRequest) !void {
        switch (self) {
            inline else => |h| try h.handle(request),
        }
    }

    pub fn matches(self: routeHandler, request: *HttpRequest) bool {
        switch (self) {
            inline else => |h| return h.matches(request),
        }
    }

    pub fn getHandler(request: *HttpRequest, allocator: *std.mem.Allocator, conn: *net.Server.Connection) ?routeHandler {
        const handlers = [_]routeHandler{
            routeHandler{ .root = RootHandler{ .allocator = allocator, .conn = conn } },
            routeHandler{ .echo = EchoHandler{ .allocator = allocator, .conn = conn } },
            routeHandler{ .userAgent = UserAgentHandler{ .allocator = allocator, .conn = conn } },
        };

        for (handlers) |h| {
            if (h.matches(request)){
                return h;
            }
        }

        return null;
    }
};

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

    var handler: ?routeHandler = undefined;
    handler = routeHandler.getHandler(&httpRequest, &a_allocator, &conn);

    if (handler) |h| {
        try h.handle(&httpRequest);
    } else {
        try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}

