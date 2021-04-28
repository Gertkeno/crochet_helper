const std = @import("std");

pub const Save = struct {
    savedProgress: usize,
    file: []const u8,

    fn open_maybe(str: []const u8) !?std.fs.File {
        if (std.fs.cwd().openFile(str, .{})) |imgfile| {
            return imgfile;
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            } else {
                return null;
            }
        }
    }

    pub fn open(str: []const u8) !?Save {
        if (try open_maybe(str)) |imgfile| {
            defer imgfile.close();
            const reader = imgfile.reader();
            const savedProgress = try reader.readIntNative(usize);

            return Save{
                .savedProgress = savedProgress,
                .file = str,
            };
        } else {
            return Save{
                .savedProgress = 0,
                .file = str,
            };
        }
    }

    pub fn close(self: Save, newValue: usize) !void {
        if (std.fs.cwd().createFile(self.file, .{})) |imgfile| {
            defer imgfile.close();
            const writer = imgfile.writer();
            try writer.writeIntNative(usize, newValue);
        } else |err| {
            return err;
        }
    }
};
