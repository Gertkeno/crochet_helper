const time = @import("std").time;
const Context = @import("Context.zig");
const string = []const u8;

const Self = @This();

stamp: i64,
texti: u8,

const PopupSeconds = 25;
const PopupMilliSeconds = PopupSeconds * time.ms_per_s;
const PopupTexts = [_]string{ "-10", "-1", "+1", "+10", "???" };

fn valid(self: Self, against: i64) bool {
    return against - self.stamp < PopupMilliSeconds;
}

pub fn draw(self: []const Self, ctx: Context, ymax: i32) void {
    const stamp = time.milliTimestamp();
    var ybump: i32 = 32;
    for (self) |s| {
        if (s.valid(stamp)) {
            const text: string = PopupTexts[s.texti];
            const alpha: u8 = @intCast(u8, 255 - @divTrunc((stamp - s.stamp) * 255, PopupMilliSeconds));
            ctx.font.setAlphaMod(alpha) catch {};

            ctx.print_slice(text, 0, ymax - ybump);
            ybump += 32;
        }
    }

    ctx.font.setAlphaMod(0xFF) catch {};
}

pub fn push(self: []Self, inc: i32) void {
    const stamp = time.milliTimestamp();
    for (self) |*s| {
        if (!s.valid(stamp)) {
            s.stamp = stamp;
            s.texti = switch (inc) {
                -10 => 0,
                -1 => 1,
                1 => 2,
                10 => 3,
                else => 4,
            };
            break;
        }
    }
}
