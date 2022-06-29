const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const net = std.net;
const io = std.io;
const json = std.json;

const i3ipc = @import("src/i3ipc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());

    const allocator = gpa.allocator();

    var stream = blk: {
        const path = try i3ipc.findSocketPath(allocator);
        defer allocator.free(path);

        print("path='{s}'\n", .{path});
        break :blk try net.connectUnixSocket(path);
    };
    defer stream.close();

    {
        var write_buffer = io.bufferedWriter(stream.writer());
        const writer = write_buffer.writer();
        try i3ipc.Protocol.pack(writer, .run_command, "nop");
        try write_buffer.flush();
    }

    const reply_payload = blk: {
        var read_buffer: [1024]u8 = undefined;
        const reader = stream.reader();

        const header = try i3ipc.Protocol.unpackReplyHeader(reader);
        assert(header.len <= read_buffer.len);
        const payload = read_buffer[0..header.len];
        _ = try reader.readAll(payload);
        print("header={any}\n", .{header});
        print("payload={s}\n", .{payload});

        break :blk payload;
    };

    {
        var parser = json.Parser.init(allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(reply_payload);
        defer tree.deinit();

        assert(tree.root.Array.items[0].Object.get("success").?.Bool);
    }
}
