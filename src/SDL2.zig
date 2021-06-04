const std = @import("std");
const c = @import("c.zig");

usingnamespace @import("Save.zig");
usingnamespace @import("Context.zig");

pub const Instance = struct {
    //////////
    // context
    //////////
    allocator: *std.mem.Allocator,
    context: Context,
    running: bool,

    //////////
    // texture
    //////////
    save: Save,
    texture: *c.SDL_Texture,
    pixels: []const u8,
    stride: u8,
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
    scrolling: u4 = 0,
    expandedView: bool = true,
    progressCounter: std.ArrayList(u8),

    const HintDotsWidth = 10;
    const FrameRate = 24;
    const FrameTimeMS = 1000 / FrameRate;

    //////////
    // INIT //
    //////////
    pub fn init(filename: []const u8, allocator: *std.mem.Allocator) !Instance {
        const ctx = try Context.init();
        errdefer ctx.deinit();

        // image loading
        const cfn = try std.cstr.addNullByte(allocator, filename);
        defer allocator.free(cfn);
        const tsurf: *c.SDL_Surface = c.IMG_Load(cfn) orelse {
            std.log.err("Failed to create surface for image: {s}", .{c.IMG_GetError()});
            return ContextError.TextureError;
        };
        const stride = tsurf.format.*.BytesPerPixel;

        defer c.SDL_FreeSurface(tsurf);
        const pct = @ptrCast([*]const u8, tsurf.pixels);
        const pixels = try allocator.dupe(u8, pct[0..@intCast(usize, tsurf.w * tsurf.h * @intCast(c_int, stride))]);
        errdefer allocator.free(pixels);

        const texture = c.SDL_CreateTextureFromSurface(ctx.render, tsurf) orelse {
            std.log.err("Failed to create texture for image: {s}", .{c.SDL_GetError()});
            return ContextError.TextureError;
        };
        errdefer c.SDL_DestroyTexture(texture);

        // Save reading
        const a = [_][]const u8{ filename, ".save" };
        const imgSaveFilename = try std.mem.concat(allocator, u8, &a);
        errdefer allocator.free(imgSaveFilename);
        const imgSave = try Save.open(imgSaveFilename);

        return Instance{
            .allocator = allocator,

            .context = ctx,

            .save = imgSave,
            .width = @intCast(usize, tsurf.w),
            .height = @intCast(usize, tsurf.h),
            .texture = texture,
            .pixels = pixels,
            .stride = stride,

            .expandedView = imgSave.progress == 0,
            .progressCounter = std.ArrayList(u8).init(allocator),

            .running = true,
        };
    }

    pub fn deinit(self: Instance) void {
        self.progressCounter.deinit();
        self.save.write() catch |err| {
            std.log.err("Error saving: {}", .{err});
            std.log.err("here's your progress number: {}", .{self.save.progress});
        };
        self.allocator.free(self.save.file);
        self.allocator.free(self.pixels);
        self.context.deinit();
    }

    ////////////
    // EVENTS //
    ////////////
    fn handle_key(self: *Instance, eventkey: c_int, up: bool) void {
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
                c.SDLK_SLASH => {
                    self.expandedView = !self.expandedView;
                    self.write_progress();
                },
                else => {},
            }

            // increments
            const incval: i32 = switch (eventkey) {
                c.SDLK_z => -10,
                c.SDLK_x => -1,
                c.SDLK_c => 1,
                c.SDLK_v => 10,
                c.SDLK_F1 => if (std.builtin.mode == .Debug) 999999 else 0,
                c.SDLK_F2 => if (std.builtin.mode == .Debug) -999999 else 0,
                else => 0,
            };

            if (incval != 0) {
                self.save.increment(incval);
                if (self.save.progress > self.max()) {
                    self.save.progress = self.max();
                }

                self.save.write() catch |err| {
                    std.log.warn("Failed to save progress cause: {}", .{err});
                    std.log.warn("You may want this number: {}", .{self.save.progress});
                };

                self.write_progress();
            }
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

    fn handle_events(self: *Instance) void {
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
    fn draw_all(self: Instance) void {
        // draw texture
        const drawRect = c.SDL_Rect{
            .x = @floatToInt(i32, self.offset.x),
            .y = @floatToInt(i32, self.offset.y),
            .w = @intCast(i32, self.width) * self.offset.z,
            .h = @intCast(i32, self.height) * self.offset.z,
        };
        if (c.SDL_RenderCopy(self.context.render, self.texture, null, &drawRect) != 0) {
            std.log.notice("Failed to render to screen", .{});
        }

        // draw fully complete lines
        self.context.set_color(0xFF, 0, 0);
        var fullLines: usize = self.save.progress / self.width;
        while (fullLines > 0) : (fullLines -= 1) {
            const x = @floatToInt(c_int, self.offset.x);
            const y = @floatToInt(c_int, self.offset.y) + @intCast(c_int, fullLines) * self.offset.z - @divTrunc(self.offset.z, 2);
            const maxX = @intCast(c_int, self.width) * self.offset.z;
            if (c.SDL_RenderDrawLine(self.context.render, x, y, x + maxX, y) != 0) {
                std.log.notice("Drawing line at {} failed: {s}", .{ fullLines, c.SDL_GetError() });
            }
        }

        // draw progress
        self.context.set_color(0xFF, 0, 0x7F);
        const y = self.save.progress / self.width;
        const x = self.save.progress % self.width;
        const oy = @floatToInt(c_int, self.offset.y) + @intCast(c_int, y) * self.offset.z + @divTrunc(self.offset.z, 2);
        if (y & 1 == 0) {
            // left to right
            const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, x) * self.offset.z;
            _ = c.SDL_RenderDrawLine(self.context.render, @floatToInt(c_int, self.offset.x), oy, ox, oy);

            self.context.set_color(0, 0xFF, 0);
            var i: u32 = 0;
            while (i < HintDotsWidth and x + i < self.width) : (i += 1) {
                const hintX = ox + (@intCast(i32, i) * self.offset.z) + @divTrunc(self.offset.z, 2);
                self.set_inverse_color(x + i, y);
                _ = c.SDL_RenderDrawPoint(self.context.render, hintX, oy);
            }
        } else {
            // right to left
            const ow = @floatToInt(c_int, self.offset.x) + @intCast(c_int, self.width) * self.offset.z;
            const ox = @floatToInt(c_int, self.offset.x) + @intCast(c_int, self.width - x) * self.offset.z;
            _ = c.SDL_RenderDrawLine(self.context.render, ow, oy, ox, oy);

            self.context.set_color(0, 0xFF, 0);
            var i: u32 = 0;
            while (i < HintDotsWidth and x + i < self.width) : (i += 1) {
                const hintX = ox - (@intCast(i32, i) * self.offset.z) - @divTrunc(self.offset.z, 2);
                self.set_inverse_color(self.width - x - i - 1, y);
                _ = c.SDL_RenderDrawPoint(self.context.render, hintX, oy);
            }
        }
    }

    fn set_inverse_color(self: Instance, x: usize, y: usize) void {
        const pos = (x + y * self.width) * self.stride;
        const pixel = self.pixels[pos .. pos + 3];
        const r = 255 - pixel[0];
        const g = 255 - pixel[1];
        const b = 255 - pixel[2];
        self.context.set_color(r, g, b);
    }

    fn clear(self: Instance) void {
        self.context.set_color(0, 0, 0);
        if (c.SDL_RenderClear(self.context.render) != 0) {
            std.log.notice("Failed to clear renderer: {s}", .{c.SDL_GetError()});
        }
    }

    fn swap(self: Instance) void {
        c.SDL_RenderPresent(self.context.render);
    }

    ///////////////
    // MAIN LOOP //
    ///////////////
    pub fn main_loop(self: *Instance) void {
        self.write_progress();
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
            self.context.print_slice(self.progressCounter.items, 10, 0);
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
    fn max(self: Instance) usize {
        return self.width * self.height;
    }

    fn pixel_at_index(self: Instance, i: usize) []const u8 {
        const is = i * self.stride;
        return self.pixels[is .. is + 3];
    }

    fn last_color_change(self: Instance) usize {
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

    fn write_progress(self: *Instance) void {
        self.progressCounter.shrink(0);
        const lp = self.save.progress % self.width;
        const hp = self.save.progress / self.width;
        const cp = std.math.min(lp, self.last_color_change());
        if (self.expandedView) {
            const percent = @intToFloat(f32, self.save.progress) / @intToFloat(f32, self.max()) * 100;
            self.progressCounter.writer().print(
                \\Total: {:.>6}/{:.>6} {d: >3.1}%
                \\Lines: {}
                \\Since line: {:.>5}
                \\Since Color: {:.>4}
                \\===
                \\Panning: WASD
                \\Zoom: QE
                \\Add Stitch ..10/1: V/C
                \\Remov Stitch 10/1: Z/X
                \\Toggle Help: ?
            , .{ self.save.progress, self.max(), percent, hp, lp, cp }) catch
            |err| std.log.warn("Progress counter errored with: {}", .{err});
        } else {
            self.progressCounter.writer().print("T{:.>6}/{:.>6} L{:.>4} C{:.>4}", .{ self.save.progress, self.max(), lp, cp }) catch
            |err| std.log.warn("Progress counter errored with: {}", .{err});
        }
    }
};
