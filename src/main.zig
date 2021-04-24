const std = @import("std");
const curse = @import("ncurses.zig");
usingnamespace @import("Image.zig");
usingnamespace @import("Camera.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var imgbuffer: ?Image = null;
    var imgfilename: ?[]const u8 = null;

    var args = std.process.args();
    _ = args.skip();
    while (args.nextPosix()) |arg| {
        if (arg.len != 0 and arg[0] == '-') {
            // options?
            std.log.warn("unkown option \"{s}\"", .{arg});
            return;
        } else {
            if (imgbuffer != null) {
                std.log.warn("a file has already been read: \"{}\" ignoring \"{}\"", .{ imgfilename.?, arg });
                continue;
            }

            imgbuffer = try Image.png(arg, allocator);
            std.log.info("png size {}x{}, d{}", .{ imgbuffer.?.width, imgbuffer.?.height, imgbuffer.?.stride });
            imgfilename = try allocator.dupe(u8, arg);
        }
    }

    if (imgbuffer) |img| {
        var ctx = curse.Context.init();
        defer ctx.deinit();

        var camera = Camera.init(&ctx, img);

        //ctx.fill(curse.Color.from_slice(&[_]u8{ 0xFF, 0x7F, 0x00 }), false);
        //ctx.fill(curse.Color.from_slice(&[_]u8{ 0xFF, 0x7F, 0x00 }), false);
        //ctx.fill(curse.Color.from_slice(&[_]u8{ 0xFF, 0x7F, 0x00 }), false);
        //ctx.fill(curse.Color.from_slice(&[_]u8{ 0xFF, 0x7F, 0x00 }), false);
        while (true) {
            ctx.clear();
            camera.draw_all();
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
                else => {},
            }
        }
    } else {
        std.log.err("No file specified!", .{});
    }
}
