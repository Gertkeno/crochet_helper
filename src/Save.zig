const std = @import("std");

const Save = @This();

progress: u64,
file: []const u8,

pub fn open(str: []const u8) !Save {
    if (std.fs.cwd().openFile(str, .{})) |imgfile| {
        defer imgfile.close();
        const reader = imgfile.reader();
        const savedprogress = try reader.readIntLittle(u64);

        return Save{
            .progress = savedprogress,
            .file = str,
        };
    } else |err| {
        if (err == error.FileNotFound) {
            return Save{
                .progress = 0,
                .file = str,
            };
        } else {
            return err;
        }
    }
}

pub fn write(self: Save) !void {
    const imgfile = try std.fs.cwd().createFile(self.file, .{});
    defer imgfile.close();
    const writer = imgfile.writer();
    try writer.writeIntLittle(u64, self.progress);
}

pub fn increment(self: *Save, value: i32) void {
    if (value < 0 and self.progress <= -value) {
        self.progress = 0;
    } else {
        self.progress = @intCast(u64, @intCast(i64, self.progress) + value);
    }
}
