const std = @import("std");
const mem = std.mem;

pub const Method = enum {
    GET,
    POST,
    DELETE,
    PUT,
    PATCH,
};

fn getEnumFieldFromString(comptime T: type, str: []const u8) ?T {
    inline for (@typeInfo(T).@"enum".fields) |enumField| {
        if (std.mem.eql(u8, str, enumField.name)) {
            return @field(T, enumField.name);
        }
    }
    return null;
}

pub const HttpRequest = struct {
    const Self = @This();

    method: Method,
    route: []const u8,
    protocol_version: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: *mem.Allocator,

    pub fn init(allocator: *mem.Allocator) HttpRequest {
        return .{
            .method = undefined,
            .route = undefined,
            .protocol_version = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator.*),
            .body = undefined,
            .allocator = allocator,
        };
    }

    pub fn parseRequest(self: *Self, request: []const u8) !void {
        var it_request = mem.splitSequence(u8, request, "\r\n");
        const request_line = it_request.next().?;

        var it_request_line = mem.splitScalar(u8, request_line, ' ');

        self.method = getEnumFieldFromString(Method, it_request_line.next().?) orelse return error.BadMethod;
        self.route = it_request_line.next().?;
        self.protocol_version = it_request_line.next().?;

        try self.parseHeaders(&it_request);

        _ = it_request.next();
        self.body = it_request.next();
    }

    fn parseHeaders(self: *Self, it: *mem.SplitIterator(u8, mem.DelimiterType.sequence)) !void {
        while(!mem.eql(u8, it.peek().?, "")){
            var line = it.next().?;
            const colon_pos = mem.indexOf(u8, line, ":") orelse continue;

            const key = line[0..colon_pos];
            const value = line[colon_pos + 1..];

            const trimmed_key = mem.trim(u8, key, " ");
            const trimmed_value = mem.trim(u8, value, " ");

            _ = try self.headers.put(trimmed_key, trimmed_value);
        }
    }

    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }
};
