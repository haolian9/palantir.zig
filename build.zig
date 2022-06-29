const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    {
        const exe = b.addExecutable("palantir", "main.zig");
        exe.setBuildMode(mode);
        exe.strip = false;
        exe.single_threaded = true;
        exe.install();
    }
}
