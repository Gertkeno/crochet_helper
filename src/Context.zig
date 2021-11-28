const std = @import("std");
const c = @import("c.zig");
usingnamespace @import("Texture.zig");

const font_franklin = @embedFile("franklin.bmp");

pub const ContextError = error{
    InitError,
    WindowError,
    RendererError,
    TextureError,
};

pub const Context = struct {
    window: *c.SDL_Window,
    render: *c.SDL_Renderer,
    font: *c.SDL_Texture,
    offset: struct {
        x: f32 = 0,
        y: f32 = 0,
        z: i32 = 8,
    } = .{},

    const HintDotsCount = 10;

    pub fn init() !Context {
        // SDL2 init
        if (c.SDL_Init(c.SDL_INIT_EVENTS) != 0) {
            std.log.err("Failed to init SDL2: {s}", .{c.SDL_GetError()});
            return ContextError.InitError;
        }
        _ = c.IMG_Init(c.IMG_INIT_JPG | c.IMG_INIT_PNG);
        errdefer c.SDL_Quit();
        errdefer c.IMG_Quit();

        const wflags = c.SDL_WINDOW_RESIZABLE;
        const pos = c.SDL_WINDOWPOS_CENTERED;
        const window = c.SDL_CreateWindow("gert's crochet helper", pos, pos, 1000, 600, wflags) orelse {
            std.log.err("Failed to create Window: {s}", .{c.SDL_GetError()});
            return ContextError.WindowError;
        };
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse
            c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_SOFTWARE) orelse
            {
            std.log.err("Failed to create renderer: {s}", .{c.SDL_GetError()});
            return ContextError.RendererError;
        };
        errdefer c.SDL_DestroyRenderer(renderer);

        const fsurf: *c.SDL_Surface = c.SDL_LoadBMP_RW(c.SDL_RWFromConstMem(font_franklin, font_franklin.len), 1) orelse {
            std.log.err("Failed to create font surface from interal image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };
        defer c.SDL_FreeSurface(fsurf);
        _ = c.SDL_SetColorKey(fsurf, c.SDL_TRUE, c.SDL_MapRGB(fsurf.format, 0xFF, 0, 0xFF));
        const ftexture = c.SDL_CreateTextureFromSurface(renderer, fsurf) orelse {
            std.log.err("Failed to create font from internal image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };

        return Context{
            .window = window,
            .render = renderer,
            .font = ftexture,
        };
    }

    pub fn deinit(self: Context) void {
        c.SDL_DestroyRenderer(self.render);
        c.SDL_DestroyWindow(self.window);
        c.IMG_Quit();
        c.SDL_Quit();
    }

    //////////////////
    // FONT DRAWING //
    //////////////////
    pub fn print_slice(self: Context, str: []const u8, x: i32, y: i32) void {
        var ox: i32 = x;
        var oy: i32 = y;
        for (str) |char, n| {
            if (char == '\n') {
                ox = x;
                oy += 32;
                continue;
            } else if (std.ascii.isPrint(char)) {
                const cx = @intCast(i32, char % 16) * 32;
                const cy = @intCast(i32, char / 16) * 32;
                const srcRect = c.SDL_Rect{
                    .x = cx,
                    .y = cy,
                    .w = 32,
                    .h = 32,
                };
                const dstRect = c.SDL_Rect{
                    .x = ox,
                    .y = oy,
                    .w = 32,
                    .h = 32,
                };
                _ = c.SDL_RenderCopy(self.render, self.font, &srcRect, &dstRect);
            }
            ox += 18;
        }
    }

    /////////////////////
    // REGUALR DRAWING //
    /////////////////////
    pub fn set_color(self: Context, r: u8, g: u8, b: u8) void {
        _ = c.SDL_SetRenderDrawColor(self.render, r, g, b, 0xFF);
    }

    pub fn draw_line(self: Context, x1: c_int, y1: c_int, x2: c_int) void {
        _ = c.SDL_RenderDrawLine(self.render, x1, y1, x2, y1);
    }

    pub fn clear(self: Context) void {
        self.set_color(0, 0, 0);
        if (c.SDL_RenderClear(self.render) != 0) {
            std.log.notice("Failed to clear renderer: {s}", .{c.SDL_GetError()});
        }
    }

    pub fn swap(self: Context) void {
        c.SDL_RenderPresent(self.render);
    }

    fn set_inverse_color(self: Context, texture: Texture, x: usize, y: usize) void {
        const pos = x + y * texture.width;
        const pixel = texture.pixel_at_index(pos);
        const r = 255 - pixel[0];
        const g = 255 - pixel[1];
        const b = 255 - pixel[2];
        self.set_color(r, g, b);
    }

    pub fn draw_all(self: Context, texture: Texture, progress: usize) void {
        // draw texture
        const drawRect = c.SDL_Rect{
            .x = @floatToInt(i32, self.offset.x),
            .y = @floatToInt(i32, self.offset.y),
            .w = @intCast(i32, texture.width) * self.offset.z,
            .h = @intCast(i32, texture.height) * self.offset.z,
        };
        if (c.SDL_RenderCopy(self.render, texture.handle, null, &drawRect) != 0) {
            std.log.notice("Failed to render to screen", .{});
        }

        // draw fully complete lines
        self.set_color(0xFF, 0, 0);
        var fullLines: usize = progress / texture.width;
        while (fullLines > 0) : (fullLines -= 1) {
            const x = @floatToInt(c_int, self.offset.x);
            const y = @floatToInt(c_int, self.offset.y) + @intCast(c_int, fullLines) * self.offset.z - @divTrunc(self.offset.z, 2);
            const maxX = @intCast(c_int, texture.width) * self.offset.z;
            self.draw_line(x, y, x + maxX);
        }

        // draw progress
        self.set_color(0xFF, 0, 0x7F);
        const y = progress / texture.width;
        const x = progress % texture.width;
        const oy = @floatToInt(c_int, self.offset.y) + @intCast(c_int, y) * self.offset.z + @divTrunc(self.offset.z, 2);
        if (y & 1 == 0) {
            // left to right
            const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, x) * self.offset.z;
            self.draw_line(@floatToInt(c_int, self.offset.x), oy, ox);

            self.set_color(0, 0xFF, 0);
            var i: u32 = 0;
            while (i < HintDotsCount and x + i < texture.width) : (i += 1) {
                const hintX = ox + (@intCast(i32, i) * self.offset.z) + @divTrunc(self.offset.z, 2);
                self.set_inverse_color(texture, x + i, y);
                _ = c.SDL_RenderDrawPoint(self.render, hintX, oy);
            }
        } else {
            // right to left
            const ow = @floatToInt(c_int, self.offset.x) + @intCast(c_int, texture.width) * self.offset.z;
            const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, texture.width - x) * self.offset.z;
            self.draw_line(ow, oy, ox);

            self.set_color(0, 0xFF, 0);
            var i: u32 = 0;
            while (i < HintDotsCount and x + i < texture.width) : (i += 1) {
                const hintX = ox - (@intCast(i32, i) * self.offset.z) - @divTrunc(self.offset.z, 2);
                self.set_inverse_color(texture, texture.width - x - i - 1, y);
                _ = c.SDL_RenderDrawPoint(self.render, hintX, oy);
            }
        }
    }

    ////////////////
    // DROP EVENT //
    ////////////////
    pub fn wait_for_file(self: Context) ?[:0]const u8 {
        var e: c.SDL_Event = undefined;

        while (true) {
            while (c.SDL_PollEvent(&e) == 1) {
                if (e.type == c.SDL_DROPFILE) {
                    const file = e.drop.file;
                    return std.mem.span(e.drop.file);
                } else if (e.type == c.SDL_DROPTEXT) {
                    self.error_box("Could not understand dropped item, try something else.");
                } else if (e.type == c.SDL_KEYDOWN) {
                    if (e.key.keysym.sym == c.SDLK_F4 and @enumToInt(c.SDL_GetModState()) & c.KMOD_ALT != 0) {
                        return null;
                    }
                } else if (e.type == c.SDL_QUIT) {
                    return null;
                }
            }

            self.clear();
            self.print_slice("Please drag a image onto this window to open it", 20, 80);
            self.swap();
            c.SDL_Delay(33);
        }

        return null;
    }

    pub fn error_box(self: Context, msg: [:0]const u8) void {
        const err = c.SDL_ShowSimpleMessageBox(c.SDL_MESSAGEBOX_ERROR, "Error!", msg, self.window);
        if (err != 0) {
            std.log.err("Error creation failed! msg: \"{s}\" SDL: {s}", .{ msg, c.SDL_GetError() });
        }
    }
};
