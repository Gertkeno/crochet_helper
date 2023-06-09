const std = @import("std");
const sdl = @import("sdl2");
const Texture = @import("Texture.zig");

const font_franklin = @embedFile("franklin.bmp");

pub const ContextError = error{
    InitError,
    WindowError,
    RendererError,
    TextureError,
};

const Context = @This();

window: sdl.Window,
render: sdl.Renderer,
font: sdl.Texture,
offset: struct {
    x: f32 = 0,
    y: f32 = 0,
    z: i32 = 8,
} = .{},

const HintDotsCount = 10;

pub fn init() !Context {
    // SDL2 init
    try sdl.init(.{ .events = true });
    try sdl.image.init(.{ .png = true, .jpg = true });
    errdefer sdl.quit();
    errdefer sdl.image.quit();

    const wflags = sdl.WindowFlags{
        .resizable = true,
    };
    const pos = sdl.WindowPosition.default;
    const window = try sdl.createWindow("gert's crochet helper", pos, pos, 1000, 600, wflags);
    errdefer window.destroy();

    const renderer = sdl.createRenderer(window, null, .{}) catch try sdl.createRenderer(window, null, .{ .software = true });
    errdefer renderer.destroy();

    const fsurf = try sdl.loadBmpFromConstMem(font_franklin);
    defer fsurf.destroy();
    try fsurf.setColorKey(true, sdl.Color.magenta);
    const ftexture = try sdl.createTextureFromSurface(renderer, fsurf);

    return Context{
        .window = window,
        .render = renderer,
        .font = ftexture,
    };
}

pub fn deinit(self: Context) void {
    self.render.destroy();
    self.window.destroy();

    sdl.image.quit();
    sdl.quit();
}

//////////////////
// FONT DRAWING //
//////////////////
pub fn print_slice(self: Context, str: []const u8, x: i32, y: i32) void {
    var ox: i32 = x;
    var oy: i32 = y;
    for (str) |char| {
        if (char == '\n') {
            ox = x;
            oy += 32;
            continue;
        } else {
            const cx = @intCast(i32, char % 16) * 32;
            const cy = @intCast(i32, char / 16) * 32;
            const srcRect = sdl.Rectangle{
                .x = cx,
                .y = cy,
                .width = 32,
                .height = 32,
            };
            const dstRect = sdl.Rectangle{
                .x = ox,
                .y = oy,
                .width = 32,
                .height = 32,
            };
            self.render.copy(self.font, dstRect, srcRect) catch {};
        }
        ox += 18;
    }
}

/////////////////////
// REGUALR DRAWING //
/////////////////////
pub fn clear(self: Context) void {
    self.render.setColor(sdl.Color.black) catch {};
    self.render.clear() catch {};
}

pub fn swap(self: Context) void {
    self.render.present();
}

fn set_inverse_color(self: Context, texture: Texture, x: usize, y: usize) void {
    const pos = x + y * texture.width;
    const pixel = texture.pixel_at_index(pos);
    const r = 255 - pixel[0];
    const g = 255 - pixel[1];
    const b = 255 - pixel[2];
    self.render.setColorRGB(r, g, b) catch {};
}

pub fn draw_all(self: Context, texture: Texture, progress: usize) void {
    // draw texture
    const drawRect = sdl.Rectangle{
        .x = @floatToInt(i32, self.offset.x),
        .y = @floatToInt(i32, self.offset.y),
        .width = @intCast(i32, texture.width) * self.offset.z,
        .height = @intCast(i32, texture.height) * self.offset.z,
    };
    self.render.copy(texture.handle, drawRect, null) catch {};

    // draw fully complete lines
    self.render.setColor(sdl.Color.red) catch {};
    var fullLines: usize = progress / texture.width;
    while (fullLines > 0) : (fullLines -= 1) {
        const x = @floatToInt(c_int, self.offset.x);
        const y = @floatToInt(c_int, self.offset.y) + @intCast(c_int, fullLines) * self.offset.z - @divTrunc(self.offset.z, 2);
        const maxX = @intCast(c_int, texture.width) * self.offset.z;
        self.render.drawLine(x, y, x + maxX, y) catch {};
    }

    // draw progress
    self.render.setColorRGB(0xFF, 0, 0x7F) catch {};
    const y = progress / texture.width;
    if (y >= texture.height) {
        return;
    }
    const x = progress % texture.width;
    const oy = @floatToInt(c_int, self.offset.y) + @intCast(c_int, y) * self.offset.z + @divTrunc(self.offset.z, 2);
    if (y & 1 == 0) {
        // left to right
        const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, x) * self.offset.z;
        self.render.drawLine(@floatToInt(i32, self.offset.x), oy, ox, oy) catch {};

        var i: u32 = 0;
        while (i < HintDotsCount and x + i < texture.width) : (i += 1) {
            const hintX = ox + (@intCast(i32, i) * self.offset.z) + @divTrunc(self.offset.z, 2);
            self.set_inverse_color(texture, x + i, y);
            self.render.drawPoint(hintX, oy) catch {};
        }
    } else {
        // right to left
        const ow = @floatToInt(c_int, self.offset.x) + @intCast(c_int, texture.width) * self.offset.z;
        const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, texture.width - x) * self.offset.z;
        self.render.drawLine(ow, oy, ox, oy) catch {};

        var i: u32 = 0;
        while (i < HintDotsCount and x + i < texture.width) : (i += 1) {
            const hintX = ox - (@intCast(i32, i) * self.offset.z) - @divTrunc(self.offset.z, 2);
            self.set_inverse_color(texture, texture.width - x - i - 1, y);
            self.render.drawPoint(hintX, oy) catch {};
        }
    }
}

////////////////
// DROP EVENT //
////////////////
pub fn wait_for_file(self: Context) ?[:0]const u8 {
    while (true) {
        if (sdl.waitEvent()) |e| {
            switch (e) {
                .drop_file => |file| {
                    return std.mem.span(file.file);
                },
                .drop_text => {
                    self.error_box("Could not understand dropped item, try something else. Was text");
                },
                .key_down => |key| {
                    if (key.keycode == .f4 and sdl.getModState().get(sdl.KeyModifierBit.left_alt)) {
                        return null;
                    }
                },
                .quit => {
                    return null;
                },
                else => {},
            }
        } else |_| {
            return null;
        }

        self.clear();
        self.print_slice("Please drag a image onto this window to open it", 20, 80);
        self.swap();
    }
}

pub fn error_box(self: Context, msg: [:0]const u8) void {
    sdl.showSimpleMessageBox(.{ .@"error" = true }, "Error!", msg, self.window) catch {};
}
