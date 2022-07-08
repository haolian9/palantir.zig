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
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try i3ipc.findSocketPath(&buffer);
        conn = try i3ipc.Connection.init(path);
    }
    defer conn.deinit();

    try conn.sendMsg(.subscribe, "[\"workspace\"]");

    var resp_iter = conn.iterateResp();
    defer resp_iter.deinit();

    if (false) {
        var buffer: [1 << 20]u8 = undefined;
        var countdown: usize = 3;
        while (resp_iter.next(&buffer)) |resp| {
            if (countdown < 1) break else countdown -= 1;
            log.info("{}", .{resp});
        } else |err| return err;
    } else {
        var countdown: usize = 3;
        while (resp_iter.nextAlloc(allocator, 1 << 20)) |resp| {
            defer allocator.free(resp.payload);
            if (countdown < 1) break else countdown -= 1;
            log.info("{}", .{resp});
        } else |err| return err;
    }
}
