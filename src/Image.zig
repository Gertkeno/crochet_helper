const std = @import("std");
const c = @cImport({
    @cInclude("png.h");
    @cInclude("stdio.h");
});

pub const BitmapError = error{
    InvalidType,
    InvalidPlanes,
    UnsupportedCompression,
};

pub const PNGError = error{
    Unkown,
    CreationError,
    NotFound,
    NotPNG,
    UnsupportedColorType,
};

fn read_row_callback(
    ptr: c.png_structp,
    row: c.png_uint_32,
    pass: c_int,
) callconv(.C) void {
    // print?
    //std.log.info("png read {}pass {}row", .{ pass, row });
}

pub const Image = struct {
    width: u32,
    height: u32,
    stride: usize,
    pixels: []const u8,
    allocator: *std.mem.Allocator,

    pub fn png(filename: [*:0]const u8, allocator: *std.mem.Allocator) !Image {
        var png_ptr = c.png_create_read_struct(c.PNG_LIBPNG_VER_STRING, null, null, null);
        var info_ptr = c.png_create_info_struct(png_ptr);
        defer c.png_destroy_read_struct(&png_ptr, &info_ptr, null);

        var file = c.fopen(filename, "r") orelse return PNGError.NotFound;
        defer _ = c.fclose(file);

        c.png_init_io(png_ptr, file);
        c.png_set_read_status_fn(png_ptr, read_row_callback);
        c.png_set_keep_unknown_chunks(png_ptr, 1, null, 0);
        c.png_read_info(png_ptr, info_ptr);

        var width: c_uint = 0;
        var height: c_uint = 0;
        var bitDepth: c_int = 0;
        var colorType: c_int = 0;
        if (c.png_get_IHDR(png_ptr, info_ptr, &width, &height, &bitDepth, &colorType, null, null, null) != 1) {
            return PNGError.Unkown;
        }

        const stride: usize = switch (colorType) {
            c.PNG_COLOR_TYPE_RGB => 3,
            c.PNG_COLOR_TYPE_RGB_ALPHA => 4,
            c.PNG_COLOR_TYPE_GRAY => 1,
            c.PNG_COLOR_TYPE_GRAY_ALPHA => 2,
            else => return PNGError.UnsupportedColorType,
        };

        if (bitDepth == 16) {
            c.png_set_strip_16(png_ptr);
        }

        c.png_read_update_info(png_ptr, info_ptr);

        const rowbytes = c.png_get_rowbytes(png_ptr, info_ptr);
        var row_pointers = try allocator.alloc(c.png_bytep, height);
        defer allocator.free(row_pointers);

        var imgData = try allocator.alloc(u8, rowbytes * height);
        errdefer allocator.free(imgData);

        for (row_pointers) |*row, n| {
            row.* = imgData.ptr + n * rowbytes;
        }

        c.png_read_image(png_ptr, row_pointers.ptr);
        c.png_read_end(png_ptr, null);

        return Image{
            .width = width,
            .height = height,
            .pixels = imgData,
            .stride = stride,
            .allocator = allocator,
        };
    }

    pub fn bmp(file: []const u8, allocator: *std.mem.Allocator) !Image {
        var file = try std.fs.cwd().openFile(file, .{});
        defer file.close();

        const reader = file.reader();

        var headType: [2]u8 = undefined;
        try reader.readNoEof(&headType);

        if (headType[0] != 'B' and headType[1] != 'M') {
            return BitmapError.InvalidType;
        }

        try reader.skipBytes(12, .{ .buf_size = 12 });

        // BITMAPINFOHEADER
        const headsize = try reader.readIntLittle(u32);
        const width = try reader.readIntLittle(i32);
        const height = try reader.readIntLittle(i32);
        const planes = try reader.readIntLittle(i32);
        if (planes != 1) {
            return BitmapError.InvalidPlanes;
        }
        const bitcount = try reader.readIntLittle(i32);
        const compression = try reader.readIntLittle(i32);
        if (compression != 0) {
            return BitmapError.UnsupportedCompression;
        }
        const imgsize = try reader.readIntLittle(i32);
        const ppmw = try reader.readIntLittle(i32);
        const ppmh = try reader.readIntLittle(i32);
        const colorsInPalette = try reader.readIntLittle(i32);
        const colorSignificant = try reader.readIntLittle(i32);

        // color table
        if (colorsInPalette > 0) {}

        return Bitmap{
            .width = 0,
            .height = 0,
            .pixels = undefined,
            .stride = @intCast(usize, @divExact(bitcount, 8)),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Image) void {
        self.allocator.free(self.pixels);
    }
};
