const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;
const net = std.net;
const os = std.os;
const process = std.process;
const fs = std.fs;
const log = std.log;
const io = std.io;
const testing = std.testing;

/// the caller owns result memory
fn findSocketPath(allocator: mem.Allocator) ![]const u8 {
    // try env.I3SOCK first
    // then i3 --get-socketpath

    // TODO@haoliang avoid this allocation
    if (os.getenv("I3SOCK")) |path| return try allocator.dupe(u8, path);

    const result = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = &.{ "/usr/bin/i3", "--get-socketpath" } });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => {
            if (mem.endsWith(u8, result.stdout, "\n")) {
                defer allocator.free(result.stdout);
                // TODO@haoliang avoid this allocation
                return try allocator.dupe(u8, result.stdout[0 .. result.stdout.len - 2]);
            } else {
                return result.stdout;
            }
        },
        else => {
            defer allocator.free(result.stdout);
            log.err("abnormal termination for i3 --get-socketpath: {s}", .{result.stderr});
        },
    }

    return error.NotFound;
}

const Protocol = struct {
    const magic = "i3-ipc";
    const MessageType = enum(u32) {
        run_command,
        get_workspaces,
        subscribe,
        get_outputs,
        get_tree,
        get_marks,
        get_bar_config,
        get_version,
        get_binding_modes,
        get_config,
        send_tick,
        sync,
        get_binding_state,
    };
    const ReplyType = enum(u32) {
        command,
        workspaces,
        subscribe,
        outputs,
        tree,
        marks,
        bar_config,
        version,
        binding_modes,
        config,
        tick,
        sync,
        binding_state,
    };
    fn pack(writer: anytype, mt: MessageType, payload: []const u8) !void {
        try writer.writeAll(magic);
        try writer.writeIntNative(u32, @intCast(u32, payload.len));
        try writer.writeIntNative(u32, @enumToInt(mt));
        try writer.writeAll(payload);
    }
};

test "protocol.pack" {
    // see https://i3wm.org/docs/ipc.html#_establishing_a_connection
    var buffer: [32]u8 = undefined;
    var stream = io.fixedBufferStream(&buffer);
    try Protocol.pack(stream.writer(), .run_command, "exit");
    const wrote = stream.getWritten();
    const expected = [_]u8{ 0x69, 0x33, 0x2d, 0x69, 0x70, 0x63, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x65, 0x78, 0x69, 0x74 };
    try testing.expectEqualStrings(&expected, wrote);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer assert(!gpa.deinit());

    const allocator = gpa.allocator();

    const path = try findSocketPath(allocator);
    defer allocator.free(path);

    print("path='{s}'\n", .{path});

    var stream = try net.connectUnixSocket(path);
    defer stream.close();

    var write_buffer = io.bufferedWriter(stream.writer());
    var read_buffer: [1024]u8 = undefined;
    const writer = write_buffer.writer();
    const reader = stream.reader();

    try Protocol.pack(writer, .run_command, "nop");
    try write_buffer.flush();

    const rn = try reader.read(&read_buffer);
    print("read: {s}\n", .{read_buffer[0..rn]});
}