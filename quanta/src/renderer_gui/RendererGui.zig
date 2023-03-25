const RendererGui = @This();

const std = @import("std");
const graphics = @import("../graphics.zig");
const window = @import("../windowing.zig").window;
const zalgebra = @import("../math.zig").zalgebra;
const imgui = @import("../imgui.zig").cimgui;

var self: @This() = .{};

const RectanglePipelinePushData = extern struct {
    render_target_width: f32,
    render_target_height: f32,
    rectangle: Rectangle,
};

const MeshPipelinePushData = extern struct {
    projection: [4][4]f32,
    texture_index: u32,
};

const Texture = struct {
    image: graphics.Image,
    sampler: graphics.Sampler,
};

allocator: std.mem.Allocator = undefined,
rectangle_pipeline: graphics.GraphicsPipeline = undefined,
mesh_pipeline: graphics.GraphicsPipeline = undefined,
///Should use double buffering of course, but that will be a big change
///and I want to create a solution common to all renderers in the engine
command_buffer: graphics.CommandBuffer = undefined,
color_target_image: *const graphics.Image = undefined,
rectangles: std.ArrayListUnmanaged(Rectangle) = .{},
scissors: std.ArrayListUnmanaged([4]u16) = .{},
rectangles_buffer: graphics.Buffer = undefined,
vertices_buffer: graphics.Buffer = undefined,
vertices_staging_buffer: graphics.Buffer = undefined,
indices_buffer: graphics.Buffer = undefined,
indices_staging_buffer: graphics.Buffer = undefined,
textures: std.ArrayListUnmanaged(Texture) = .{},

pub const TextureHandle = enum(u32) { null = 0, _ };

pub fn createTexture(data: []const u8, width: u32, height: u32) !TextureHandle {
    const handle = @intToEnum(TextureHandle, @intCast(u32, self.textures.items.len + 1));

    var image = try graphics.Image.initData(.@"2d", data, width, height, 1, 1, .r8g8b8a8_srgb, .shader_read_only_optimal, .{
        .transfer_dst_bit = true,
        .sampled_bit = true,
    });
    errdefer image.deinit();

    var sampler = try graphics.Sampler.init(.nearest, .nearest, .repeat, .repeat, .repeat, null);
    errdefer sampler.deinit();

    try self.textures.append(self.allocator, .{
        .image = image,
        .sampler = sampler,
    });

    self.mesh_pipeline.setDescriptorImageSampler(1, @enumToInt(handle) - 1, image, sampler);

    return handle;
}

pub fn init(allocator: std.mem.Allocator, swapchain: graphics.Swapchain) !void {
    self.allocator = allocator;
    // self.rectangle_pipeline = try graphics.GraphicsPipeline.init(
    //     allocator,
    //     .{
    //         .color_attachment_formats = &.{ swapchain.surface_format.format },
    //         .vertex_shader_binary = @alignCast(4, @embedFile("spirv/rectangle.vert.spv")),
    //         .fragment_shader_binary = @alignCast(4, @embedFile("spirv/rectangle.frag.spv")),
    //         .depth_state = .{
    //             .write_enabled = false,
    //             .test_enabled = false,
    //             .compare_op = .greater,
    //         },
    //         .rasterisation_state = .{
    //             .polygon_mode = .fill,
    //         },
    //     },
    //     null,
    //     RectanglePipelinePushData,
    // );
    // errdefer self.rectangle_pipeline.deinit(self.allocator);

    self.mesh_pipeline = try graphics.GraphicsPipeline.init(
        allocator,
        .{
            .color_attachment_formats = &.{swapchain.surface_format.format},
            .vertex_shader_binary = @alignCast(4, @embedFile("renderer_gui_mesh_vert.spv")),
            .fragment_shader_binary = @alignCast(4, @embedFile("renderer_gui_mesh_frag.spv")),
            .depth_state = .{
                .write_enabled = false,
                .test_enabled = false,
                .compare_op = .greater,
            },
            .rasterisation_state = .{
                .polygon_mode = .fill,
            },
            .blend_state = .{
                .blend_enabled = true,
            },
        },
        null,
        MeshPipelinePushData,
    );
    errdefer self.mesh_pipeline.deinit(self.allocator);

    self.command_buffer = try graphics.CommandBuffer.init(.graphics);
    errdefer self.command_buffer.deinit();

    self.rectangles_buffer = try graphics.Buffer.init(4096 * @sizeOf(Rectangle), .storage);
    errdefer self.rectangles_buffer.deinit();

    // self.rectangle_pipeline.setDescriptorBuffer(0, 0, self.rectangles_buffer);

    const max_vertices = 50_000;
    const max_indices = 50_000;

    self.vertices_buffer = try graphics.Buffer.init(max_vertices * @sizeOf(Vertex), .storage);
    errdefer self.vertices_buffer.deinit();

    self.vertices_staging_buffer = try graphics.Buffer.init(max_vertices * @sizeOf(Vertex), .staging);
    errdefer self.vertices_staging_buffer.deinit();

    self.mesh_pipeline.setDescriptorBuffer(0, 0, self.vertices_buffer);

    self.indices_buffer = try graphics.Buffer.init(max_indices * @sizeOf(u16), .index);
    errdefer self.indices_buffer.deinit();

    self.indices_staging_buffer = try graphics.Buffer.init(max_indices * @sizeOf(u16), .staging);
    errdefer self.indices_staging_buffer.deinit();

    try initImGui();
    errdefer deinitImGui();
}

fn initImGui() !void {
    const io: *imgui.ImGuiIO = @ptrCast(*imgui.ImGuiIO, imgui.igGetIO());

    var pixel_pointer: [*c]u8 = undefined;
    var width: c_int = 0;
    var height: c_int = 0;
    var out_bytes_per_pixel: c_int = 0;

    imgui.ImFontAtlas_GetTexDataAsRGBA32(io.Fonts, &pixel_pointer, &width, &height, &out_bytes_per_pixel);

    const font_texture = try createTexture(pixel_pointer[0 .. @intCast(u32, width) * @intCast(u32, height) * @sizeOf(u32)], @intCast(u32, width), @intCast(u32, height));

    io.Fonts.*.TexID = @intToPtr(*anyopaque, @enumToInt(font_texture));
}

fn deinitImGui() void {}

pub fn deinit() void {
    // defer self.rectangle_pipeline.deinit(self.allocator);
    defer self.mesh_pipeline.deinit(self.allocator);
    defer self.command_buffer.deinit();
    defer self.rectangles_buffer.deinit();
    defer self.rectangles.deinit(self.allocator);
    defer self.vertices_buffer.deinit();
    defer self.vertices_staging_buffer.deinit();
    defer self.indices_buffer.deinit();
    defer self.indices_staging_buffer.deinit();
    defer self.scissors.deinit(self.allocator);
    defer self.textures.deinit(self.allocator);
    defer for (self.textures.items) |*texture| {
        defer texture.image.deinit();
        defer texture.sampler.deinit();
    };
    defer deinitImGui();
}

pub fn begin(color_target_image: *const graphics.Image) void {
    self.color_target_image = color_target_image;
    self.rectangles.clearRetainingCapacity();
    self.scissors.clearRetainingCapacity();
}

pub const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: u32,
};

///All coordinates are 16 bit "pixel" coordinates, which are local or global depending
///on the Pipeline
pub const Rectangle = extern struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    color: u32,
    border_radius: f32 = 0,
};

pub fn drawRectangle(rectangle: Rectangle) void {
    self.rectangles.append(self.allocator, rectangle) catch unreachable;
}

pub fn renderImGuiDrawData(draw_data: *const imgui.ImDrawData) !void {
    if (draw_data.CmdListsCount == 0 or !draw_data.Valid) return;

    {
        try self.command_buffer.begin();
        defer self.command_buffer.end();

        //Upload
        {
            {
                std.debug.assert(draw_data.CmdListsCount != 0);

                var command_list_index: usize = 0;

                var vertex_offset: usize = 0;
                var index_offset: usize = 0;

                const staging_vertices = try self.vertices_staging_buffer.map(imgui.ImDrawVert);
                const staging_indices = try self.indices_staging_buffer.map(u16);

                while (command_list_index < @intCast(usize, draw_data.CmdListsCount)) : (command_list_index += 1) {
                    const command_list: *imgui.ImDrawList = draw_data.CmdLists[command_list_index];

                    const vertices: []imgui.ImDrawVert = command_list.VtxBuffer.Data[0..@intCast(usize, command_list.VtxBuffer.Size)];
                    const indices: []u16 = command_list.IdxBuffer.Data[0..@intCast(usize, command_list.IdxBuffer.Size)];

                    @memcpy(@ptrCast([*]u8, staging_vertices.ptr + vertex_offset), @ptrCast([*]u8, vertices.ptr), vertices.len * @sizeOf(imgui.ImDrawVert));

                    @memcpy(@ptrCast([*]u8, staging_indices.ptr + index_offset), @ptrCast([*]u8, indices.ptr), indices.len * @sizeOf(u16));

                    //Would use this code, but not sure if it generates a good memcpy
                    // std.mem.copy(imgui.ImDrawVert, staging_vertices[vertex_offset..vertex_offset + vertices.len], vertices);
                    // std.mem.copy(u16, staging_indices[index_offset..index_offset + indices.len], indices);

                    vertex_offset += vertices.len;
                    index_offset += indices.len;
                }

                self.command_buffer.copyBuffer(
                    self.vertices_staging_buffer,
                    0,
                    vertex_offset * @sizeOf(imgui.ImDrawVert),
                    self.vertices_buffer,
                    0,
                    vertex_offset * @sizeOf(imgui.ImDrawVert),
                );

                self.command_buffer.copyBuffer(
                    self.indices_staging_buffer,
                    0,
                    index_offset * @sizeOf(u16),
                    self.indices_buffer,
                    0,
                    index_offset * @sizeOf(u16),
                );

                self.command_buffer.bufferBarrier(self.vertices_buffer, .{
                    .source_stage = .{
                        .copy = true,
                    },
                    .source_access = .{ .transfer_write = true },
                    .destination_stage = .{
                        .vertex_shader = true,
                    },
                    .destination_access = .{ .shader_read = true },
                });

                self.command_buffer.bufferBarrier(self.indices_buffer, .{
                    .source_stage = .{ .copy = true },
                    .source_access = .{ .transfer_write = true },
                    .destination_stage = .{ .index_input = true },
                    .destination_access = .{ .index_read = true },
                });
            }
        }

        //#Color Pass 1: main
        {
            self.command_buffer.beginRenderPass(0, 0, window.getWidth(), window.getHeight(), &[_]graphics.CommandBuffer.Attachment{.{
                .image = self.color_target_image,
            }}, null);
            defer self.command_buffer.endRenderPass();

            self.command_buffer.setGraphicsPipeline(self.mesh_pipeline);
            self.command_buffer.setViewport(0, @intToFloat(f32, window.getHeight()), @intToFloat(f32, window.getWidth()), -@intToFloat(f32, window.getHeight()), 0, 1);
            self.command_buffer.setScissor(0, 0, window.getWidth(), window.getHeight());

            // const projection = zalgebra.orthographic(0, @intToFloat(f32, window.getWidth()), 0, @intToFloat(f32, window.getHeight()), 0, 1);

            var ortho = [4][4]f32{
                .{ 2.0, 0.0, 0.0, 0.0 },
                .{ 0.0, -2.0, 0.0, 0.0 },
                .{ 0.0, 0.0, -1.0, 0.0 },
                .{ -1.0, 1.0, 0.0, 1.0 },
            };
            ortho[0][0] /= @intToFloat(f32, window.getWidth());
            ortho[1][1] /= @intToFloat(f32, window.getHeight());

            self.command_buffer.setIndexBuffer(self.indices_buffer, .u16);

            {
                var command_list_index: usize = 0;

                var vertex_offset: usize = 0;
                var index_offset: usize = 0;

                while (command_list_index < @intCast(usize, draw_data.CmdListsCount)) : (command_list_index += 1) {
                    const command_list: *imgui.ImDrawList = draw_data.CmdLists[command_list_index];

                    const vertices: []imgui.ImDrawVert = command_list.VtxBuffer.Data[0..@intCast(usize, command_list.VtxBuffer.Size)];
                    const indices: []u16 = command_list.IdxBuffer.Data[0..@intCast(usize, command_list.IdxBuffer.Size)];

                    var command_index: usize = 0;

                    while (command_index < @intCast(usize, command_list.CmdBuffer.Size)) : (command_index += 1) {
                        const command: imgui.ImDrawCmd = command_list.CmdBuffer.Data[command_index];

                        self.command_buffer.setPushData(MeshPipelinePushData, .{
                            .projection = ortho,
                            .texture_index = @intCast(u32, @ptrToInt(command.TextureId)),
                        });

                        self.command_buffer.setScissor(@floatToInt(u32, @max(command.ClipRect.x, 0)), @floatToInt(u32, @max(command.ClipRect.y, 0)), @floatToInt(u32, @min(command.ClipRect.z, @intToFloat(f32, window.getWidth()))) - @floatToInt(u32, @max(command.ClipRect.x, 0)), @floatToInt(u32, @min(command.ClipRect.w, @intToFloat(f32, window.getHeight()))) - @floatToInt(u32, @max(command.ClipRect.y, 0)));

                        self.command_buffer.drawIndexed(command.ElemCount, 1, @intCast(u32, index_offset) + command.IdxOffset, @intCast(i32, vertex_offset) + @intCast(i32, command.VtxOffset), 0);
                    }

                    vertex_offset += vertices.len;
                    index_offset += indices.len;
                }
            }
        }
    }

    //quite slow but will do for now
    try self.command_buffer.submitAndWait();
}
