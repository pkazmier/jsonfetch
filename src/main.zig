const std = @import("std");
const jsonfetch = @import("jsonfetch");

var buffer: [128]u8 = undefined;
var writer = std.fs.File.stdout().writer(&buffer);
const stdout = &writer.interface;

const url = "http://httpbin.org/anything";

const HttpBinResponse = struct {
    method: []const u8,
    origin: []const u8,
    url: []const u8,
    headers: std.json.Value,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Version 1
    // const result = try jsonfetch.fetch1(&client, url, *HttpBinResponse);
    // defer result.deinit();
    //
    // const parsed = result.parsed orelse {
    //     try stdout.print("Non-200 response received: {d}\n", .{result.status});
    //     return;
    // };
    // const value = parsed.value;

    // Version 2
    const result = try jsonfetch.fetch2(&client, url, *HttpBinResponse);
    defer result.deinit();

    const value = result.value orelse {
        try stdout.print("Non-200 response received: {d}\n", .{result.status});
        return;
    };

    // Everything below is the same.
    try stdout.print(
        \\
        \\url     = {s}
        \\method  = {s}
        \\status  = {d}
        \\origin  = {s}
        \\headers =
        \\
    , .{ value.url, value.method, result.status, value.origin });

    var it = value.headers.object.iterator();
    while (it.next()) |hdr| {
        try stdout.print("  {s}: {s}\n", .{
            hdr.key_ptr.*,
            hdr.value_ptr.*.string,
        });
    }

    try stdout.flush(); // Don't forget to flush!
}
