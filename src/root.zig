const std = @import("std");

// Two different implementations for comparison and feedback.

// VERSION 1:
// The two downsides of this version in my opinion include:
//
// 1. The JSON value we decoded is wrapped in a std.json.Parsed,
//    which means the user must access the `value` field of it.
//    This seems like one extra step that shouldn't be required.
//
// 2. The buffer that we allocate to hold the HTTP response is
//    freed upon returning from fetch, so that means we need to
//    use the `.allac_always` option when parsing the JSON. This
//    results in double allocating memory for the JSON strings.
//
// The upside is that `JsonResult1` result does not have any
// extra "private" fields.

fn JsonResult1(comptime T: type) type {
    return struct {
        status: std.http.Status,
        parsed: ?std.json.Parsed(T),

        pub fn deinit(self: @This()) void {
            if (self.parsed) |parsed| {
                parsed.deinit();
            }
        }
    };
}

// Caller must call `deinit` on the returned object.
pub fn fetch1(client: *std.http.Client, url: []const u8, comptime T: type) !JsonResult1(T) {
    const allocator = client.allocator;

    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer buf.deinit();

    const http_result = try client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &buf },
    });

    var json_result = JsonResult1(T){
        .status = http_result.status,
        .parsed = null,
    };

    if (http_result.status != std.http.Status.ok) {
        return json_result;
    }

    const parsed = try std.json.parseFromSlice(T, allocator, buf.items, .{
        .ignore_unknown_fields = true,
        // Must always alloc because 'buf' is freed upon return
        .allocate = .alloc_always,
    });

    json_result.parsed = parsed;
    return json_result;
}

// ---------------------------------------------------------------------------
// VERSION 2:
// This version fixes the two downsides of version 1:
//
// 1. The JSON value we decoded is no longer wrapped in `Parsed`
//    and is now made available to the user as a direct member
//    of the `JsonResult2`. But we still need to hold a reference
//    to `Parsed` so it can later be reclaimed via `deinit` by
//    the user. We store this reference as `_parsed` to imply it
//    is not intended for public use.
//
// 2. The buffer that we allocate to hold the HTTP response is
//    no longer freed upon returning from fetch. Instead, we save
//    this as a "private" member of `JsonResult2` as `_buf`. This
//    means we can use the `alloc_if_needed` option when porsing
//    the JSON--hopefully avoiding unnecessary allocations.
//
// The downside is that `JsonResult2` now has two extra "private"
// fields that are exposed to the user.

fn JsonResult2(comptime T: type) type {
    return struct {
        status: std.http.Status,
        value: ?T,

        _buf: std.ArrayList(u8),
        _parsed: ?std.json.Parsed(T),

        pub fn deinit(self: @This()) void {
            self._buf.deinit();
            if (self._parsed) |p| {
                p.deinit();
            }
        }
    };
}

// Caller must call `deinit` on the returned object.
pub fn fetch2(client: *std.http.Client, url: []const u8, comptime T: type) !JsonResult2(T) {
    const allocator = client.allocator;

    var buf = try std.ArrayList(u8).initCapacity(allocator, 1024);
    errdefer buf.deinit();

    const http_result = try client.fetch(.{
        .location = .{ .url = url },
        .response_storage = .{ .dynamic = &buf },
    });

    var json_result = JsonResult2(T){
        .status = http_result.status,
        .value = null,
        ._buf = buf,
        ._parsed = null,
    };

    if (http_result.status != std.http.Status.ok) {
        return json_result;
    }

    const parsed = try std.json.parseFromSlice(T, allocator, buf.items, .{
        .ignore_unknown_fields = true,
        // We don't have to allocate again because we don't free 'buf' now
        .allocate = .alloc_if_needed,
    });

    json_result._parsed = parsed;
    json_result.value = parsed.value;
    return json_result;
}
