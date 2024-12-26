const std = @import("std");
const net = std.net;
const posix = std.posix;
const mem = std.mem;
const HttpRequest = @import("http_request.zig").HttpRequest;
const Method = @import("http_request.zig").Method;

const ok = "HTTP/1.1 200 OK";
const notFound = "HTTP/1.1 404 Not Found";
const created = "HTTP/1.1 201 Created";
const allowed_encondings = [_][]const u8{ "gzip", "zip" };

fn send_response(allocator: *mem.Allocator, fd: i32,
                status: []const u8, headers: ?[]const u8, body: ?[]const u8) !void{

    const response = try std.fmt.allocPrint(allocator.*, "{s}\r\n{s}\r\n{s}", .{status, headers orelse "", body orelse ""});
    defer allocator.free(response);
    _ = try posix.write(fd, response);
}

fn createHeader(allocator: *mem.Allocator, content_type: []const u8, content_len: usize, request: *HttpRequest) []u8 {
    if(request.headers.get("Accept-Encoding") == null){
        const header = try std.fmt.allocPrint(allocator.*, "Content-Type: {s}\r\nContent-Length:{d}\r\n", .{content_type, content_len});
        return header;
    }

    const encodings = request.headers.get("Accept-Encoding");
    for (allowed_encondings) |encoding| {
        if(mem.containsAtLeast(u8, encodings, 1, encoding)){
            const header = try std.fmt.allocPrint(allocator.*, "Content-Type: {s}\r\nContent-Length:{d}\r\nContent-Encoding\r\n", .{content_type, content_len, encoding});
            return header;
        }
    }
}

const RootHandler = struct {
    const Self = @This();

    route: []const u8 = "/",
    allocator: *mem.Allocator,
    fd: i32,

    pub fn handle(self: Self, request: *HttpRequest) !void {
        _ = request;
        try send_response(self.allocator, self.fd, ok, null, null);
    }

    pub fn matches(self: Self, request: *HttpRequest) bool {
        return mem.eql(u8, request.route, self.route);
    }
};

const FileHandler = struct {
    const Self = @This();

    route: []const u8 = "/files",
    allocator: *mem.Allocator,
    fd: i32,

    pub fn handle(self: Self, request: *HttpRequest) !void {
        switch (request.method){
            .GET => {
                try getMethodHandler(self, request);
            },
            .POST => {
                try postMethodHandler(self, request);
            },
            else => {
                try send_response(self.allocator, self.fd, notFound, null, null);
            }
        }
    }

    fn getMethodHandler(self: Self, request: *HttpRequest) !void {
        const filename = request.route[7..];
        var args = try std.process.argsWithAllocator(self.allocator.*);
        defer args.deinit();
        var dirname: []u8 = undefined;
        while (args.next()) |arg| {
            if (mem.eql(u8, arg, "--directory")) {
                dirname = @constCast(mem.trimRight(u8, args.next().?, "/"));
                break;
            }
        } else {
            try send_response(self.allocator, self.fd, notFound, null, null);
            return;
        }
        const path = try std.fmt.allocPrint(self.allocator.*, "{s}/{s}", .{dirname, filename});
        defer self.allocator.free(path);
        var file = std.fs.cwd().openFile(path, .{}) catch {
            try send_response(self.allocator, self.fd, notFound, null, null);
            return;
        };
        defer file.close();
        const stat = try file.stat();
        const headers = try std.fmt.allocPrint(self.allocator.*, "Content-Type: application/octet-stream\r\nContent-Length:{d}\r\n", .{stat.size});
        defer self.allocator.free(headers);
        const buffer = try self.allocator.alloc(u8, stat.size);
        _ = try file.readAll(buffer);
        try send_response(self.allocator, self.fd, ok, headers, buffer);
    }

    fn postMethodHandler(self: Self, request: *HttpRequest) !void {
        var args = try std.process.argsWithAllocator(self.allocator.*);
        defer args.deinit();
        var dirname: []u8 = undefined;
        while (args.next()) |arg| {
            if (mem.eql(u8, arg, "--directory")) {
                dirname = @constCast(mem.trimRight(u8, args.next().?, "/"));
                break;
            }
        } else {
            try send_response(self.allocator, self.fd, notFound, null, null);
            return;
        }
        var dir = try std.fs.openDirAbsolute(dirname, .{});
        defer dir.close();
        const filename = request.route[7..];
        var file = try dir.createFile(filename, .{});
        defer file.close();

        const size = try std.fmt.parseInt(usize, request.headers.get("Content-Length").?, 10);

        var content: []const u8 = undefined;
        if(request.body) |b| {
            content = b[0..size];
        } else {
            content = "";
        }

        _ = try file.write(content);
        try send_response(self.allocator, self.fd, created, null, null);
    }

    pub fn matches(self: Self, request: *HttpRequest) bool {
        return mem.startsWith(u8, request.route, self.route);
    }
};

const EchoHandler = struct {
    const Self = @This();

    route: []const u8 = "/echo",
    allocator: *mem.Allocator,
    fd: i32,

    pub fn handle(self: Self, request: *HttpRequest) !void {
        const response_body = request.route[6..];
        const header = createHeader(self.allocator, "text/plain", response_body.len, request);
        defer self.allocator.free(header);
        try send_response(self.allocator, self.fd, ok, header, response_body);
    }

    pub fn matches(self: Self, request: *HttpRequest) bool {
        return mem.startsWith(u8, request.route, self.route);
    }
};

const UserAgentHandler = struct {
    const Self = @This();

    route: []const u8 = "/user-agent",
    allocator: *mem.Allocator,
    fd: i32,


    pub fn handle(self: Self, request: *HttpRequest) !void {
        const body = request.headers.get("User-Agent").?;
        const header = try std.fmt.allocPrint(self.allocator.*, "Content-Type: text/plain\r\nContent-Length:{d}\r\n", .{body.len});
        try send_response(self.allocator, self.fd, ok, header, body);
    }

    pub fn matches(self: Self, request: *HttpRequest) bool {
        return mem.startsWith(u8, request.route, self.route);
    }
};

const RouteNotFoundHandler= struct {
    const Self = @This();

    route: []const u8 = undefined,
    allocator: *mem.Allocator,
    fd: i32,

    pub fn handle(self: Self, request: *HttpRequest) !void{
        _ = request;
        try send_response(self.allocator, self.fd, notFound, null, null);
    }
    fn matches(self: Self, request: *HttpRequest) bool {
        _ = self;
        _ = request;
        return false;
    }
};

pub const RouteHandler = union(enum) {
    const Self = @This();

    root: RootHandler,
    echo: EchoHandler,
    userAgent: UserAgentHandler,
    file: FileHandler,
    notFound: RouteNotFoundHandler,

    pub fn handle(self: Self, request: *HttpRequest) !void {
        switch (self) {
            inline else => |h| try h.handle(request),
        }
    }

    pub fn matches(self: Self, request: *HttpRequest) bool {
        switch (self) {
            inline else => |h| return h.matches(request),
        }
    }

    pub fn getHandler(request: *HttpRequest, allocator: *mem.Allocator, fd: i32 ) Self {
        const handlers = [_]RouteHandler{
            RouteHandler{ .root = RootHandler{ .allocator = allocator, .fd = fd } },
            RouteHandler{ .echo = EchoHandler{ .allocator = allocator, .fd = fd } },
            RouteHandler{ .userAgent = UserAgentHandler{ .allocator = allocator, .fd = fd } },
            RouteHandler{ .file = FileHandler{ .allocator = allocator, .fd = fd } },
        };

        for (handlers) |h| {
            if (h.matches(request)){
                return h;
            }
        }

        return RouteHandler{ .notFound = RouteNotFoundHandler{ .allocator = allocator, .fd = fd }};
    }
};
