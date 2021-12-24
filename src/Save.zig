const std = @import("std");

const Save = @This();

progress: usize,
file: []const u8,

pub fn open(str: []const u8) !Save {
    if (std.fs.cwd().openFile(str, .{})) |imgfile| {
        defer imgfile.close();
        const reader = imgfile.reader();
        const savedprogress = try reader.readIntNative(usize);

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
    try writer.writeIntNative(usize, self.progress);
}

pub fn increment(self: *Save, value: i32) void {
    if (value < 0 and self.progress <= -value) {
        self.progress = 0;
    } else {
        self.progress = @intCast(usize, @intCast(i64, self.progress) + value);
    }
}
