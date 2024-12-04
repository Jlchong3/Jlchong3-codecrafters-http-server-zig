const std = @import("std");
const net = std.net;
const posix = std.posix;
const HttpRequest = @import("http_request.zig").HttpRequest;

const ok = "HTTP/1.1 200 OK";
const notFound = "HTTP/1.1 404 Not Found";

fn send_response(allocator: std.mem.Allocator, fd: i32,
                status: []const u8, headers: ?[]const u8, body: ?[]const u8) !void{

    const response = try std.fmt.allocPrint(allocator, "{s}\r\n{s}\r\n{s}", .{status, headers orelse "", body orelse ""});
    defer allocator.free(response);
    _ = try posix.write(fd, response);
}

const RootHandler = struct {
    route: []const u8 = "/",
    allocator: std.mem.Allocator,
    fd: i32,

    const handlerRoute = "/";

    pub fn handle(self: RootHandler, request: *HttpRequest) !void {
        _ = request;
        try send_response(self.allocator, self.fd, ok, null, null);
    }

    pub fn matches(self: RootHandler, request: *HttpRequest) bool {
        return std.mem.eql(u8, request.route, self.route);
    }
};

const EchoHandler = struct {
    route: []const u8 = "/echo",
    allocator: std.mem.Allocator,
    fd: i32,

    pub fn handle(self: EchoHandler, request: *HttpRequest) !void {
        const response_body = request.route[6..];
        const header = try std.fmt.allocPrint(self.allocator, "Content-Type: text/plain\r\nContent-Length:{d}\r\n", .{response_body.len});
        try send_response(self.allocator, self.fd, ok, header, response_body);
    }

    pub fn matches(self: EchoHandler, request: *HttpRequest) bool {
        return std.mem.startsWith(u8, request.route, self.route);
    }
};

const UserAgentHandler = struct {
    route: []const u8 = "/user-agent",
    allocator: std.mem.Allocator,
    fd: i32,


    pub fn handle(self: UserAgentHandler, request: *HttpRequest) !void {
        const body = request.headers.get("User-Agent").?;
        const header = try std.fmt.allocPrint(self.allocator, "Content-Type: text/plain\r\nContent-Length:{d}\r\n", .{body.len});
        try send_response(self.allocator, self.fd, ok, header, body);
    }

    pub fn matches(self: UserAgentHandler, request: *HttpRequest) bool {
        return std.mem.startsWith(u8, request.route, self.route);
    }
};

const NotFoundHandler= struct {
    route: []const u8 = undefined,
    allocator: std.mem.Allocator,
    fd: i32,

    pub fn handle(self: NotFoundHandler, request: *HttpRequest) !void{
        _ = request;
        try send_response(self.allocator, self.fd, notFound, null, null);
    }
    fn matches(self: NotFoundHandler, request: *HttpRequest) bool {
        _ = self;
        _ = request;
        return false;
    }
};

pub const RouteHandler = union(enum) {
    root: RootHandler,
    echo: EchoHandler,
    userAgent: UserAgentHandler,
    notFound: NotFoundHandler,

    pub fn handle(self: RouteHandler, request: *HttpRequest) !void {
        switch (self) {
            inline else => |h| try h.handle(request),
        }
    }

    pub fn matches(self: RouteHandler, request: *HttpRequest) bool {
        switch (self) {
            inline else => |h| return h.matches(request),
        }
    }

    pub fn getHandler(request: *HttpRequest, allocator: std.mem.Allocator, fd: i32 ) RouteHandler {
        const handlers = [_]RouteHandler{
            RouteHandler{ .root = RootHandler{ .allocator = allocator, .fd = fd } },
            RouteHandler{ .echo = EchoHandler{ .allocator = allocator, .fd = fd } },
            RouteHandler{ .userAgent = UserAgentHandler{ .allocator = allocator, .fd = fd } },
        };

        for (handlers) |h| {
            if (h.matches(request)){
                return h;
            }
        }

        return RouteHandler{ .notFound = NotFoundHandler{ .allocator = allocator, .fd = fd }};
    }
};
