# jsonfetch

Utility function to make an HTTP request and parse the JSON response in Zig.

This module provides a thin wrapper around `std.http.Client.fetch` and
`std.json.parseFromSlice` to simplify making an HTTP request and parsing the
JSON response.

## Installation

This library tracks Zig main.

1. Add `jsonfetch.zig` as a dependency in your `build.zig.zon`:

   ```console
   zig fetch --save "git+https://github.com/pkazmier/jsonfetch#main"
   ```

2. Add the `jsonfetch` module as a dependency in your `build.zig`:

   ```zig
   const jsonfetch = b.dependency("jsonfetch", .{
       .target = target,
       .optimize = optimize,
   });
   // the executable from your call to b.addExecutable(...)
   exe.root_module.addImport("jsonfetch", jsonfetch.module("jsonfetch"));
   ```

## Example

The following example parses the JSON output returned by the
[`httpbin.org/anything`](http://httpbin.org/anything) endpoint, which is shown
below:

```json
{
  "args": {},
  "data": "",
  "files": {},
  "form": {},
  "headers": {
    "Accept-Encoding": "gzip, deflate",
    "Host": "httpbin.org",
    "User-Agent": "zig/0.15.0-dev.1228+6dbcc3bd5 (std.http)"
  },
  "json": null,
  "method": "GET",
  "origin": "10.1.100.35",
  "url": "http://httpbin.org/anything"
}
```

To use `jsonfetch.fetch` you'll define a struct to hold the parsed result. The
Zig JSON parser requires that the fields of this struct match the fields of
the JSON response. If you want to only parse some of the fields, you can use
the `.ignore_unknown_fields` parser option as shown below.

```zig
const std = @import("std");
const jsonfetch = @import("jsonfetch");

const HttpBinResponse = struct {
    url: []const u8,
    method: []const u8,
    origin: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.detectLeaks();
    const allocator = gpa.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const parsed = try jsonfetch.fetch(
        &client,
        *HttpBinResponse,
        // std.http.Client.FetchOptions
        .{ .location = .{ .url = "http://httpbin.org/anything" } },
        // std.json.ParseOptions
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const v = parsed.value;
    std.debug.print("{s} {s} from {s}\n", .{ v.method, v.url, v.origin });
}
```
