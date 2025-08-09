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

    const parsed = std.json.parseFromSlice(T, allocator, items, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |err| {
        log.debug("JSON parse failed with {t}", .{err});
        return FetchError.JsonParseError;
    };

    return parsed;
}
