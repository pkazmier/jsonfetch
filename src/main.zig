const std = @import("std");
const jsonfetch = @import("jsonfetch");

var buffer: [128]u8 = undefined;
var writer = std.fs.File.stdout().writer(&buffer);
const stdout = &writer.interface;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("usage: {s} <url>\n", .{args[0]});
        std.process.exit(1);
    }
    const url = args[1];

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const parsed = jsonfetch.fetch(
        &client,
        *std.json.Value,
        .{ .location = .{ .url = url } },
        .{},
    ) catch |err| {
        std.debug.print("JSON fetch failed with {t}\n", .{err});
        std.process.exit(1);
    };
    defer parsed.deinit();

    try std.json.Stringify.value(parsed.value, .{ .whitespace = .indent_3 }, stdout);
    try stdout.print("\n", .{});
    try stdout.flush(); // Don't forget to flush!
}
