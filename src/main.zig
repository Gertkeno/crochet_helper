const std = @import("std");
usingnamespace @import("Instance.zig");
usingnamespace @import("Context.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    var imgFilename: ?[:0]const u8 = null;

    var args = std.process.args();
    _ = args.skip();
    while (args.next(allocator)) |argerr| {
        const arg = try argerr;
        defer allocator.free(arg);

        if (arg.len != 0 and arg[0] == '-') {
            // options?
            std.log.warn("unkown option \"{s}\"", .{arg});
            return;
        } else {
            if (imgFilename != null) {
                std.log.warn("a file has already been read, ignoring \"{s}\"", .{arg});
                continue;
            }

            imgFilename = try allocator.dupeZ(u8, arg);
        }
    }

    var ctx = try Context.init();
    defer ctx.deinit();

    if (imgFilename) |img| {
        defer allocator.free(img);

        var instance = try Instance.init(ctx, img, allocator);
        defer instance.deinit();

        instance.main_loop();
    } else {
        const filename = ctx.wait_for_file();

        if (filename) |img| {
            var instance = try Instance.init(ctx, img, allocator);
            defer instance.deinit();

            instance.main_loop();
        }
    }
}
