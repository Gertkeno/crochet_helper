const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

usingnamespace @import("Save.zig");
const font_franklin = @embedFile("franklin.bmp");

pub const ContextError = error{
    InitError,
    WindowError,
    RendererError,
    TextureError,
};

pub const Context = struct {
    //////////
    // context
    //////////
    allocator: *std.mem.Allocator,
    window: *c.SDL_Window,
    render: *c.SDL_Renderer,
    running: bool,

    //////////
    // texture
    //////////
    save: Save,
    texture: *c.SDL_Texture,
    font: *c.SDL_Texture,
    pixels: []const u8,
    width: usize,
    height: usize,

    /////////////////////
    // drawing / movement
    /////////////////////
    offset: struct {
        x: f32 = 0,
        y: f32 = 0,
        z: i32 = 8,
    } = .{},
    // left, right, up, down
    scrolling: u4,

    const HintDotsWidth = 10;
    const FrameRate = 24;
    const FrameTimeMS = 1000 / FrameRate;

    //////////
    // INIT //
    //////////
    pub fn init(filename: []const u8, allocator: *std.mem.Allocator) !Context {
        // SDL2 init
        if (c.SDL_Init(c.SDL_INIT_EVENTS) != 0) {
            std.log.err("Failed to init SDL2: {s}", .{c.SDL_GetError()});
            return ContextError.InitError;
        }
        _ = c.IMG_Init(c.IMG_INIT_JPG | c.IMG_INIT_PNG);

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

        // image loading
        const cfn = try std.cstr.addNullByte(allocator, filename);
        const tsurf = c.IMG_Load(cfn) orelse {
            std.log.err("Failed to create surface for image: {s}", .{c.IMG_GetError()});
            return ContextError.TextureError;
        };
        allocator.free(cfn);
        defer c.SDL_FreeSurface(tsurf);
        const pct = @ptrCast([*]const u8, tsurf[0].pixels);
        const pixels = try allocator.dupe(u8, pct[0..@intCast(usize, tsurf[0].w * tsurf[0].h * 4)]);
        errdefer allocator.free(pixels);

        const ttexture = c.SDL_CreateTextureFromSurface(renderer, tsurf) orelse {
            std.log.err("Failed to create texture for image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };
        errdefer c.SDL_DestroyTexture(ttexture);

        const fsurf = c.SDL_LoadBMP_RW(c.SDL_RWFromConstMem(&font_franklin[0], font_franklin.len), 1) orelse {
            std.log.err("Failed to create font surface from interal image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };
        defer c.SDL_FreeSurface(fsurf);
        _ = c.SDL_SetColorKey(fsurf, c.SDL_TRUE, c.SDL_MapRGB(fsurf[0].format, 0xFF, 0, 0xFF));
        const ftexture = c.SDL_CreateTextureFromSurface(renderer, fsurf) orelse {
            std.log.err("Failed to create font from internal image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };

        // Save reading
        const a = [_][]const u8{ filename, ".save" };
        const imgSaveFilename = try std.mem.concat(allocator, u8, &a);
        errdefer allocator.free(imgSaveFilename);
        const imgSave = try Save.open(imgSaveFilename);

        return Context{
            .allocator = allocator,

            .window = window,
            .render = renderer,

            .save = imgSave,
            .width = @intCast(usize, tsurf[0].w),
            .height = @intCast(usize, tsurf[0].h),
            .texture = ttexture,
            .font = ftexture,
            .pixels = pixels,

            .scrolling = 0,

            .running = true,
        };
    }

    pub fn deinit(self: Context) void {
        self.save.write() catch |err| {
            std.log.err("Error saving: {}", .{err});
            std.log.err("here's your progress number: {}", .{self.save.progress});
        };
        self.allocator.free(self.save.file);
        self.allocator.free(self.pixels);
        c.SDL_DestroyRenderer(self.render);
        c.SDL_DestroyWindow(self.window);
        c.IMG_Quit();
        c.SDL_Quit();
    }

    ////////////
    // EVENTS //
    ////////////
    fn handle_key(self: *Context, eventkey: c_int, up: bool) void {
        // singular presses
        if (!up) {
            // zoom in/out
            switch (eventkey) {
                c.SDLK_e => {
                    self.offset.z += 1;
                },
                c.SDLK_q => {
                    self.offset.z = std.math.max(1, self.offset.z - 1);
                },
                else => {},
            }

            // increments
            const incval: i32 = switch (eventkey) {
                c.SDLK_z => -10,
                c.SDLK_x => -1,
                c.SDLK_c => 1,
                c.SDLK_v => 10,
                else => 0,
            };
            self.save.increment(incval);
            if (self.save.progress > self.max()) {
                self.save.progress = self.max();
            }

            self.save.write() catch |err| {
                std.log.warn("Failed to save progress cause: {}", .{err});
                std.log.warn("You may want this number: {}", .{self.save.progress});
            };
        }

        // movement mask
        const mask: u4 = switch (eventkey) {
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

    fn handle_events(self: *Context) void {
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) == 1) {
            if (e.type == c.SDL_KEYDOWN or e.type == c.SDL_KEYUP) {
                self.handle_key(e.key.keysym.sym, e.type == c.SDL_KEYUP);
            } else if (e.type == c.SDL_QUIT) {
                self.running = false;
            }
        }
    }

    /////////////
    // DRAWING //
    /////////////
    fn draw_all(self: Context) void {
        // draw texture
        const drawRect = c.SDL_Rect{
            .x = @floatToInt(i32, self.offset.x),
            .y = @floatToInt(i32, self.offset.y),
            .w = @intCast(i32, self.width) * self.offset.z,
            .h = @intCast(i32, self.height) * self.offset.z,
        };
        if (c.SDL_RenderCopy(self.render, self.texture, null, &drawRect) != 0) {
            std.log.notice("Failed to render to screen", .{});
        }

        // draw fully complete lines
        _ = c.SDL_SetRenderDrawColor(self.render, 0xFF, 0, 0, 0xFF);
        var fullLines: usize = self.save.progress / self.width;
        while (fullLines > 0) : (fullLines -= 1) {
            const x = @floatToInt(c_int, self.offset.x);
            const y = @floatToInt(c_int, self.offset.y) + @intCast(c_int, fullLines) * self.offset.z - @divTrunc(self.offset.z, 2);
            const maxX = @intCast(c_int, self.width) * self.offset.z;
            if (c.SDL_RenderDrawLine(self.render, x, y, x + maxX, y) != 0) {
                std.log.notice("Drawing line at {} failed: {s}", .{ fullLines, c.SDL_GetError() });
            }
        }

        // draw progress
        _ = c.SDL_SetRenderDrawColor(self.render, 0xFF, 0, 0x7F, 0xFF);
        const y = self.save.progress / self.width;
        const x = self.save.progress % self.width;
        const oy = @floatToInt(c_int, self.offset.y) + @intCast(c_int, y) * self.offset.z + @divTrunc(self.offset.z, 2);
        if (y & 1 == 0) {
            // left to right
            const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, x) * self.offset.z;
            _ = c.SDL_RenderDrawLine(self.render, @floatToInt(c_int, self.offset.x), oy, ox, oy);

            _ = c.SDL_SetRenderDrawColor(self.render, 0, 0xFF, 0, 0xFF);
            var i: i32 = 0;
            while (i < HintDotsWidth) : (i += 1) {
                _ = c.SDL_RenderDrawPoint(self.render, ox + (i * self.offset.z) + @divTrunc(self.offset.z, 2), oy);
            }
        } else {
            // right to left
            const ow = @floatToInt(c_int, self.offset.x) + @intCast(c_int, self.width) * self.offset.z;
            const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, self.width - x) * self.offset.z;
            _ = c.SDL_RenderDrawLine(self.render, ow, oy, ox, oy);

            _ = c.SDL_SetRenderDrawColor(self.render, 0, 0xFF, 0, 0xFF);
            var i: i32 = 0;
            while (i < HintDotsWidth) : (i += 1) {
                _ = c.SDL_RenderDrawPoint(self.render, ox - (i * self.offset.z) - @divTrunc(self.offset.z, 2), oy);
            }
        }
    }

    fn set_inverse_color(self: Context, x: usize, y: usize) void {
        const pos = (x + y * self.width) * 4;
        const pixel = self.pixels[pos .. pos + 3];
        const r = 255 - pixel[0];
        const g = 255 - pixel[1];
        const b = 255 - pixel[2];
        _ = c.SDL_SetRenderDrawColor(self.render, r, g, b, 0xFF);
    }

    fn clear(self: Context) void {
        _ = c.SDL_SetRenderDrawColor(self.render, 0, 0, 0, 0xFF);
        if (c.SDL_RenderClear(self.render) != 0) {
            std.log.notice("Failed to clear renderer: {s}", .{c.SDL_GetError()});
        }
    }

    fn swap(self: Context) void {
        c.SDL_RenderPresent(self.render);
    }

    //////////
    // FONT //
    //////////
    fn print_slice(self: Context, str: []const u8, x: i32, y: i32) void {
        for (str) |char, n| {
            const cx = @intCast(i32, char % 16) * 32;
            const cy = @intCast(i32, char / 16) * 32;
            const srcRect = c.SDL_Rect{
                .x = cx,
                .y = cy,
                .w = 32,
                .h = 32,
            };
            const dstRect = c.SDL_Rect{
                .x = x + @intCast(i32, n * 18),
                .y = y,
                .w = 32,
                .h = 32,
            };
            _ = c.SDL_RenderCopy(self.render, self.font, &srcRect, &dstRect);
        }
    }

    ///////////////
    // MAIN LOOP //
    ///////////////
    pub fn main_loop(self: *Context, allocator: *std.mem.Allocator) void {
        var progressCounter = std.ArrayList(u8).init(allocator);
        defer progressCounter.deinit();

        while (self.running) {
            const frameStart = std.time.milliTimestamp();
            self.handle_events();
            if (self.scrolling & 0b1000 != 0) {
                self.offset.x -= 10;
            } else if (self.scrolling & 0b0100 != 0) {
                self.offset.x += 10;
            }
            if (self.scrolling & 0b0010 != 0) {
                self.offset.y -= 10;
            } else if (self.scrolling & 0b0001 != 0) {
                self.offset.y += 10;
            }

            self.clear();
            self.draw_all();
            { // render progress counter
                const lp = self.save.progress % self.width;
                const hp = self.save.progress / self.width;
                const cp = std.math.min(lp, self.last_color_change());
                if (progressCounter.writer().print("T{:.>6}/{:.>6} Y{} L{:.>4} C{:.>4}", .{ self.save.progress, self.max(), hp, lp, cp })) {
                    self.print_slice(progressCounter.items, 0, 0);
                } else |err| {
                    std.log.warn("Progress counter errored with: {}", .{err});
                }
                progressCounter.shrink(0);
            }
            self.swap();

            // frame limit with SDL_Delay
            const frameTime = std.time.milliTimestamp() - frameStart;
            if (frameTime < FrameTimeMS) {
                c.SDL_Delay(@intCast(u32, FrameTimeMS - frameTime));
            }
        }
    }

    //////////////////////
    // PROGRESS READERS //
    //////////////////////
    fn max(self: Context) usize {
        return self.width * self.height;
    }

    fn pixel_at_index(self: Context, i: usize) []const u8 {
        const is = i * 4;
        return self.pixels[is .. is + 3];
    }

    fn last_color_change(self: Context) usize {
        const p = self.save.progress;
        if (p == self.max()) {
            return 0;
        }

        const x = p % self.width;
        const y = p / self.width;
        if (y & 1 == 0) {
            const start = self.pixel_at_index(p);
            var i: usize = 1;
            while (i < p and std.mem.eql(u8, start, self.pixel_at_index(p - i))) : (i += 1) {}
            return i - 1;
        } else {
            const op = y * self.width + self.width - x - 1;
            const start = self.pixel_at_index(op);
            var i: usize = 1;
            while (i + op < self.max() and std.mem.eql(u8, start, self.pixel_at_index(op + i))) : (i += 1) {}
            return i - 1;
        }
    }
};
