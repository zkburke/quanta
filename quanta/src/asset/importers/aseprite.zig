//! Implements compiling aseprite files directly.
//! Aseprite file format is fully specified by https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

pub const Import = struct {
    //Currently just takes all frames and creates a static image
    //TODO: implement layers and animations
    data: []u8,
    width: u32,
    height: u32,

    pub fn assetCompile(
        context: *compiler.CompilerContext,
        file_path: []const u8,
        data: []const u8,
        meta_data: ?Metadata,
    ) ![]const u8 {
        _ = file_path; // autofix
        _ = meta_data; // autofix

        var stream = std.io.FixedBufferStream([]const u8){ .pos = 0, .buffer = data };

        var reader = stream.reader();

        const header = try reader.readStructEndian(Header, .little);

        std.debug.assert(header.magic_number == Header.magic_number);
        std.debug.assert(header.file_size == data.len);

        log.info("header: {}", .{header});

        var pixel_data: ?[]u8 = null;
        var width: u32 = 0;
        var height: u32 = 0;

        for (0..header.frames) |frame_index| {
            const frame = try reader.readStructEndian(Frame, .little);

            std.debug.assert(frame.magic_number == Frame.magic_number);

            log.info("frame[{}]: {}", .{ frame_index, frame });

            for (0..frame.chunk_count) |chunk_index| {
                _ = chunk_index; // autofix
                const chunk_size = try reader.readInt(u32, .little);

                const chunk_type = try reader.readEnum(Chunk.Type, .little);

                //chunk.chunk_size includes the size of the header itself
                const chunk_data_size = chunk_size - @sizeOf(u32) - @sizeOf(Chunk.Type);

                const chunk_data = try context.allocator.alloc(u8, chunk_data_size);

                switch (chunk_type) {
                    .cel_chunk => {
                        const cel_chunk = try reader.readStructEndian(CelChunk, .little);

                        switch (cel_chunk.cel_type) {
                            .raw_image => {
                                const raw_image_extra = try reader.readStructEndian(CelChunk.RawImageDataExtra, .little);

                                log.info("raw_image_extra = {}", .{raw_image_extra});

                                const chunk_width: u32 = raw_image_extra.width;
                                const chunk_height: u32 = raw_image_extra.height;

                                width = chunk_width;
                                height = chunk_height;

                                const raw_image_data = try context.allocator.alloc(u8, chunk_width * chunk_height * @sizeOf(u32));

                                log.info("raw_image_data.len = {}", .{raw_image_data.len});

                                _ = try reader.read(raw_image_data);

                                pixel_data = raw_image_data;
                            },
                            else => {
                                const compressed_image_extra = try reader.readStructEndian(CelChunk.CompressedImage, .little);

                                width = compressed_image_extra.width;
                                height = compressed_image_extra.height;

                                const uncompressed_size = width * height * @sizeOf(u32);

                                const uncompressed_data = try context.allocator.alloc(u8, uncompressed_size);

                                var decompression_stream = std.io.FixedBufferStream([]u8){ .buffer = uncompressed_data, .pos = 0 };

                                try std.compress.zlib.decompress(reader, decompression_stream.writer());

                                pixel_data = uncompressed_data;
                            },
                        }
                    },
                    else => {
                        _ = try reader.read(chunk_data);
                    },
                }
            }
        }

        if (pixel_data == null) return error.FailedToGetPixelData;

        //Encode the imported data

        const fixed_buffer = try context.allocator.alloc(u8, @sizeOf(Encoded) + pixel_data.?.len);

        var out_stream = std.io.FixedBufferStream([]u8){ .buffer = fixed_buffer, .pos = 0 };

        const out_writer = out_stream.writer();

        _ = try out_writer.writeStruct(Encoded{
            .width = width,
            .height = height,
        });

        _ = try out_writer.write(pixel_data.?);

        return fixed_buffer;
    }

    pub fn decode(
        allocator: std.mem.Allocator,
        data: []u8,
    ) !Import {
        _ = allocator; // autofix
        var in_stream = std.io.fixedBufferStream(data);

        const reader = in_stream.reader();

        const encoded = try reader.readStruct(Encoded);

        const pixel_data_size = encoded.width * encoded.height * @sizeOf(u32);
        _ = pixel_data_size; // autofix

        const pixel_data = data[in_stream.pos..];

        return .{
            .width = encoded.width,
            .height = encoded.height,
            .data = pixel_data,
        };
    }

    pub const Metadata = struct {};

    ///TODO: add extension alternatives to handle the .ase extension
    pub const file_extension = ".aseprite";

    pub const base_hash = compiler.getBaseHashFromBytes(@embedFile("aseprite.zig"));

    pub const Encoded = extern struct {
        width: u32,
        height: u32,
    };
};

const Header = extern struct {
    file_size: u32,
    magic_number: u16,
    frames: u16,
    width: u16,
    height: u16,
    color_depth: u16,
    flags: u32 align(1),
    speed: u16 align(1),
    padding_0: u32,
    padding_1: u32,
    palette: u8,
    padding_2: [3]u8,
    color_count: u16,
    pixel_width: u8,
    pixel_height: u8,
    ///X position of grid
    grid_x: i16,
    ///Y position of grid
    grid_y: i16,
    grid_width: u16,
    grid_height: u16,
    padding_reserved: [84]u8,

    pub const magic_number = 0xA5E0;
};

comptime {
    std.debug.assert(@sizeOf(Header) == 128);
}

const Frame = extern struct {
    bytes: u32,
    magic_number: u16,
    deprecated_chunk_count: u16,
    frame_duration: u16,
    padding_reserved: [2]u8,
    chunk_count: u32,

    pub const magic_number = 0xF1FA;
};

comptime {
    std.debug.assert(@sizeOf(Frame) == 16);
}

const Chunk = packed struct(u48) {
    chunk_size: u32,
    chunk_type: Type,

    pub const Type = enum(u16) {
        layer_chunk = 0x2004,
        cel_chunk = 0x2005,
        cel_extra_chunk = 0x2006,
        color_profile = 0x2007,
        external_files_chunk = 0x2008,
        mask_chunk = 0x2016,
        path_chunk = 0x2017,
        tags_chunk = 0x2018,
        palette_chunk = 0x2019,
        deprecated_palette_chunk = 0x0004,
        deprecated_palette_chunk_2 = 0x0011,
        _,
    };
};

const ColorProfile = extern struct {
    type: u16,
    flags: u16,
    gamma: Fixed,
    padding_reserved: [8]u8,

    pub const Type = enum(u16) {
        none = 0,
        use_srgb = 1,
        use_icc = 2,
    };

    ///Extra data for type == icc
    pub const ICCExtra = extern struct {
        data_length: u32,
    };
};

///A fixed point number
const Fixed = packed struct(u32) {
    major: u16,
    fractional: u16,
};

const CelChunk = extern struct {
    layer_index: u16 align(1),
    x_position: i16 align(1),
    y_position: i16 align(1),
    opacity_level: u8 align(1),
    cel_type: CelType align(1),
    z_index: i16 align(1),
    padding_reserved: [5]u8 align(1),

    pub const CelType = enum(u16) {
        raw_image = 0,
        linked_cel = 1,
        compressed_image = 2,
        compressed_tilemap = 3,
    };

    pub const RawImageDataExtra = packed struct {
        width: u16,
        height: u16,
    };

    pub const CompressedImage = packed struct(u32) {
        width: u16,
        height: u16,
    };
};

const compiler = @import("../compiler.zig");
const std = @import("std");
const log = std.log.scoped(.aseprite);
