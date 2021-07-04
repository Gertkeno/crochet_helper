const std = @import("std");
usingnamespace @import("Instance.zig");
usingnamespace @import("Context.zig");

fn drop_loop(ctx: Context, allocator: *std.mem.Allocator) ?Instance {
    while (true) {
        const filename = ctx.wait_for_file();

        if (filename) |img| {
            var instance = Instance.init(ctx, img, allocator) catch |err| {
                const errstr = switch (err) {
                    error.CreationFailure => "Probably a unsupported image format, try again with a JPEG or PNG",
                    error.OutOfMemory => "Ran out of memory!",
                    else => "Unkown error, check command prompt if available.",
                };

                ctx.error_box(errstr);
                continue;
            };

            return instance;
        } else {
            return null;
        }
    }
}

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
        var instance = drop_loop(ctx, allocator) orelse return;
        defer instance.deinit();

        instance.main_loop();
    }
}
