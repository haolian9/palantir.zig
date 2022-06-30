const std = @import("std");
const linux = std.os.linux;

test "reader.readAllAlloc" {
    var fds: [2]i32 = undefined;
    switch (linux.getErrno(linux.pipe(&fds))) {
        .SUCCESS => {},
        else => unreachable,
    }

    const reader_side = fds[0];
    const writer_side = fds[1];

    var reader_stream = std.net.Stream{ .handle = reader_side };
    defer reader_stream.close();

    var writer_stream = std.net.Stream{ .handle = writer_side };
    defer writer_stream.close();

    const in = "abcde";

    try writer_stream.writer().writeAll(in);

    if (true) {
        const out = try reader_stream.reader().readAllAlloc(std.testing.allocator, 5);
        defer std.testing.allocator.free(out);

        try std.testing.expectEqualSlices(u8, in, out);
    } else {
        var buf: [5]u8 = undefined;
        const n = try reader_stream.reader().readAll(&buf);
        const out = buf[0..n];

        try std.testing.expectEqualSlices(u8, in, out);
    }
}
