pub fn renderToGraph(
    graph: *quanta.rendering.graph.Builder,
    draw_data: *const imgui.ImDrawData,
    ///The output color attachment to render to
    target: *Image,
) !void {
    //TODO: pass this as a parameter

    if (draw_data.CmdListsCount == 0 or !draw_data.Valid) {
        return;
    }

    const font_atlas = blk: {
        const io: *imgui.ImGuiIO = @as(*imgui.ImGuiIO, @ptrCast(imgui.igGetIO()));

        var pixel_pointer: [*c]u8 = undefined;
        var width: c_int = 0;
        var height: c_int = 0;
        var out_bytes_per_pixel: c_int = 0;

        imgui.ImFontAtlas_GetTexDataAsAlpha8(
            io.Fonts,
            &pixel_pointer,
            &width,
            &height,
            &out_bytes_per_pixel,
        );

        const image_contents_size: usize = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * @sizeOf(u8);

        var font_image = graph.createImage(
            @src(),
            .{
                .format = .r8_unorm,
                .width = @intCast(width),
                .height = @intCast(height),
                .depth = 1,
            },
        );

        // io.Fonts.*.TexID = @as(*anyopaque, @ptrFromInt(font_image.getHandle()));

        const FontInit = struct {
            var initialized: bool = false;
        };

        //TODO: how do we handle resources who's data does not change
        //We *could* memcmp the inputs if we really want to but that's just silly(?)
        if (!FontInit.initialized) {
            graph.beginTransferPass(@src());
            defer graph.endTransferPass();

            graph.updateImage(
                &font_image,
                0,
                u8,
                pixel_pointer[0..image_contents_size],
            );

            FontInit.initialized = true;
        }

        break :blk .{
            .font_image = font_image,
        };
    };

    const max_draws = 32_000;

    var draw_cmd_buffer = graph.createBuffer(@src(), .{
        .size = max_draws * @sizeOf(quanta.rendering.graph.DrawIndexedIndirectCommand),
    });

    var draw_data_buffer = graph.createBuffer(@src(), .{
        .size = max_draws * @sizeOf(DrawData),
    });

    var draw_count_buffer = graph.createBuffer(@src(), .{ .size = @sizeOf(u32) });

    //upload
    //Could be it's own function (but that shouldn't be neccessary)
    const updated_buffers = blk: {
        const max_vertices = 100_000;
        const max_indices = 100_000;

        //Notice how these resources are local to this scope. We pass these resources as inputs to passes, so these variable names needn't be referenced
        var vertex_buffer = graph.createBuffer(@src(), .{ .size = max_vertices * @sizeOf(imgui.ImDrawVert) });
        var index_buffer = graph.createBuffer(@src(), .{ .size = max_indices * @sizeOf(u16) });

        //Upload buffers pass
        graph.beginTransferPass(@src());
        defer graph.endTransferPass();

        var vertex_offset: usize = 0;
        var index_offset: usize = 0;

        for (0..@intCast(draw_data.CmdListsCount)) |command_list_index| {
            const command_list: *imgui.ImDrawList = draw_data.CmdLists.Data[command_list_index];

            const vertices: []const imgui.ImDrawVert = command_list.VtxBuffer.Data[0..@as(usize, @intCast(command_list.VtxBuffer.Size))];
            const indices: []const u16 = command_list.IdxBuffer.Data[0..@as(usize, @intCast(command_list.IdxBuffer.Size))];

            graph.updateBuffer(
                &vertex_buffer,
                vertex_offset * @sizeOf(imgui.ImDrawVert),
                imgui.ImDrawVert,
                vertices,
            );

            graph.updateBuffer(
                &index_buffer,
                index_offset * @sizeOf(u16),
                u16,
                indices,
            );

            vertex_offset += vertices.len;
            index_offset += indices.len;
        }

        break :blk .{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
        };
    };

    const pipeline = graph.createRasterPipeline(
        @src(),
        .{
            .vertex_module = .{ .code = @alignCast(@embedFile("mesh.vert.spv")) },
            .fragment_module = .{ .code = @alignCast(@embedFile("mesh.frag.spv")) },
            .push_constant_size = @sizeOf(MeshPipelinePushData),
            .attachment_formats = &.{
                graph.imageGetFormat(target.*),
            },
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
    );

    const font_sampler = graph.createSampler(@src(), .{
        .min_filter = .linear,
        .mag_filter = .linear,
    });

    const general_image_sampler = graph.createSampler(@src(), .{
        .min_filter = .nearest,
        .mag_filter = .nearest,
    });

    const target_width = graph.imageGetWidth(target.*);
    const target_height = graph.imageGetHeight(target.*);

    var image_sampler_bump: u32 = 0;

    var vertex_offset: usize = 0;
    var index_offset: usize = 0;

    var output_draw_commands: std.ArrayListUnmanaged(quanta.rendering.graph.DrawIndexedIndirectCommand) = .{};
    var output_draws: std.ArrayListUnmanaged(DrawData) = .{};

    {
        graph.beginTransferPass(@src());
        defer graph.endTransferPass();

        //Do we really need bindless for this?
        graph.setRasterPipelineImageSampler(
            pipeline,
            2,
            image_sampler_bump,
            font_atlas.font_image,
            font_sampler,
        );

        image_sampler_bump += 1;

        for (0..@intCast(draw_data.CmdListsCount)) |command_list_index| {
            const command_list: *imgui.ImDrawList = draw_data.CmdLists.Data[command_list_index];

            const vertices: []imgui.ImDrawVert = command_list.VtxBuffer.Data[0..@as(usize, @intCast(command_list.VtxBuffer.Size))];
            const indices: []u16 = command_list.IdxBuffer.Data[0..@as(usize, @intCast(command_list.IdxBuffer.Size))];

            try output_draw_commands.ensureTotalCapacity(graph.scratch_allocator.allocator(), @intCast(command_list.CmdBuffer.Size));

            for (0..@intCast(command_list.CmdBuffer.Size)) |command_index| {
                const command: imgui.ImDrawCmd = command_list.CmdBuffer.Data[command_index];

                var texture_index: u32 = 1;

                if (command.TextureId != null) {
                    const image_handle: quanta.rendering.graph.ImageHandle = @enumFromInt(@intFromPtr(command.TextureId.?));
                    defer image_sampler_bump += 1;

                    const image = graph.imageFromPersistantHandle(image_handle);
                    //TODO: only set this once

                    graph.setRasterPipelineImageSampler(
                        pipeline,
                        2,
                        image_sampler_bump,
                        image.*,
                        general_image_sampler,
                    );

                    texture_index = image_sampler_bump + 1;
                }

                const window_width = @as(f32, @floatFromInt(target_width));
                const window_height = @as(f32, @floatFromInt(target_height));

                const scissor_min_x = @as(u32, @intFromFloat(@max(command.ClipRect.x, 0)));
                const scissor_min_y = @as(u32, @intFromFloat(@max(command.ClipRect.y, 0)));
                const scissor_max_x = @as(u32, @intFromFloat(@min(command.ClipRect.z, window_width))) -| @as(u32, @intFromFloat(@max(command.ClipRect.x, 0)));
                const scissor_max_y = @as(u32, @intFromFloat(@min(command.ClipRect.w, window_height))) -| @as(u32, @intFromFloat(@max(command.ClipRect.y, 0)));

                try output_draws.append(graph.scratch_allocator.allocator(), .{
                    .scissor_min = .{ scissor_min_x, scissor_min_y },
                    .scissor_max = .{ scissor_max_x, scissor_max_y },
                    .texture_index = texture_index,
                });

                try output_draw_commands.append(graph.scratch_allocator.allocator(), .{
                    .index_count = command.ElemCount,
                    .instance_count = 1,
                    .first_index = @as(u32, @intCast(index_offset)) + command.IdxOffset,
                    .vertex_offset = @as(i32, @intCast(vertex_offset)) + @as(i32, @intCast(command.VtxOffset)),
                    .first_instance = 0,
                });
            }

            vertex_offset += vertices.len;
            index_offset += indices.len;
        }

        graph.updateBuffer(&draw_count_buffer, 0, u32, &.{@intCast(output_draws.items.len)});
        graph.updateBuffer(&draw_cmd_buffer, 0, quanta.rendering.graph.DrawIndexedIndirectCommand, output_draw_commands.items);
        graph.updateBuffer(&draw_data_buffer, 0, DrawData, output_draws.items);
    }

    //Drawing
    {

        //Color output pass
        graph.beginRasterPass(
            @src(),
            &.{
                .{
                    .image = target,
                },
            },
            null,
            .entirety,
        );
        defer graph.endRasterPass();

        graph.setRasterPipeline(pipeline);
        graph.setRasterPipelineResourceBuffer(
            pipeline,
            0,
            0,
            updated_buffers.vertex_buffer,
        );

        graph.setRasterPipelineResourceBuffer(
            pipeline,
            1,
            0,
            draw_data_buffer,
        );

        graph.setViewport(
            0,
            @as(f32, @floatFromInt(target_height)),
            @as(f32, @floatFromInt(target_width)),
            -@as(f32, @floatFromInt(target_height)),
            0,
            1,
        );

        graph.setScissor(
            0,
            0,
            target_width,
            target_height,
        );

        graph.setIndexBuffer(updated_buffers.index_buffer, .u16);

        var ortho = [4][4]f32{
            .{ 2.0, 0.0, 0.0, 0.0 },
            .{ 0.0, -2.0, 0.0, 0.0 },
            .{ 0.0, 0.0, -1.0, 0.0 },
            .{ -1.0, 1.0, 0.0, 1.0 },
        };
        ortho[0][0] /= @as(f32, @floatFromInt(target_width));
        ortho[1][1] /= @as(f32, @floatFromInt(target_height));

        graph.setPushData(MeshPipelinePushData, .{
            .projection = ortho,
        });

        graph.drawIndexedIndirectCount(
            draw_cmd_buffer,
            0,
            @sizeOf(quanta.rendering.graph.DrawIndexedIndirectCommand),
            draw_count_buffer,
            0,
            max_draws,
        );
    }
}

const MeshPipelinePushData = extern struct {
    projection: [4][4]f32,
};

const DrawData = extern struct {
    scissor_min: [2]u32,
    scissor_max: [2]u32,
    texture_index: u32,
};

test {
    _ = renderToGraph;
}

const RendererGui = @This();
const std = @import("std");
const quanta = @import("quanta");
const imgui = @import("../root.zig").cimgui;
const Image = quanta.rendering.graph.Image;
