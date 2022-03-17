const c = @import("c.zig");
const std = @import("std");

pub const TextureError = error{
    CreationFailure,
};

const Texture = @This();

handle: *c.SDL_Texture,
pixels: []const u8,
stride: u8,
colors: ?[]c.SDL_Color,
width: usize,
height: usize,

pub fn load_file(filename: [:0]const u8, render: *c.SDL_Renderer, allocator: std.mem.Allocator) !Texture {
    const surf: *c.SDL_Surface = c.IMG_Load(filename) orelse {
        std.log.err("Failed to create surface for image: {s}", .{c.IMG_GetError()});
        return TextureError.CreationFailure;
    };
    const stride = surf.format.*.BytesPerPixel;
    std.log.debug("Image stride (Bpp) {d}", .{stride});
    if (stride == 1) {
        std.log.debug("Low stride (bpp) {d}, {s}", .{
            surf.format.*.BitsPerPixel,
            c.SDL_GetPixelFormatName(surf.format.*.format),
        });
    }

    defer c.SDL_FreeSurface(surf);
    const pct = @ptrCast([*]const u8, surf.pixels);
    const pixels = try allocator.dupe(u8, pct[0..@intCast(usize, surf.w * surf.h * @intCast(c_int, stride))]);
    errdefer allocator.free(pixels);

    const texture = c.SDL_CreateTextureFromSurface(render, surf) orelse {
        std.log.err("Failed to create texture for image: {s}", .{c.SDL_GetError()});
        return TextureError.CreationFailure;
    };
    errdefer c.SDL_DestroyTexture(texture);

    var colors: ?[]c.SDL_Color = null;
    if (surf.format.*.palette) |palette| {
        const len = @intCast(usize, palette.*.ncolors);
        colors = try allocator.dupe(c.SDL_Color, palette.*.colors[0..len]);
    }

    return Texture{
        .width = @intCast(usize, surf.w),
        .height = @intCast(usize, surf.h),
        .stride = stride,
        .pixels = pixels,
        .handle = texture,
        .colors = colors,
    };
}

pub fn deinit(self: Texture, allocator: std.mem.Allocator) void {
    c.SDL_DestroyTexture(self.handle);
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
