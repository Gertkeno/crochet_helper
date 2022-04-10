const std = @import("std");
const Self = @This();

startTime: i64,
startProgress: u64,

pub fn start(currentProgress: u64) Self {
    const currentTime = std.time.timestamp();

    return Self{
        .startTime = currentTime,
        .startProgress = currentProgress,
    };
}

pub fn write_append(self: Self, currentProgress: u64) !void {
    const currentTime = std.time.timestamp();
    const duration = currentTime - self.startTime;
    const netprogress = currentProgress - self.startProgress;

    const file = try std.fs.cwd().createFile("crochet_stats.csv", .{ .truncate = false });
    defer file.close();
    const writer = file.writer();

    const end = try file.getEndPos();
    if (end == 0) {
        std.log.debug("New stats file, adding legend line", .{});
        try writer.writeAll("Duration (seconds), stitches\n");
    } else {
        try file.seekTo(end);
    }

    try writer.print("{d}, {d}\n", .{ duration, netprogress });
}
