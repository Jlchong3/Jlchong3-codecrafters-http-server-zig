const std = @import("std");

pub const HttpRequest = struct {
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
        var it_request = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = it_request.next().?;

        var it_request_line = std.mem.splitScalar(u8, request_line, ' ');

        self.method = it_request_line.next().?;
        self.route = it_request_line.next().?;
        self.protocol_version = it_request_line.next().?;

        try self.parseHeaders(&it_request);

        _ = it_request.next();
        self.body = it_request.next();
    }

    fn parseHeaders(self: *HttpRequest, it: *std.mem.SplitIterator(u8, std.mem.DelimiterType.sequence)) !void {
        while(!std.mem.eql(u8, it.peek().?, "")){
            var line = it.next().?;
            const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;

            const key = line[0..colon_pos];
            const value = line[colon_pos + 1..];

            const trimmed_key = std.mem.trim(u8, key, " ");
            const trimmed_value = std.mem.trim(u8, value, " ");

            _ = try self.headers.put(trimmed_key, trimmed_value);
        }
    }
};
