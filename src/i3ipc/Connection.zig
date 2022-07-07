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
const Connection = Self;

pub const RespIterator = struct {
    ctx: *Connection,
    buffer: []u8,

    pub fn init(ctx: *Connection, buffer: []u8) RespIterator {
        ctx.rlock.lock();
        return .{ .ctx = ctx, .buffer = buffer };
    }

    pub fn deinit(self: *RespIterator) void {
        self.ctx.rlock.unlock();
    }

    pub fn next(self: RespIterator) ![]const u8 {
        return self.ctx.recvRespUnsafe(self.buffer);
    }
};

pub const RespIteratorAlloc = struct {
    ctx: *Connection,

    pub fn init(ctx: *Connection) RespIteratorAlloc {
        ctx.rlock.lock();
        return .{ .ctx = ctx };
    }

    pub fn deinit(self: *RespIteratorAlloc) void {
        self.ctx.rlock.unlock();
    }

    // need to free returned memory
    pub fn next(self: RespIteratorAlloc) ![]const u8 {
        return self.ctx.recvRespUnsafeAlloc();
    }
};

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
    try self.sendMsg(mt, payload);
    return self.recvResp();
}

pub fn sendMsg(self: *Self, mt: Protocol.MessageType, payload: []const u8) !void {
    self.wlock.lock();
    defer self.wlock.unlock();

    var wb = BufferedWriter{ .unbuffered_writer = self.stream.writer() };

    try Protocol.pack(wb.writer(), mt, payload);
    try wb.flush();
    log.debug("sent request: {s} {s}", .{ mt, payload });
}

// caller owns returned memory
pub fn recvRespAlloc(self: *Self) ![]const u8 {
    self.rlock.lock();
    defer self.rlock.unlock();

    return self.recvRespUnsafeAlloc();
}

pub fn recvResp(self: *Self, buffer: []u8) ![]const u8 {
    self.rlock.lock();
    defer self.rlock.unlock();

    return self.recvRespUnsafe(buffer);
}

pub fn iterateResp(self: *Self, buffer: []u8) RespIterator {
    return RespIterator.init(self, buffer);
}

pub fn iterateRespAlloc(self: *Self) RespIteratorAlloc {
    return RespIteratorAlloc.init(self);
}

fn recvRespUnsafeAlloc(self: Self) ![]const u8 {
    log.debug("reading response", .{});

    // todo: is a buffered reader needed here?
    const reader = self.stream.reader();
    // todo: handles eof
    const header = try Protocol.unpackResponseHeader(reader);
    log.debug("read response header: {}", .{header});

    if (header.len > 5 << 20) @panic("response is too big");

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

fn recvRespUnsafe(self: Self, buffer: []u8) ![]const u8 {
    log.debug("reading response", .{});

    // todo: is a buffered reader needed here?
    const reader = self.stream.reader();
    // todo: handles eof
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

    return buffer[0..header.len];
}
