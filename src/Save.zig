const std = @import("std");

pub const Save = struct {
    progress: usize,
    file: []const u8,

    fn open_maybe(str: []const u8) !?std.fs.File {
        if (std.fs.cwd().openFile(str, .{})) |imgfile| {
            return imgfile;
        } else |err| {
            if (err == error.FileNotFound) {
                return null;
            } else {
                return err;
            }
        }
    }

    pub fn open(str: []const u8) !Save {
        if (try open_maybe(str)) |imgfile| {
            defer imgfile.close();
            const reader = imgfile.reader();
            const savedprogress = try reader.readIntNative(usize);

            return Save{
                .progress = savedprogress,
                .file = str,
            };
        } else {
            return Save{
                .progress = 0,
                .file = str,
            };
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
};
