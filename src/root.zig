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
pub fn fetch(client: *std.http.Client, url: []const u8, comptime T: type) FetchError!Parsed(T) {
    const allocator = client.allocator;

    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buf.deinit();

    const http_result = client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &buf },
    }) catch |err| {
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

    const parsed = std.json.parseFromSlice(T, allocator, buf.items, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch |err| {
        log.debug("JSON parse failed with {t}", .{err});
        return FetchError.JsonParseError;
    };

    return parsed;
}
