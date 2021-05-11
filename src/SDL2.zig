const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
});

usingnamespace @import("Save.zig");

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

    const HintDotsWidth = 8;

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
        const window = c.SDL_CreateWindow("crochet helper", pos, pos, 800, 600, wflags) orelse {
            std.log.err("Failed to create Window: {s}", .{c.SDL_GetError()});
            return ContextError.WindowError;
        };
        errdefer c.SDL_DestroyWindow(window);

        const rflags = c.SDL_RENDERER_PRESENTVSYNC | c.SDL_RENDERER_ACCELERATED;
        const renderer = c.SDL_CreateRenderer(window, -1, rflags) orelse {
            std.log.err("Failed to create renderer: {s}", .{c.SDL_GetError()});
            return ContextError.RendererError;
        };
        errdefer c.SDL_DestroyRenderer(renderer);

        // image loading
        const cfn = try std.cstr.addNullByte(allocator, filename);
        defer allocator.free(cfn);
        const tsurf = c.IMG_Load(cfn) orelse {
            std.log.err("Failed to create surface for image: {s}", .{c.IMG_GetError()});
            return ContextError.TextureError;
        };
        defer c.SDL_FreeSurface(tsurf);
        const texture = c.SDL_CreateTextureFromSurface(renderer, tsurf) orelse {
            std.log.err("Failed to create texture for image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };
        errdefer c.SDL_DestroyTexture(texture);

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
            .texture = texture,

            .scrolling = 0,

            .running = true,
        };
    }

    pub fn deinit(self: Context) void {
        self.save.close() catch |err| {
            std.log.err("Error saving: {}", .{err});
            std.log.err("here's your progress number: {}", .{self.save.progress});
        };
        self.allocator.free(self.save.file);
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
                c.SDLK_b => 25,
                else => 0,
            };
            self.save.increment(incval);
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
        const y = self.save.progress / self.width + 1;
        const x = self.save.progress % self.width;
        const oy = @floatToInt(c_int, self.offset.y) + @intCast(c_int, y) * self.offset.z - @divTrunc(self.offset.z, 2);
        if (y & 1 == 1) {
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

    fn clear(self: Context) void {
        _ = c.SDL_SetRenderDrawColor(self.render, 0, 0, 0, 0xFF);
        if (c.SDL_RenderClear(self.render) != 0) {
            std.log.notice("Failed to clear renderer: {s}", .{c.SDL_GetError()});
        }
    }

    fn swap(self: Context) void {
        c.SDL_RenderPresent(self.render);
    }

    ///////////////
    // MAIN LOOP //
    ///////////////
    pub fn main_loop(self: *Context, allocator: *std.mem.Allocator) void {
        var progressCounter = std.ArrayList(u8).init(allocator);
        defer progressCounter.deinit();

        var frameStart = std.time.milliTimestamp();

        while (self.running) {
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
            // render progress counter
            self.swap();

            const frameTime = std.time.milliTimestamp() - frameStart;
            if (frameTime < 33) {
                c.SDL_Delay(@intCast(u32, 33 - frameTime));
            }
        }

        //const p = ctx.save.progress;
        //const lineprogress = p % ctx.width;
        //const heightprogress = p / ctx.width;
        //const colorprogress = std.math.min(camera.img.last_color_change(camera.progress), lineprogress);
        //try progressCounter.writer().print("T {:.>6}/{:.>6} Y {:.>4} L {:.>4} C {:.>4}", .{ camera.progress, camera.max(), heightprogress, lineprogress, colorprogress });
        //ctx.print_slice(progressCounter.items);
        //progressCounter.shrink(0);
    }
};
