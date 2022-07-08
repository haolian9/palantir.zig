const std = @import("std");
const log = std.log;

const i3ipc = @import("src/i3ipc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());

    const allocator = gpa.allocator();

    const path = try i3ipc.findSocketPathAlloc(allocator);
    defer allocator.free(path);
    log.debug("path='{s}'", .{path});

    var stream = try std.net.connectUnixSocket(path);
    defer stream.close();

    {
        var write_buffer = std.io.bufferedWriter(stream.writer());
        const writer = write_buffer.writer();
        try i3ipc.Protocol.pack(writer, .run_command, "nop");
        try write_buffer.flush();
    }

    const reader = stream.reader();
    var buf: [1024]u8 = undefined;
    const n = try reader.read(&buf);
    const resp = buf[0..n];

    log.info("'{s}'", .{std.fmt.fmtSliceEscapeLower(resp)});
}
