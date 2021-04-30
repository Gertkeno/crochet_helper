const std = @import("std");
usingnamespace @import("Image.zig");
usingnamespace @import("ncurses.zig");

pub const Stitch = struct {
    char: u8,
    color: u8,

    pub fn eql(lhs: Stitch, rhs: Stitch) bool {
        return lhs.char == rhs.char and lhs.color == rhs.color;
    }
};

fn mag_to_char(mag: u8) u8 {
    return switch (mag) {
        0x00...0x10 => ' ',
        0x11...0x30 => '.',
        0x31...0x50 => '_',
        0x51...0x70 => ':',
        0x71...0x90 => 'c',
        0x91...0xB0 => '7',
        0xB1...0xD0 => 'Q',
        0xD1...0xFF => '@',
    };
}

fn stitch_image(img: Image, allocator: *std.mem.Allocator) ![]Stitch {
    var output = std.ArrayList(Stitch).init(allocator);
    errdefer output.deinit();

    var i: usize = 0;
    while (i < img.pixels.len) : (i += img.stride) {
        const pixel = Color.from_slice(img.pixels[i .. i + img.stride]);

        const st = Stitch{
            .char = mag_to_char(pixel.opposite_magnitude()),
            .color = @enumToInt(pixel.closest_name()),
        };

        try output.append(st);
    }

    return output.toOwnedSlice();
}

pub const Stitches = struct {
    width: usize,
    height: usize,
    pixels: []Stitch,
    allocator: *std.mem.Allocator,

    pub fn from_image(img: Image, allocator: *std.mem.Allocator) !Stitches {
        return Stitches{
            .width = img.width,
            .height = img.height,
            .pixels = try stitch_image(img, allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Stitches) void {
        self.allocator.free(self.pixels);
    }

    pub fn last_color_change(self: Stitches, pos: usize) usize {
        const x = pos % self.width;
        const y = pos / self.width;
        const p = self.pixels;
        if (y & 1 == 0) {
            var i: usize = 1;
            while (p[pos].eql(p[pos - i])) : (i += 1) {}
            return i - 1;
        } else {
            const start = y * self.width + self.width - x;
            var i: usize = 1;
            while (p[start].eql(p[start + i])) : (i += 1) {}
            return i;
        }
    }
};
