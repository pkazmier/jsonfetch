const std = @import("std");
const log = std.log.scoped(.jsonfetch);
const Parsed = std.json.Parsed;

pub const FetchError = std.mem.Allocator.Error ||
    error{
        HttpStatusError,
        HttpFetchError,
        JsonParseError,
    };

// Caller must call `deinit` on the returned object.
pub fn fetch(client: *std.http.Client, comptime T: type, options: std.http.Client.FetchOptions) FetchError!Parsed(T) {
    const allocator = client.allocator;

    // If user doesn't provide response storage, then we provide it.
    var options_copy = options;
    var maybe_buf: ?std.ArrayList(u8) = null;
    if (options_copy.response_storage == .ignore) {
        maybe_buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
        options_copy.response_storage = .{ .dynamic = &maybe_buf.? };
    }
    defer {
        if (maybe_buf) |buf| buf.deinit();
    }

    const http_result = client.fetch(options_copy) catch |err| {
        log.debug("HTTP fetch failed with {t}", .{err});
        return FetchError.HttpFetchError;
    };

    if (http_result.status != .ok) {
        log.debug("HTTP request failed with code {d} {s}", .{
            http_result.status,
            http_result.status.phrase() orelse "???",
        });
        return FetchError.HttpStatusError;
    }

    const items: []u8 = switch (options_copy.response_storage) {
        .dynamic => |al| al.items,
        .static => |alu| alu.items,
        .ignore => unreachable,
    };

    // TODO: allow user to specify parse options.
    const parsed = std.json.parseFromSlice(T, allocator, items, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |err| {
        log.debug("JSON parse failed with {t}", .{err});
        return FetchError.JsonParseError;
    };

    return parsed;
}
// ----------------------------------------------------------------------------
// Testing code follows
// ----------------------------------------------------------------------------
test "json fetch typical use case" {
    const test_server = try test_server_with_json();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
        name: []const u8,
        aliases: [][]const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const parsed = try fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("George Costanza", parsed.value.name);
    try std.testing.expectEqual(38, parsed.value.age);
    try std.testing.expectEqualDeep(&[_][]const u8{ "Art Vandalay", "Buck Naked" }, parsed.value.aliases);
}

test "json fetch with client provided dynamic storage for response" {
    const test_server = try test_server_with_json();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
        name: []const u8,
        aliases: [][]const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    const parsed = try fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
        .response_storage = .{ .dynamic = &buf },
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("George Costanza", parsed.value.name);
    try std.testing.expectEqual(38, parsed.value.age);
    try std.testing.expectEqualDeep(&[_][]const u8{ "Art Vandalay", "Buck Naked" }, parsed.value.aliases);
}

test "json fetch with client provided static storage for response" {
    const test_server = try test_server_with_json();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
        name: []const u8,
        aliases: [][]const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    // Pass in our own static buffer for the response storage
    var buf = try std.ArrayListUnmanaged(u8).initCapacity(std.testing.allocator, 1024);
    defer buf.deinit(std.testing.allocator);

    const parsed = try fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
        .response_storage = .{ .static = &buf },
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("George Costanza", parsed.value.name);
    try std.testing.expectEqual(38, parsed.value.age);
    try std.testing.expectEqualDeep(&[_][]const u8{ "Art Vandalay", "Buck Naked" }, parsed.value.aliases);
}

test "json fetch with client provided too small static storage for response" {
    const test_server = try test_server_with_json();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
        name: []const u8,
        aliases: [][]const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    // Pass in a static buffer for the response storage that is too small. 80
    // bytes is too small for the server response.
    var buf = try std.ArrayListUnmanaged(u8).initCapacity(std.testing.allocator, 80);
    defer buf.deinit(std.testing.allocator);

    const parsed = fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
        .response_storage = .{ .static = &buf },
    });
    try std.testing.expectError(FetchError.JsonParseError, parsed);
}

test "json fetch non-200 response from server" {
    const test_server = try test_server_non200_response();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
        name: []const u8,
        aliases: [][]const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const parsed = fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
    });
    try std.testing.expectError(FetchError.HttpStatusError, parsed);
}

test "json fetch with extra fields in response from server" {
    const test_server = try test_server_with_json();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const parsed = try fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
    });
    defer parsed.deinit();
    try std.testing.expectEqual(38, parsed.value.age);
}

test "json fetch with missing fields in response from server" {
    const test_server = try test_server_with_json();
    defer test_server.destroy();

    const Response = struct {
        age: i32,
        missing: []const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const parsed = fetch(&client, *Response, .{
        .location = .{ .uri = .{
            .scheme = "http",
            .host = .{ .raw = "127.0.0.1" },
            .port = test_server.port(),
        } },
    });
    try std.testing.expectError(FetchError.JsonParseError, parsed);
}

test "json fetch to non-existent server" {
    const Response = struct {
        age: i32,
        name: []const u8,
        aliases: [][]const u8,
    };

    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const parsed = fetch(&client, *Response, .{
        .location = .{ .url = "http://nosuchhost.example.com" },
    });
    try std.testing.expectError(FetchError.HttpFetchError, parsed);
}

const TestServer = struct {
    server_thread: std.Thread,
    net_server: std.net.Server,

    fn destroy(self: *@This()) void {
        self.server_thread.join();
        self.net_server.deinit();
        std.testing.allocator.destroy(self);
    }

    fn port(self: @This()) u16 {
        return self.net_server.listen_address.in.getPort();
    }
};

fn createTestServer(S: type) !*TestServer {
    const address = try std.net.Address.parseIp("127.0.0.1", 0);
    const test_server = try std.testing.allocator.create(TestServer);
    test_server.net_server = try address.listen(.{ .reuse_address = true });
    test_server.server_thread = try std.Thread.spawn(.{}, S.run, .{&test_server.net_server});
    return test_server;
}

fn test_server_with_json() !*TestServer {
    return try createTestServer(struct {
        fn run(net_server: *std.net.Server) anyerror!void {
            const conn = try net_server.accept();
            defer conn.stream.close();
            var header_buffer: [888]u8 = undefined;
            var server = std.http.Server.init(conn, &header_buffer);
            var request = try server.receiveHead();
            try request.respond(
                \\{
                \\  "name": "George Costanza",
                \\  "age": 38,
                \\  "aliases": [ "Art Vandalay", "Buck Naked" ]
                \\}
            , .{});
        }
    });
}

fn test_server_non200_response() !*TestServer {
    return try createTestServer(struct {
        fn run(net_server: *std.net.Server) anyerror!void {
            const conn = try net_server.accept();
            defer conn.stream.close();
            var header_buffer: [888]u8 = undefined;
            var server = std.http.Server.init(conn, &header_buffer);
            var request = try server.receiveHead();
            try request.respond("", .{ .status = .not_found });
        }
    });
}
