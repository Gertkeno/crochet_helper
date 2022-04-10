const std = @import("std");
const date = @import("date").DateTime;
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
        try writer.writeAll("Date, Duration (seconds), stitches\n");
    } else {
        try file.seekTo(end);
    }

    const startDate = date.initUnix(@intCast(u63, self.startTime));

    try writer.print("{YY-MM-DD HH.mm}, {d}, {d}\n", .{ startDate, duration, netprogress });
}
