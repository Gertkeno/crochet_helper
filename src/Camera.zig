const std = @import("std");
const curses = @import("ncurses.zig");
usingnamespace @import("Image.zig");

pub const Camera = struct {
    offset: curses.Vec,
    ctx: *const curses.Context,
    img: Image,

    progress: usize,

    pub fn init(ctx: *const curses.Context, image: Image) Camera {
        return Camera{
            .offset = curses.Vec{
                .x = 0,
                .y = 0,
            },
            .progress = 0,

            .ctx = ctx,
            .img = image,
        };
    }

    pub fn draw_all(self: Camera) void {
        const s = self.img.stride;
        var x: i32 = 0;
        var y: i32 = 0;
        const ww = self.ctx.window._maxx;
        const wh = self.ctx.window._maxy;
        const iw = @intCast(i32, self.img.width);

        self.ctx.move(curses.Vec.zero());

        while (x + y * iw < self.img.width * self.img.height and y < wh) : ({
            x += 1;
            if (x >= iw or x >= ww) {
                x = 0;
                y += 1;
                self.ctx.move(curses.Vec{ .x = x, .y = y });
            }
        }) {
            const ox = x + self.offset.x;
            const oy = y + self.offset.y;
            if (ox < 0 or ox >= self.img.width) {
                continue;
            } else if (oy < 0 or oy >= self.img.height) {
                continue;
            }

            const pos = ox + oy * iw;
            const i = @intCast(usize, pos) * s;
            const pixel = curses.Color.from_slice(self.img.pixels[i .. i + s]);
            self.ctx.fill(pixel, self.progress > pos);
        }
    }

    pub fn add_progress(self: *Camera, comptime amount: comptime_int) void {
        if (amount < 0) {
            if (self.progress > -amount) {
                // wtf zig...
                self.progress -= -amount;
            } else {
                self.progress = 0;
            }
        } else {
            if (self.progress < self.max() - amount) {
                self.progress += amount;
            } else {
                self.progress = self.max();
            }
        }
    }

    fn max(self: Camera) usize {
        return self.img.width * self.img.height;
    }
};
