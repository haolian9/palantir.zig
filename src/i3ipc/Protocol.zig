const std = @import("std");
const mem = std.mem;
const io = std.io;
const assert = std.debug.assert;
const testing = std.testing;

const magic = "i3-ipc";
const header_size = 14;
const magic_size = magic.len;
const type_size = 4;

pub const MessageType = enum(u32) {
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

pub const ResponseHeader = struct {
    magic: [magic_size]u8,
    len: u32,
    type: Type,

    pub const Type = union(enum) {
        reply: Reply,
        event: Event,

        pub const Reply = enum(u32) {
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

        pub const Event = enum(u32) {
            workspace,
            output,
            mode,
            window,
            barconfig_update,
            binding,
            shutdown,
            tick,
        };

        fn init(int: u32) Type {
            return if (int >> 31 == 1) .{ .event = @intToEnum(Event, int & 0x7f) } else .{ .reply = @intToEnum(Reply, int) };
        }
    };
};

pub const Response = union {
    reply: []const u8,
    event: []const u8,
};

pub fn pack(writer: anytype, mt: MessageType, payload: []const u8) !void {
    try writer.writeAll(magic);
    try writer.writeIntNative(u32, @intCast(u32, payload.len));
    try writer.writeIntNative(u32, @enumToInt(mt));
    try writer.writeAll(payload);
}

pub fn unpackResponseHeader(reader: anytype) !ResponseHeader {
    var raw: [header_size]u8 = undefined;

    const rn = try reader.readAll(&raw);
    if (rn < raw.len) return error.headerSizeTooSmall;

    const header = ResponseHeader{ .magic = raw[0..6].*, .len = mem.readIntNative(u32, raw[6..10]), .type = ResponseHeader.Type.init(mem.readIntNative(u32, raw[10..14])) };
    assert(mem.eql(u8, &header.magic, magic));

    return header;
}

test "protocol.pack" {
    // see https://i3wm.org/docs/ipc.html#_establishing_a_connection
    var buffer: [32]u8 = undefined;
    var stream = io.fixedBufferStream(&buffer);
    try pack(stream.writer(), .run_command, "nop");

    const wrote = stream.getWritten();
    const expected = [_]u8{ 0x69, 0x33, 0x2d, 0x69, 0x70, 0x63, 3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 'n', 'o', 'p' };

    try testing.expectEqualStrings(&expected, wrote);
}

test "protocol.unpackResponseHeader" {
    const raw = "i3-ipc\x12\x00\x00\x00\x00\x00\x00\x00[{\"success\":true}]";
    const expected = ResponseHeader{ .magic = magic.*, .len = 18, .type = .{ .reply = .command } };
    var stream = io.fixedBufferStream(raw);
    const header = try unpackResponseHeader(stream.reader());

    try expectEqual(expected, header);
}

fn expectEqual(expected: anytype, actual: @TypeOf(expected)) !void {
    switch (@typeInfo(@TypeOf(actual))) {
        .Struct => |structType| {
            inline for (structType.fields) |field| {
                const field_name = field.name;
                expectEqual(@field(expected, field_name), @field(actual, field_name)) catch |err| {
                    std.debug.print("not equal on field {s}; {any} != {any}\n", .{ field_name, @field(expected, field_name), @field(actual, field_name) });
                    return err;
                };
            }
        },
        else => try testing.expectEqual(expected, actual),
    }
}
