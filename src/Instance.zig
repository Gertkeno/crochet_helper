const std = @import("std");
const c = @import("c.zig");

usingnamespace @import("Save.zig");
usingnamespace @import("Context.zig");
usingnamespace @import("Texture.zig");

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
    texture: Texture,

    /////////////////////
    // drawing / movement
    /////////////////////
    // left, right, up, down
    scrolling: u4 = 0,
    expandedView: bool = true,
    progressCounter: std.ArrayList(u8),

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
        const texture = try Texture.load_file(cfn, ctx.render, allocator);

        // Save reading
        const a = [_][]const u8{ filename, ".save" };
        const imgSaveFilename = try std.mem.concat(allocator, u8, &a);
        errdefer allocator.free(imgSaveFilename);
        const imgSave = try Save.open(imgSaveFilename);

        return Instance{
            .allocator = allocator,

            .context = ctx,

            .save = imgSave,
            .texture = texture,

            .expandedView = imgSave.progress == 0,
            .progressCounter = std.ArrayList(u8).init(allocator),

            .running = true,
        };
    }

    pub fn deinit(self: Instance) void {
        self.progressCounter.deinit();
        self.save.write() catch |err| {
            std.log.err("Error saving: {any}", .{err});
            std.log.err("here's your progress number: {d}", .{self.save.progress});
        };
        self.allocator.free(self.save.file);
        self.texture.deinit(self.allocator);
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
                    self.context.offset.z += 1;
                },
                c.SDLK_q => {
                    self.context.offset.z = std.math.max(1, self.context.offset.z - 1);
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
                    std.log.warn("Failed to save progress cause: {any}", .{err});
                    std.log.warn("You may want this number: {d}", .{self.save.progress});
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

    //////////////////////
    // PROGRESS READERS //
    //////////////////////
    fn max(self: Instance) usize {
        return self.texture.width * self.texture.height;
    }

    fn last_color_change(self: Instance) usize {
        const p = self.save.progress;
        if (p == self.max()) {
            return 0;
        }

        const x = p % self.texture.width;
        const y = p / self.texture.width;
        if (y & 1 == 0) {
            const start = self.texture.pixel_at_index(p);
            var i: usize = 1;
            while (i < p and std.mem.eql(u8, start, self.texture.pixel_at_index(p - i))) : (i += 1) {}
            return i - 1;
        } else {
            const op = y * self.texture.width + self.texture.width - x - 1;
            const start = self.texture.pixel_at_index(op);
            var i: usize = 1;
            while (i + op < self.max() and std.mem.eql(u8, start, self.texture.pixel_at_index(op + i))) : (i += 1) {}
            return i - 1;
        }
    }

    fn write_progress(self: *Instance) void {
        self.progressCounter.shrinkAndFree(0);
        const lp = self.save.progress % self.texture.width;
        const hp = self.save.progress / self.texture.width;
        const cp = std.math.min(lp, self.last_color_change());
        if (self.expandedView) {
            const percent = @intToFloat(f32, self.save.progress) / @intToFloat(f32, self.max()) * 100;
            self.progressCounter.writer().print(
                \\Total: {:.>6}/{:.>6} {d: >3.1}%
                \\Lines: {d}
                \\Since line: {:.>5}
                \\Since Color: {:.>4}
                \\===
                \\Panning: WASD
                \\Zoom: QE
                \\Add Stitch ..10/1: V/C
                \\Remov Stitch 10/1: Z/X
                \\Toggle Help: ?
            , .{ self.save.progress, self.max(), percent, hp, lp, cp }) catch |err|
                std.log.warn("Progress counter errored with: {any}", .{err});
        } else {
            self.progressCounter.writer().print("T{:.>6}/{:.>6} L{:.>4} C{:.>4}", .{ self.save.progress, self.max(), lp, cp }) catch |err|
                std.log.warn("Progress counter errored with: {any}", .{err});
        }
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
                self.context.offset.x -= 10;
            } else if (self.scrolling & 0b0100 != 0) {
                self.context.offset.x += 10;
            }
            if (self.scrolling & 0b0010 != 0) {
                self.context.offset.y -= 10;
            } else if (self.scrolling & 0b0001 != 0) {
                self.context.offset.y += 10;
            }

            self.context.clear();
            self.context.draw_all(self.texture, self.save.progress);
            self.context.print_slice(self.progressCounter.items, 10, 0);
            self.context.swap();

            // frame limit with SDL_Delay
            const frameTime = std.time.milliTimestamp() - frameStart;
            if (frameTime < FrameTimeMS) {
                c.SDL_Delay(@intCast(u32, FrameTimeMS - frameTime));
            }
        }
    }
};
