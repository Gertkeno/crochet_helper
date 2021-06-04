const std = @import("std");
const c = @import("c.zig");

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
        const window = c.SDL_CreateWindow("gert's crochet helper", pos, pos, 800, 600, wflags) orelse {
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

    pub fn set_color(self: Context, r: u8, g: u8, b: u8) void {
        _ = c.SDL_SetRenderDrawColor(self.render, r, g, b, 0xFF);
    }

    pub fn set_scale(self: Context, x: i32, y: i32) void {
        _ = c.SDL_RenderSetScale(self.render, @intToFloat(f32, x), @intToFloat(f32, y));
    }
};
