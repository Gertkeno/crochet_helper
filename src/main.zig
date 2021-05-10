const std = @import("std");
const sdl = @import("SDL2.zig");
usingnamespace @import("Camera.zig");

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

        var camera = Camera.init(&ctx, img);

        var progressCounter = std.ArrayList(u8).init(allocator);
        defer progressCounter.deinit();

        while (true) {
            ctx.clear();

            // img drawing
            camera.draw_all();

            // Progress Counter
            const lineprogress = camera.progress % img.width;
            const heightprogress = camera.progress / img.width;
            const colorprogress = std.math.min(camera.img.last_color_change(camera.progress), lineprogress);
            try progressCounter.writer().print("T {:.>6}/{:.>6} Y {:.>4} L {:.>4} C {:.>4}", .{ camera.progress, camera.max(), heightprogress, lineprogress, colorprogress });
            ctx.print_slice(progressCounter.items);
            progressCounter.shrink(0);

            ctx.swap();

            switch (ctx.get_char() orelse ' ') {
                'q' => {
                    break;
                },
                'w' => {
                    camera.offset.y -= 1;
                },
                's' => {
                    camera.offset.y += 1;
                },
                'a' => {
                    camera.offset.x -= 1;
                },
                'd' => {
                    camera.offset.x += 1;
                },
                // progress shifts
                'z' => {
                    camera.add_progress(-10);
                },
                'x' => {
                    camera.add_progress(-1);
                },
                'c' => {
                    camera.add_progress(1);
                },
                'v' => {
                    camera.add_progress(10);
                },
                'b' => {
                    camera.add_progress(25);
                },
                else => {},
            }
        }
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
