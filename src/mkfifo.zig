const std = @import("std");
const linux = std.os.linux;
const log = std.log;

pub fn mkfifo(path: [*:0]const u8, mode: u32) !void {
    switch (linux.getErrno(linux.mknod(path, linux.S.IFIFO | linux.S.IWUSR | linux.S.IRUSR | mode, 0))) {
        .SUCCESS => {},
        .EXIST => try ensureFIFO(path),
        else => |errno| {
            log.err("mkfifo error: {}\n", .{errno});
            unreachable;
        },
    }
}

fn ensureFIFO(path: [*:0]const u8) !void {
    var stat: linux.Stat = undefined;
    switch (linux.getErrno(linux.stat(path, &stat))) {
        .SUCCESS => {
            if (!linux.S.ISFIFO(stat.mode)) return error.NotFIFO;
        },
        else => |errno| {
            log.err("stat error: {}\n", .{errno});
            unreachable;
        },
    }
}
