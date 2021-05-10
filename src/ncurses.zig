const std = @import("std");
const c = @cImport({
    @cInclude("ncurses.h");
});

fn eql_within(lhs: i32, rhs: i32, err: i32) bool {
    if (lhs < rhs - err) {
        return false;
    } else if (lhs > rhs + err) {
        return false;
    } else {
        return true;
    }
}

pub const Color = struct {
    underlying: []const u8,

    pub fn from_slice(color: []const u8) Color {
        return Color{ .underlying = color[0..3] };
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
            if (eql_within(byte, high, 8)) {
                eqls |= @as(u3, 1) << @intCast(u2, n);
            }
        }

        if (eqls == 0b111 and high < 0x7F) {
            return 0;
        }

        return eqls;
    }

    pub fn opposite_magnitude(self: Color) u8 {
        return switch (self.high_bits()) {
            0b001 => (self.underlying[1] / 2 + self.underlying[2] / 2),
            0b010 => (self.underlying[0] / 2 + self.underlying[2] / 2),
            0b100 => (self.underlying[0] / 2 + self.underlying[1] / 2),
            0b011 => self.underlying[2],
            0b101 => self.underlying[1],
            0b110 => self.underlying[0],
            0b111 => 255 - self.magnitude(),
            0b000 => self.magnitude(),
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
            0b000 => .Black,
        };
    }

    pub const Name = enum(u8) {
        Red = 1,
        Green,
        Blue,
        Yellow,
        Magenta,
        Cyan,
        White,
        Black,
    };
};

test "highest color" {
    const r = Color.from_slice(&[_]u8{ 0xFF, 0, 0 });
    std.testing.expectEqual(Color.Name.Red, r.closest_name());
    std.testing.expectEqual(@as(u8, 0), r.opposite_magnitude());
}

pub const Vec = struct {
    x: i32,
    y: i32,

    pub fn zero() Vec {
        return Vec{ .x = 0, .y = 0 };
    }
};

pub const Context = struct {
    window: *c.WINDOW,
    offset: Vec,

    pub fn init() Context {
        const window = c.initscr();
        _ = c.cbreak();
        _ = c.noecho();
        _ = c.start_color();

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

    pub fn fill(self: Context, color: u8, char: u8) void {
        _ = c.wattron(self.window, c.COLOR_PAIR(color));
        _ = c.waddch(self.window, char);
    }

    pub fn get_char(self: Context) ?u8 {
        const ch = c.wgetch(self.window);

        if (ch == c.ERR) {
            return null;
        }

        if (ch < 32 or ch > 127) {
            return null;
        }

        return @intCast(u8, ch);
    }

    pub fn print_slice(self: Context, str: []const u8) void {
        _ = c.wattron(self.window, c.COLOR_PAIR(@enumToInt(Color.Name.White)));
        for (str) |ch| {
            _ = c.waddch(self.window, ch);
        }
    }

    pub fn move(self: Context, pos: Vec) void {
        _ = c.wmove(self.window, pos.y, pos.x);
    }

    pub fn swap(self: Context) void {
        _ = c.wrefresh(self.window);
    }

    pub fn clear(self: Context) void {
        _ = c.werase(self.window);
    }
};
