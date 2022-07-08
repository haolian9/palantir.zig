const std = @import("std");
const testing = std.testing;
const fs = std.fs;

const Connection = @import("Connection.zig");
const Protocol = @import("Protocol.zig");
const socketpath = @import("socketpath.zig");

var i3_running: bool = false;

test "collect" {
    _ = @import("Protocol.zig");
}

test "set i3_running" {
    i3_running = true;

    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    _ = socketpath.findSocketPath(&buffer) catch |err| {
        i3_running = false;
        return err;
    };
}

test "findSocketPath" {
    if (!i3_running) return;

    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    _ = try socketpath.findSocketPath(&buffer);
}

test "findSocketPathAlloc" {
    if (!i3_running) return;

    const path = try socketpath.findSocketPathAlloc(testing.allocator);
    testing.allocator.free(path);
}

test "Connection.roundtrip - reply" {
    if (!i3_running) return;

    const path = try socketpath.findSocketPathAlloc(testing.allocator);
    defer testing.allocator.free(path);

    var conn = try Connection.init(path);
    defer conn.deinit();

    const expected_payload = "[{\"success\":true}]";
    var buffer: [expected_payload.len]u8 = undefined;
    const resp = try conn.roundtrip(.{
        .buffer = &buffer,
        .msg_type = .run_command,
        .payload = "nop",
    });
    try testing.expectEqual(Protocol.ResponseType.Reply.command, resp.header.type.reply);
    try testing.expect(resp.header.len == resp.header.len);
    try testing.expectEqualStrings(expected_payload, resp.payload);
}

test "Connection.roundtripAlloc - reply" {
    if (!i3_running) return;

    const path = try socketpath.findSocketPathAlloc(testing.allocator);
    defer testing.allocator.free(path);

    var conn = try Connection.init(path);
    defer conn.deinit();

    const allocator = testing.allocator;
    const expected_payload = "[{\"success\":true}]";

    const resp = try conn.roundtripAlloc(.{
        .allocator = allocator,
        .msg_type = .run_command,
        .payload = "nop",
        .max_resp_payload_size = expected_payload.len,
    });
    defer allocator.free(resp.payload);

    try testing.expectEqual(Protocol.ResponseType.Reply.command, resp.header.type.reply);
    try testing.expect(resp.header.len == resp.header.len);
    try testing.expectEqualStrings(expected_payload, resp.payload);
}

test "Connection.iterateResp" {
    // todo
}
