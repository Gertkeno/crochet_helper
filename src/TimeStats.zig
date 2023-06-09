const std = @import("std");
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

pub fn yyyy_mm_dd_hh(timestamp: i64, buf: []u8) ![]const u8 {
    const es = std.time.epoch.EpochSeconds{
        .secs = @intCast(u64, timestamp),
    };
    const ds = es.getDaySeconds();
    const hours = ds.getHoursIntoDay();
    const minutes = ds.getMinutesIntoHour();

    const ey = es.getEpochDay().calculateYearDay();
    const em = ey.calculateMonthDay();

    const year = ey.year;
    const month = em.month.numeric();
    const day = em.day_index + 1;

    return try std.fmt.bufPrint(buf, "{d:0>4}/{d:0>2}/{d:0>2} {d:0>2}:{d:0>2}", .{
        year,
        month,
        day,
        hours,
        minutes,
    });
}

pub fn write_append(self: Self, currentProgress: u64) !void {
    if (currentProgress < self.startProgress) {
        log.debug("No stats generated, negative progress", .{});
        return;
    }

    const currentTime = std.time.timestamp();
    const duration = currentTime - self.startTime;
    const netprogress = currentProgress - self.startProgress;
    if (netprogress <= 0 or duration <= 0) {
        log.debug("No stats generated, no progress", .{});
        return;
    }

    log.info("Total progress = {d}", .{netprogress});
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

    var dateBuf: [16]u8 = undefined;
    const date = try yyyy_mm_dd_hh(self.startTime, &dateBuf);

    const writer = file.writer();
    try writer.print("{s}, {d}, {d}\n", .{ date, duration, netprogress });
}
