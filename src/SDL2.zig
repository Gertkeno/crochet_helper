const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

pub const ContextError = error{
    InitError,
    WindowError,
    RendererError,
    TextureError,
};

pub const Context = struct {
    window: *c.SDL_Window,
    render: *c.SDL_Renderer,

    texture: *c.SDL_Texture,
    offset: struct {
        x: f32,
        y: f32,
    },
    // left, right, up, down
    scrolling: u4,

    pub fn init(filename: [*:0]const u8) !Context {
        if (c.SDL_Init(c.SDL_INIT_EVENTS) != 0) {
            std.log.err("Failed to init SDL2: {s}", .{c.SDL_GetError()});
            return ContextError.InitError;
        }
        _ = c.IMG_Init(c.IMG_INIT_JPG | c.IMG_INIT_PNG);

        const wflags = c.SDL_WINDOW_RESIZABLE;
        const pos = c.SDL_WINDOWPOS_CENTERED;
        const window = c.SDL_CreateWindow("crochet helper", pos, pos, 800, 600, wflags) orelse {
            std.log.err("Failed to create Window: {s}", .{c.SDL_GetError()});
            return ContextError.WindowError;
        };

        const rflags = c.SDL_RENDERER_PRESENTVSYNC | c.SDL_RENDERER_ACCELERATED;
        const renderer = c.SDL_CreateRenderer(window, -1, rflags) orelse {
            std.log.err("Failed to create renderer: {s}", .{c.SDL_GetError()});
            return ContextError.RendererError;
        };

        const tsurf = c.IMG_Load(filename) orelse {
            std.log.err("Failed to create surface for image: {s}", .{c.IMG_GetError()});
            return ContextError.TextureError;
        };
        const texture = c.SDL_CreateTextureFromSurface(renderer, tsurf) orelse {
            std.log.err("Failed to create texture for image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };

        return Context{
            .window = window,
            .render = renderer,
            .texture = texture,

            .offset = .{ .x = 0, .y = 0 },
            .scrolling = 0,
        };
    }

    pub fn deinit(self: Context) void {
        c.SDL_DestroyRenderer(self.render);
        c.SDL_DestroyWindow(self.window);
        c.IMG_Quit();
        c.SDL_Quit();
    }

    fn handle_key(self: *Context, eventkey: c.SDL_Keysym, up: bool) void {
        const mask = switch (eventkey) {
            c.SDLK_a => 0b1000,
            c.SDLK_d => 0b0100,
            c.SDLK_w => 0b0010,
            c.SDLK_s => 0b0001,
            else => 0b0000,
        };

        if (up) {
            self.scrolling &= ~mask;
        } else {
            self.scrolling |= mask;
        }
    }

    pub fn handle_events(self: *Context) void {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e)) {
            switch (e.type) {
                c.SDL_KEYDOWN => {
                    self.handle_key(e.key.keysym.sym, false);
                },
                c.SDL_KEYUP => {
                    self.handle_key(e.key.keysym.sym, true);
                },
                else => {},
            }
        }
    }

    pub fn draw_all(self: Context) void {
        if (c.SDL_RenderCopy(self.render, self.texture, null, null) != 0) {
            std.log.notice("Failed to render to screen", .{});
        }

        c.SDL_RenderPresent(self.render);
    }
};
