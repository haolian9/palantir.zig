const std = @import("std");
const net = std.net;
const io = std.io;
const assert = std.debug.assert;
const mem = std.mem;
const log = std.log;

const i3ipc = @import("src/i3ipc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());

    const allocator = gpa.allocator();

    const path = try i3ipc.findSocketPath(allocator);
    defer allocator.free(path);
    log.debug("socket path: {s}", .{path});

    var conn = try i3ipc.Connection.init(allocator, path);
    defer conn.deinit();

    const resp = try conn.roundtrip(.run_command, "nop");
    defer allocator.free(resp);

    std.debug.print("resp={s}\n", .{resp});
}
