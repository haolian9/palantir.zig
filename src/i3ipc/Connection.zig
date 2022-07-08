const std = @import("std");
const mem = std.mem;
const io = std.io;
const net = std.net;
const log = std.log;
const assert = std.debug.assert;
const testing = std.testing;

const Protocol = @import("Protocol.zig");

// todo: handles eof when read

stream: net.Stream,
rlock: std.Thread.Mutex,
wlock: std.Thread.Mutex,

const BufferedWriter = io.BufferedWriter(4 << 10, net.Stream.Writer);

const Self = @This();
const Connection = Self;

pub const Resp = struct {
    header: Protocol.ResponseHeader,
    payload: []const u8,

    pub fn format(self: Resp, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = self;
        _ = fmt;
        _ = options;
        _ = writer;
        return std.fmt.format(writer, "({any}, {s})", .{self.header, self.payload});
    }
};

pub const RespIterator = struct {
    ctx: *Connection,

    pub fn init(ctx: *Connection) RespIterator {
        ctx.rlock.lock();
        return .{ .ctx = ctx };
    }

    pub fn deinit(self: *RespIterator) void {
        self.ctx.rlock.unlock();
    }

    pub fn next(self: RespIterator, buffer: []u8) !Resp {
        return self.ctx.recvRespUnsafe(buffer);
    }

    pub fn nextAlloc(self: RespIterator, allocator: mem.Allocator, max_size: usize) !Resp {
        return self.ctx.recvRespUnsafeAlloc(allocator, max_size);
    }
};

pub fn init(path: []const u8) !Self {
    var stream = try net.connectUnixSocket(path);

    return Self{
        .stream = stream,
        .rlock = std.Thread.Mutex{},
        .wlock = std.Thread.Mutex{},
    };
}

pub fn deinit(self: Self) void {
    self.stream.close();
}

pub fn roundtrip(
    self: *Self,
    args: struct {
        buffer: []u8,
        msg_type: Protocol.MessageType = .run_command,
        payload: []const u8,
    },
) !Resp {
    try self.sendMsg(args.msg_type, args.payload);
    return self.recvResp(args.buffer);
}

// caller owns resp.payload
pub fn roundtripAlloc(
    self: *Self,
    args: struct {
        allocator: mem.Allocator,
        msg_type: Protocol.MessageType = .run_command,
        payload: []const u8,
        max_resp_payload_size: usize = 1 << 20,
    },
) !Resp {
    try self.sendMsg(args.msg_type, args.payload);
    return self.recvRespAlloc(args.allocator, args.max_resp_payload_size);
}

pub fn sendMsg(self: *Self, msg_type: Protocol.MessageType, payload: []const u8) !void {
    self.wlock.lock();
    defer self.wlock.unlock();

    var wb = BufferedWriter{ .unbuffered_writer = self.stream.writer() };

    try Protocol.pack(wb.writer(), msg_type, payload);
    try wb.flush();
    log.debug("sent request: {s} {s}", .{ msg_type, payload });
}

// caller owns returned memory
pub fn recvRespAlloc(self: *Self, allocator: mem.Allocator, max_size: usize) !Resp {
    self.rlock.lock();
    defer self.rlock.unlock();

    return self.recvRespUnsafeAlloc(allocator, max_size);
}

pub fn recvResp(self: *Self, buffer: []u8) !Resp {
    self.rlock.lock();
    defer self.rlock.unlock();

    return self.recvRespUnsafe(buffer);
}

pub fn iterateResp(self: *Self) RespIterator {
    return RespIterator.init(self);
}

fn recvRespUnsafeAlloc(self: Self, allocator: mem.Allocator, max_size: usize) !Resp {
    log.debug("reading response", .{});

    const reader = self.stream.reader();
    const header = try Protocol.unpackResponseHeader(reader);
    log.debug("read response header: {}", .{header});

    if (header.len > max_size) @panic("response is too big");

    var payload = try allocator.alloc(u8, header.len);
    errdefer allocator.free(payload);

    {
        var remain: usize = header.len;
        var start_at: usize = 0;
        while (remain > 0) {
            const n = try reader.readAll(payload[start_at .. start_at + remain]);
            if (n == 0) break;
            remain -= n;
            start_at += n;
        }
        assert(start_at == header.len);
    }

    return Resp{
        .header = header,
        .payload = payload,
    };
}

fn recvRespUnsafe(self: Self, buffer: []u8) !Resp {
    log.debug("reading response", .{});

    const reader = self.stream.reader();
    const header = try Protocol.unpackResponseHeader(reader);
    log.debug("read response header: {}", .{header});

    if (header.len > buffer.len) return error.bufferOverflowed;

    {
        var remain: usize = header.len;
        var start_at: usize = 0;
        while (remain > 0) {
            const n = try reader.readAll(buffer[start_at .. start_at + remain]);
            if (n == 0) break;
            remain -= n;
            start_at += n;
        }
        assert(start_at == header.len);
    }

    return Resp{ .header = header, .payload = buffer[0..header.len] };
}
