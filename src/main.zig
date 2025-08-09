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

    var timer = try std.time.Timer.start();
    const parsed = jsonfetch.fetch(&client, *HttpBinResponse, .{ .location = .{ .url = url } }) catch |err| {
        std.debug.print("JSON fetch failed with {t}\n", .{err});
        std.process.exit(1);
    };
    std.debug.print("Fetch took {}ms\n", .{timer.read() / std.time.ns_per_ms});
    defer parsed.deinit();
    const value = parsed.value;

    try stdout.print(
        \\
        \\url     = {s}
        \\method  = {s}
        \\origin  = {s}
        \\headers =
        \\
    , .{ value.url, value.method, value.origin });

    var it = value.headers.object.iterator();
    while (it.next()) |hdr| {
        try stdout.print("  {s}: {s}\n", .{
            hdr.key_ptr.*,
            hdr.value_ptr.*.string,
        });
    }

    try stdout.flush(); // Don't forget to flush!
}
