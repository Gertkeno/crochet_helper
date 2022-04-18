const std = @import("std");
const date = @import("date").DateTime;
const Self = @This();

const log = std.log.scoped(.TimeStats);

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
    if (netprogress <= 0 or duration <= 0) {
        log.debug("No stats generated, no progress", .{});
        return;
    }

    log.info("Average seconds per stitch = {d}", .{@intToFloat(f64, duration) / @intToFloat(f64, netprogress)});

    const file = try std.fs.cwd().createFile("crochet_stats.csv", .{ .truncate = false });
    defer file.close();

    const end = try file.getEndPos();
    if (end == 0) {
        log.debug("New stats file, adding legend line", .{});
        try file.writeAll("Date, Duration (seconds), stitches\n");
    } else {
        try file.seekTo(end);
    }

    const startDate = date.initUnix(@intCast(u64, self.startTime));

    const writer = file.writer();
    try writer.print("{YYYY/MM/DD HH}:{d:0>2}, {d}, {d}\n", .{ startDate, startDate.minutes, duration, netprogress });
}
