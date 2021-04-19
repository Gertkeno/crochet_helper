const std = @import("std");
const c = @cImport({
    @cInclude("ncurses.h");
});

pub const Color = struct {
    underlying: [3]u8,

    pub fn from_slice(color: []const u8) Color {
        return Color{ .underlying = [3]u8{ color[0], color[1], color[2] } };
    }

    pub fn from_mask(color: u24) Color {
        const r: u8 = @intCast(u8, (color & 0xFF0000) >> 16);
        const g: u8 = @intCast(u8, (color & 0x00FF00) >> 8);
        const b: u8 = @intCast(u8, (color & 0x0000FF) >> 0);
        return Color{ .underlying = [3]u8{ r, g, b } };
    }

    pub fn magnitude(self: Color) u8 {
        var acc: u24 = 0;
        for (self.underlying) |b| {
            acc += b;
        }
        return @intCast(u8, acc / 3);
    }

    fn high_bits(self: Color) u3 {
        var high: u8 = 0;
        var eqls: u3 = 0;
        for (self.underlying) |byte| {
            if (high < byte) {
                high = byte;
            }
        }

        for (self.underlying) |byte, n| {
            if (high == byte) {
                eqls |= @as(u3, 1) << @intCast(u2, n);
            }
        }

        return eqls;
    }

    pub fn inverse_magnitude(self: Color) u8 {
        return switch (self.high_bits()) {
            0b001 => (self.underlying[1] + self.underlying[2]) / 2,
            0b010 => (self.underlying[0] + self.underlying[2]) / 2,
            0b100 => (self.underlying[0] + self.underlying[1]) / 2,
            0b011 => self.underlying[2],
            0b101 => self.underlying[1],
            0b110 => self.underlying[0],
            0b111 => self.magnitude(),
            0b000 => 0,
        };
    }

    pub fn closest_name(self: Color) Name {
        return switch (self.high_bits()) {
            0b001 => .Red,
            0b010 => .Green,
            0b100 => .Blue,
            0b110 => .Cyan,
            0b101 => .Magenta,
            0b011 => .Yellow,
            0b111 => .White,
            else => unreachable,
        };
    }

    pub const Name = enum {
        Red,
        Green,
        Blue,
        Yellow,
        Magenta,
        Cyan,
        White,
        Black,
    };
};

test "color from mask" {
    const tc = Color.from_mask(0xFF1A07);
    std.testing.expectEqual(@as(u8, 0xFF), tc.underlying[0]);
    std.testing.expectEqual(@as(u8, 0x1A), tc.underlying[1]);
    std.testing.expectEqual(@as(u8, 0x07), tc.underlying[2]);
}

test "highest color" {
    const r = Color.from_mask(0xFF0000);
    std.testing.expectEqual(Color.Name.Red, r.closest_name());
    std.testing.expectEqual(@as(u8, 0), r.inverse_magnitude());
}

pub const Vec = struct {
    x: i32,
    y: i32,
};

pub const Context = struct {
    window: *c.WINDOW,
    offset: Vec,

    pub fn init() Context {
        const window = c.initscr();
        _ = c.start_color();
        _ = c.cbreak();
        _ = c.noecho();

        _ = c.init_pair(@enumToInt(Color.Name.Red), c.COLOR_WHITE, c.COLOR_RED);
        _ = c.init_pair(@enumToInt(Color.Name.Green), c.COLOR_WHITE, c.COLOR_GREEN);
        _ = c.init_pair(@enumToInt(Color.Name.Blue), c.COLOR_WHITE, c.COLOR_BLUE);
        _ = c.init_pair(@enumToInt(Color.Name.Yellow), c.COLOR_BLACK, c.COLOR_YELLOW);
        _ = c.init_pair(@enumToInt(Color.Name.Magenta), c.COLOR_BLACK, c.COLOR_MAGENTA);
        _ = c.init_pair(@enumToInt(Color.Name.Cyan), c.COLOR_BLACK, c.COLOR_CYAN);
        _ = c.init_pair(@enumToInt(Color.Name.White), c.COLOR_BLACK, c.COLOR_WHITE);
        _ = c.init_pair(@enumToInt(Color.Name.Black), c.COLOR_WHITE, c.COLOR_BLACK);

        return Context{ .window = window, .offset = Vec{ .x = 0, .y = 0 } };
    }

    pub fn deinit(self: *Context) void {
        _ = c.endwin();
    }

    pub fn fill(self: Context, color: Color, mark: bool) void {
        const cint = @enumToInt(color.closest_name());
        const mag = color.inverse_magnitude();

        _ = c.wattron(self.window, cint);
        _ = c.waddch(self.window, if (mark) 'X' else mag);
        _ = c.wattroff(self.window, cint);
    }

    pub fn move(self: Color, pos: Vec) void {
        _ = c.wmove(self.window, pos.x, pos.y);
    }
};
