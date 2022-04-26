const sdl = @import("sdl2");
const std = @import("std");

const log = std.log.scoped(.Texture);

pub const TextureError = error{
    CreationFailure,
};

const Texture = @This();

handle: sdl.Texture,
pixels: []const u8,
stride: u8,
colors: ?[]sdl.Color,
width: usize,
height: usize,

pub fn load_file(filename: [:0]const u8, render: sdl.Renderer, allocator: std.mem.Allocator) !Texture {
    const surf = try sdl.image.loadSurface(filename);
    defer surf.destroy();

    const stride = surf.ptr.format.*.BytesPerPixel;
    log.debug("Image stride (Bpp) {d}", .{stride});
    if (stride == 1) {
        log.debug("Low stride (bpp) {d}, {s}", .{
            surf.ptr.format.*.BitsPerPixel,
            sdl.c.SDL_GetPixelFormatName(surf.ptr.format.*.format),
        });
    }

    const pct = @ptrCast([*]const u8, surf.ptr.pixels);
    const pctlen = @intCast(usize, surf.ptr.w * surf.ptr.h * @intCast(c_int, stride));
    const pixels = try allocator.dupe(u8, pct[0..pctlen]);
    errdefer allocator.free(pixels);

    const texture = try sdl.createTextureFromSurface(render, surf);
    errdefer texture.destroy();

    var colors: ?[]sdl.Color = null;
    if (surf.ptr.format.*.palette) |palette| {
        const len = @intCast(usize, palette.*.ncolors);
        colors = try allocator.dupe(sdl.Color, @ptrCast([*]sdl.Color, palette.*.colors)[0..len]);
        log.debug("Found palette of {d} colors.", .{len});
    }

    return Texture{
        .width = @intCast(usize, surf.ptr.w),
        .height = @intCast(usize, surf.ptr.h),
        .stride = stride,
        .pixels = pixels,
        .handle = texture,
        .colors = colors,
    };
}

pub fn deinit(self: Texture, allocator: std.mem.Allocator) void {
    self.handle.destroy();
    allocator.free(self.pixels);
    if (self.colors) |colors| {
        allocator.free(colors);
    }
}

pub fn pixel_at_index(self: Texture, i: usize) []const u8 {
    if (self.stride == 1 and self.colors != null) { // palette index
        const ci = self.pixels[i];
        return std.mem.asBytes(&self.colors.?[ci]);
    } else { // true RGB888/RGBA8888
        const is = i * self.stride;
        return self.pixels[is .. is + 3];
    }
}
