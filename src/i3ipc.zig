pub const Connection = @import("i3ipc/Connection.zig");
pub const Protocol = @import("i3ipc/Protocol.zig");

const finding = @import("i3ipc/socketpath.zig");
pub const findSocketPath = finding.findSocketPath;
pub const findSocketPathAlloc = finding.findSocketPathAlloc;
