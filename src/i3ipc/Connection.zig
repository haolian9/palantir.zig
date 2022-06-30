const std = @import("std");
const mem = std.mem;
const io = std.io;
const net = std.net;
const log = std.log;
const assert = std.debug.assert;

const Protocol = @import("Protocol.zig");

allocator: mem.Allocator,
stream: net.Stream,
rlock: std.Thread.Mutex,
wlock: std.Thread.Mutex,

const BufferedWriter = io.BufferedWriter(4 << 10, net.Stream.Writer);

const Self = @This();

pub fn init(allocator: mem.Allocator, path: []const u8) !Self {
    var stream = try net.connectUnixSocket(path);

    return Self{
        .allocator = allocator,
        .stream = stream,
        .rlock = std.Thread.Mutex{},
        .wlock = std.Thread.Mutex{},
    };
}

pub fn deinit(self: Self) void {
    self.stream.close();
}

// caller owns returned memory
pub fn roundtrip(self: *Self, mt: Protocol.MessageType, payload: []const u8) ![]const u8 {
    {
        self.wlock.lock();
        defer self.wlock.unlock();

        var wb = BufferedWriter{ .unbuffered_writer = self.stream.writer() };

        try Protocol.pack(wb.writer(), mt, payload);
        try wb.flush();
        log.debug("sent request: {s} {s}", .{ mt, payload });
    }

    {
        self.rlock.lock();
        defer self.rlock.unlock();

        log.debug("reading response", .{});

        // todo: is a buffered reader needed here?
        const reader = self.stream.reader();
        const header = try Protocol.unpackReplyHeader(reader);
        assert(header.len <= 1 << 20);
        log.debug("read response header: {}", .{header});

        // todo: stream/iterator instead of slice in memory?
        var resp = try self.allocator.alloc(u8, header.len);
        errdefer self.allocator.free(resp);

        {
            var remain: usize = header.len;
            var start_at: usize = 0;
            while (remain > 0) {
                const n = try reader.readAll(resp[start_at .. start_at + remain]);
                if (n == 0) break;
                remain -= n;
                start_at += n;
            }
            assert(start_at == header.len);
        }

        return resp;
    }
}
