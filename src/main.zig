const std = @import("std");
const sdl = @import("SDL2.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var imgFilename: ?[]const u8 = null;

    var args = std.process.args();
    _ = args.skip();
    while (args.nextPosix()) |arg| {
        if (arg.len != 0 and arg[0] == '-') {
            // options?
            std.log.warn("unkown option \"{s}\"", .{arg});
            return;
        } else {
            if (imgFilename != null) {
                std.log.warn("a file has already been read, ignoring \"{}\"", .{arg});
                continue;
            }

            imgFilename = arg;
        }
    }

    if (imgFilename) |img| {
        var ctx = try sdl.Context.init(img, allocator);
        defer ctx.deinit();

        ctx.main_loop(allocator);
    } else {
        std.log.err("No file specified!", .{});
        std.log.notice(
            \\Usage: crochet-helper FILE
            \\only supports png files, produces FILE.save for storing progress
            \\
            \\Status bar info:
            \\T total stitches made / total stitches in project
            \\Y lines done
            \\L stitches since last line
            \\C stitches since last color change
        , .{});
    }
}
