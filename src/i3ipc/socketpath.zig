const std = @import("std");
const mem = std.mem;
const os = std.os;
const linux = std.os.linux;
const log = std.log;

/// the caller owns result memory
pub fn findSocketPathAlloc(allocator: mem.Allocator) ![]const u8 {
    // try env.I3SOCK first
    // then i3 --get-socketpath

    if (os.getenv("I3SOCK")) |path| {
        // after `i3 restart`, this env var can be wrong.
        var stat: linux.Stat = undefined;
        switch (linux.getErrno(linux.stat(&try os.toPosixPath(path), &stat))) {
            .SUCCESS => {
                if (linux.S.ISSOCK(stat.mode)) {
                    return try allocator.dupe(u8, path);
                } else {
                    log.debug("I3SOCK not exists", .{});
                }
            },
            else => |errno| {
                log.debug("I3SOCK stat error: {}", .{errno});
            },
        }
    } else {
        log.debug("I3SOCK is missing", .{});
    }

    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "/usr/bin/i3", "--get-socketpath" },
        .max_output_bytes = std.fs.MAX_PATH_BYTES,
    });
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }

    switch (result.term) {
        .Exited => |rc| {
            if (rc == 0) {
                if (mem.endsWith(u8, result.stdout, "\n")) {
                    return try allocator.dupe(u8, result.stdout[0 .. result.stdout.len - 1]);
                } else {
                    return result.stdout;
                }
            } else {
                log.err("not success return-code: {d}", .{rc});
            }
        },
        else => {
            log.err("abnormal termination for i3 --get-socketpath: {s}", .{result.stderr});
        },
    }

    return error.NotFound;
}

pub fn findSocketPath(buffer: []u8) ![]const u8 {
    // try env.I3SOCK first
    // then i3 --get-socketpath

    if (os.getenv("I3SOCK")) |path| {
        // after `i3 restart`, this env var can be wrong.
        var stat: linux.Stat = undefined;
        switch (linux.getErrno(linux.stat(&try os.toPosixPath(path), &stat))) {
            .SUCCESS => {
                if (linux.S.ISSOCK(stat.mode)) {
                    if (path.len > buffer.len) return error.bufferOverflowed;
                    mem.copy(u8, buffer[0..path.len], path);
                    return buffer[0..path.len];
                } else {
                    log.debug("I3SOCK not exists", .{});
                }
            },
            else => |errno| {
                log.debug("I3SOCK stat error: {}", .{errno});
            },
        }
    } else {
        log.debug("I3SOCK is missing", .{});
    }

    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const allocator = fba.allocator();
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "/usr/bin/i3", "--get-socketpath" },
        .max_output_bytes = buffer.len,
    });

    switch (result.term) {
        .Exited => |rc| {
            if (rc == 0) {
                if (mem.endsWith(u8, result.stdout, "\n")) {
                    return result.stdout[0 .. result.stdout.len - 1];
                } else {
                    return result.stdout;
                }
            } else {
                log.err("not success return-code: {d}", .{rc});
            }
        },
        else => {
            log.err("abnormal termination for i3 --get-socketpath: {s}", .{result.stderr});
        },
    }

    return error.NotFound;
}

pub fn main() !void {
    {
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try findSocketPath(&buffer);
        std.debug.print("found socket path: {s}\n", .{path});
    }
    {
        const allocator = std.heap.page_allocator;
        const path = try findSocketPathAlloc(allocator);
        std.debug.print("found socket path: {s}\n", .{path});
    }
}
