const std = @import("std");
const builtin = @import("builtin");
const c = @import("sdl2");

const Save = @import("Save.zig");
const TimeStats = @import("TimeStats.zig");
const Context = @import("Context.zig");
const Texture = @import("Texture.zig");
const Popup = @import("Popup.zig");

const Instance = @This();
const log = std.log.scoped(.Instance);
//////////
// context
//////////
allocator: std.mem.Allocator,
context: Context,
running: bool = true,
timestat: TimeStats,

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
dragPoint: ?struct { x: f32, y: f32 } = null,
mousePos: c.SDL_Point = undefined,
windowSize: c.SDL_Point = .{ .x = 1000, .y = 600 },
progressBuffer: []u8,
progressCounter: usize = 0,
popups: []Popup,

const FrameRate = 24;
const FrameTimeMS = 1000 / FrameRate;

//////////
// INIT //
//////////
pub fn init(ctx: Context, filename: [:0]const u8, allocator: std.mem.Allocator) !Instance {
    // image loading
    const texture = try Texture.load_file(filename, ctx.render, allocator);

    // Save reading
    const a = [_][]const u8{ ".", std.fs.path.basename(filename), ".save" };
    const imgSaveFilename = try std.mem.concat(allocator, u8, &a);
    errdefer allocator.free(imgSaveFilename);
    log.debug("Save file name as \"{s}\"", .{imgSaveFilename});
    const imgSave = try Save.open(imgSaveFilename);

    // initialize increment popups
    const popups = try allocator.alloc(Popup, 20);
    errdefer allocator.free(popups);
    std.mem.set(Popup, popups, Popup{ .stamp = 0, .texti = 0 });

    return Instance{
        .allocator = allocator,
        .context = ctx,

        .save = imgSave,
        .timestat = TimeStats.start(imgSave.progress),
        .texture = texture,

        .expandedView = imgSave.progress == 0,
        .progressBuffer = try allocator.alloc(u8, 0xDF),
        .popups = popups,
    };
}

pub fn deinit(self: Instance) void {
    self.allocator.free(self.popups);
    self.allocator.free(self.progressBuffer);
    self.timestat.write_append(self.save.progress) catch |err| {
        log.warn("Error saving stats! {s}", .{@errorName(err)});
    };
    self.save.write() catch |err| {
        log.err("Error saving: {s}, path {s}", .{ @errorName(err), self.save.file });
        log.err("here's your progress number: {}", .{self.save.progress});
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
            c.SDLK_F4 => {
                if (c.SDL_GetModState() & c.KMOD_ALT != 0) {
                    self.running = false;
                    return;
                }
            },
            else => {},
        }

        // increments
        const incval: i32 = switch (eventkey) {
            c.SDLK_z => -10,
            c.SDLK_x => -1,
            c.SDLK_c => 1,
            c.SDLK_v => 10,
            c.SDLK_F1 => if (builtin.mode == .Debug) 999999 else 0,
            c.SDLK_F2 => if (builtin.mode == .Debug) -999999 else 0,
            else => 0,
        };

        if (incval != 0) {
            log.debug("Incrementing by {d: >3} was total: {d}", .{ incval, self.save.progress });
            self.save.increment(incval);
            if (self.save.progress > self.max()) {
                self.save.progress = self.max();
            }

            self.save.write() catch |err| {
                log.warn("Failed to save progress cause: {s}, path {s}", .{ @errorName(err), self.save.file });
                log.warn("You may want this number: {d}", .{self.save.progress});
            };

            self.write_progress();
            Popup.push(self.popups, incval);
        }
    }

    // movement mask
    const mask: u4 = switch (eventkey) {
        c.SDLK_LEFT, c.SDLK_a => 0b1000,
        c.SDLK_RIGHT, c.SDLK_d => 0b0100,
        c.SDLK_UP, c.SDLK_w => 0b0010,
        c.SDLK_DOWN, c.SDLK_s => 0b0001,
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
        } else if (e.type == c.SDL_MOUSEBUTTONDOWN) {
            self.dragPoint = .{
                .x = @intToFloat(f32, e.button.x) - self.context.offset.x,
                .y = @intToFloat(f32, e.button.y) - self.context.offset.y,
            };
        } else if (e.type == c.SDL_MOUSEBUTTONUP) {
            self.dragPoint = null;
        } else if (e.type == c.SDL_MOUSEMOTION) {
            self.mousePos.x = e.motion.x;
            self.mousePos.y = e.motion.y;
        } else if (e.type == c.SDL_WINDOWEVENT and
            (e.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED or e.window.event == c.SDL_WINDOWEVENT_RESIZED))
        {
            self.windowSize.x = e.window.data1;
            self.windowSize.y = e.window.data2;
            std.log.debug("resized: {}x{}", .{ self.windowSize.x, self.windowSize.y });
        } else if (e.type == c.SDL_QUIT) {
            self.running = false;
        } else {}
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

fn next_color_change(self: Instance) usize {
    const p = self.save.progress;
    if (p == self.max())
        return 0;

    const x = p % self.texture.width;
    const y = p / self.texture.width;
    if (y & 1 == 0) {
        const start = self.texture.pixel_at_index(p);
        var i: usize = 1;
        while (i < self.texture.width - x) : (i += 1) {
            const search = self.texture.pixel_at_index(p + i);
            if (!std.mem.eql(u8, start, search)) {
                return i;
            }
        }
        return self.texture.width - x;
    } else {
        const op = y * self.texture.width + (self.texture.width - x - 1);
        const start = self.texture.pixel_at_index(op);
        var i: usize = 1;
        while (i < self.texture.width - x) : (i += 1) {
            const search = self.texture.pixel_at_index(op - i);
            if (!std.mem.eql(u8, start, search)) {
                return i;
            }
        }
        return self.texture.width - x;
    }
}

fn write_progress(self: *Instance) void {
    const lp = self.save.progress % self.texture.width;
    const hp = self.save.progress / self.texture.width;
    const cp = std.math.min(lp, self.last_color_change());
    const ncp = self.next_color_change();
    const percent = @intToFloat(f32, self.save.progress) / @intToFloat(f32, self.max()) * 100;
    if (self.expandedView) {
        if (std.fmt.bufPrint(self.progressBuffer,
            \\Total: {:.>6}/{:.>6} {d: >3.1}%
            \\Lines: {d}
            \\Since line: {:.>5}
            \\Since Color: {:.>4}
            \\Next Color: {:.>5}
            \\===
            \\Panning: WASD <^v>
            \\Zoom: Q/E
            \\Add Stitch ..10/1: V/C
            \\Remov Stitch 10/1: Z/X
            \\Toggle Help: ?
        , .{
            self.save.progress, self.max(), percent, //
            hp, //
            lp,
            cp,
            ncp,
        })) |written| {
            self.progressCounter = written.len;
        } else |err| {
            log.warn("Progress counter errored with: {s}", .{@errorName(err)});
        }
    } else {
        if (std.fmt.bufPrint(self.progressBuffer, "{d: >3.1}% L{:.>4} C{:.>4}", .{ percent, cp, ncp })) |written| {
            self.progressCounter = written.len;
        } else |err| {
            log.warn("Progress counter errored with: {s}", .{@errorName(err)});
        }
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
        if (self.dragPoint) |dragPoint| {
            self.context.offset.x = @intToFloat(f32, self.mousePos.x) - dragPoint.x;
            self.context.offset.y = @intToFloat(f32, self.mousePos.y) - dragPoint.y;
        } else {
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
        }

        self.context.clear();
        self.context.draw_all(self.texture, self.save.progress);
        self.context.print_slice(self.progressBuffer[0..self.progressCounter], 10, 0);
        Popup.draw(self.popups, self.context, self.windowSize.y);
        self.context.swap();

        // frame limit with SDL_Delay
        const frameTime = std.time.milliTimestamp() - frameStart;
        if (frameTime < FrameTimeMS) {
            c.SDL_Delay(@intCast(u32, FrameTimeMS - frameTime));
        } else {
            log.debug("Frame took {d} milliseconds!", .{frameTime});
        }
    }
}
