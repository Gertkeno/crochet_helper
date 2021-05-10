const std = @import("std");
const curses = @import("ncurses.zig");
usingnamespace @import("Stitch.zig");

pub const Camera = struct {
    offset: curses.Vec,
    ctx: *const curses.Context,
    img: Stitches,

    progress: usize,

    pub fn init(ctx: *const curses.Context, image: Stitches) Camera {
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

    fn xoffsetism(self: Camera) i32 {
        return if (self.offset.x > 0) 0 else -self.offset.x;
    }

    pub fn draw_all(self: Camera) void {
        var x: i32 = 0;
        var y: i32 = 0;
        const ww = self.ctx.window._maxx;
        const wh = self.ctx.window._maxy;
        const iw = @intCast(i32, self.img.width);

        self.ctx.move(curses.Vec{ .x = self.xoffsetism(), .y = 0 });

        while (x + y * iw < self.img.width * self.img.height and y < wh) : ({
            x += 1;
            // drawing overwidth, next line
            if (x >= iw or x >= ww) {
                x = 0;
                y += 1;
                self.ctx.move(curses.Vec{ .x = self.xoffsetism(), .y = y });
            }
        }) {
            const ox = x + self.offset.x;
            const oy = y + self.offset.y;
            if (ox < 0 or ox >= self.img.width) {
                continue;
            } else if (oy < 0) {
                continue;
            } else if (oy >= self.img.height) {
                break;
            }

            const pos = ox + oy * iw;
            const i = @intCast(usize, pos);

            const pixel = self.img.pixels[i];
            // even lines marked backwards for zig-zag motion
            const marked = self.progress > if (oy & 1 == 0) pos else oy * iw + iw - ox - 1;
            self.ctx.fill(pixel.color, if (marked) 'X' else pixel.char);
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

    pub fn max(self: Camera) usize {
        return self.img.width * self.img.height;
    }
};
