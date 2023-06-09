const std = @import("std");
const Instance = @import("Instance.zig");
const Context = @import("Context.zig");

fn drop_loop(ctx: Context, allocator: std.mem.Allocator) ?Instance {
    while (true) {
        const filename = ctx.wait_for_file() orelse return null;

        if (Instance.init(ctx, filename, allocator, .{})) |instance| {
            return instance;
        } else |err| {
            const errstr = switch (err) {
                error.TextureError => "Probably a unsupported image format, try again with a JPEG or PNG",
                error.OutOfMemory => "Ran out of memory!",
                else => @errorName(err), //"Unkown error, check command prompt if available.",
            };

            std.log.warn("drop error: {s}", .{errstr});
            ctx.error_box(errstr);
            continue;
        }
    }
}

const help_message =
    \\Usage: crochet_helper [OPTIONS] [FILE.(jpg|png)]
    \\
    \\Options:
    \\  -nostats     do not write to crochet_stats.csv
    \\  -nosave      do not write .filename.(jpg|png).save or crochet_stats.csv
    \\
;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var imgFilename: ?[:0]const u8 = null;
    var instanceSettings = Instance.Settings{};

    const stdout = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.skip();
    while (args.next()) |arg| {
        if (arg.len != 0 and arg[0] == '-') {
            if (std.mem.eql(u8, "nosave", arg[1..])) {
                instanceSettings.save_progress = false;
                instanceSettings.time_stats = false;
                std.log.warn("Not saving progress...", .{});
            } else if (std.mem.eql(u8, "nostats", arg[1..])) {
                instanceSettings.time_stats = false;
            } else if (arg[1] == 'h') {
                try stdout.writeAll(help_message);
                return;
            } else {
                std.log.warn("unkown option \"{s}\"", .{arg});
                return;
            }
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

        var instance = try Instance.init(ctx, img, allocator, instanceSettings);
        defer instance.deinit();

        instance.main_loop();
    } else {
        std.log.debug("No filename argument, starting drop file loop...", .{});
        var instance = drop_loop(ctx, allocator) orelse return;
        defer instance.deinit();

        instance.main_loop();
    }
}
