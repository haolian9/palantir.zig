const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const i3ipc = @import("src/i3ipc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());

    const allocator = gpa.allocator();

    var conn: i3ipc.Connection = undefined;
    {
        const path = try i3ipc.findSocketPath(allocator);
        defer allocator.free(path);
        conn = try i3ipc.Connection.init(allocator, path);
    }
    defer conn.deinit();

    try conn.sendMsg(.subscribe, "[\"workspace\"]");

    if (true) {
        var buffer: [1 << 20]u8 = undefined;
        var resp_iter = conn.iterateResp(&buffer);
        defer resp_iter.deinit();

        var countdown: usize = 3;
        while (resp_iter.next()) |resp| {
            if (countdown < 1) break else countdown -= 1;
            log.info("{s}", .{resp});
        } else |err| return err;
    } else {
        var resp_iter = conn.iterateRespAlloc();
        defer resp_iter.deinit();

        var countdown: usize = 3;
        while (resp_iter.next()) |resp| {
            defer allocator.free(resp);
            if (countdown < 1) break else countdown -= 1;
            log.info("{s}", .{resp});
        } else |err| return err;
    }
}
