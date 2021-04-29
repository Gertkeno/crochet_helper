const std = @import("std");
const curse = @import("ncurses.zig");
usingnamespace @import("Image.zig");
usingnamespace @import("Camera.zig");
usingnamespace @import("Save.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var imgbuffer: ?Image = null;
    var imgSave: ?Save = null;

    var args = std.process.args();
    _ = args.skip();
    while (args.nextPosix()) |arg| {
        if (arg.len != 0 and arg[0] == '-') {
            // options?
            std.log.warn("unkown option \"{s}\"", .{arg});
            return;
        } else {
            if (imgbuffer != null) {
                std.log.warn("a file has already been read, ignoring \"{}\"", .{arg});
                continue;
            }

            imgbuffer = try Image.png(arg, allocator);
            std.log.info("png size {}x{}, d{}", .{ imgbuffer.?.width, imgbuffer.?.height, imgbuffer.?.stride });
            const a = [_][]const u8{ arg, ".save" };
            const imgSaveFilename = try std.mem.concat(allocator, u8, &a);
            imgSave = try Save.open(imgSaveFilename);
        }
    }

    if (imgbuffer) |img| {
        var ctx = curse.Context.init();
        defer ctx.deinit();

        var camera = Camera.init(&ctx, img);
        if (imgSave) |save| {
            camera.progress = save.savedProgress;
        }

        var progressCounter = std.ArrayList(u8).init(allocator);
        defer progressCounter.deinit();

        while (true) {
            ctx.clear();
            camera.draw_all();
            try progressCounter.writer().print("C {:.>6}", .{camera.progress});
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

        // save and close
        if (imgSave) |save| {
            try save.close(camera.progress);
            allocator.free(save.file);
        }
        img.deinit();
    } else {
        std.log.err("No file specified!", .{});
    }
}
