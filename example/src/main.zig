const std = @import("std");
const builtin = @import("builtin");
const quanta = @import("quanta");
const windowing = quanta.windowing;
const window = quanta.windowing.window;
const GraphicsContext = quanta.graphics.Context;
const Swapchain = quanta.graphics.Swapchain;
const CommandBuffer = quanta.graphics.CommandBuffer;
const GraphicsPipeline = quanta.graphics.GraphicsPipeline;
const Buffer = quanta.graphics.Buffer;
const Image = quanta.graphics.Image;
const Sampler = quanta.graphics.Sampler;
const png = quanta.asset.importers.png;
const gltf = quanta.asset.importers.gltf;
const zalgebra = quanta.math.zalgebra;
const nk = quanta.nuklear.nuklear;
const imgui = quanta.imgui.cimgui;
const asset = quanta.asset;

const vk = quanta.graphics.vulkan;
const graphics = quanta.graphics;
const Renderer3D = quanta.renderer.Renderer3D;
const RendererGui = quanta.renderer_gui.RendererGui;

const shaders = @import("shaders.zig");
const assets = @import("assets");

fn packUnorm4x8(v: [4]f32) u32
{
    const Unorm4x8 = packed struct(u32)
    {
        x: u8,
        y: u8,
        z: u8,
        w: u8,
    };

    const x = @floatToInt(u8, v[0] * @intToFloat(f32, std.math.maxInt(u8)));
    const y = @floatToInt(u8, v[1] * @intToFloat(f32, std.math.maxInt(u8)));
    const z = @floatToInt(u8, v[2] * @intToFloat(f32, std.math.maxInt(u8)));
    const w = @floatToInt(u8, v[3] * @intToFloat(f32, std.math.maxInt(u8)));

    return @bitCast(u32, Unorm4x8 {
        .x = x,
        .y = y,
        .z = z, 
        .w = w,
    });
}

fn nkAlloc(_: nk.nk_handle, _: ?*anyopaque, size: nk.nk_size) callconv(.C) ?*anyopaque
{
    return std.c.malloc(size);
}

fn nkFree(_: nk.nk_handle, ptr: ?*anyopaque) callconv(.C) void
{
    std.c.free(ptr);
}

fn nkFontWidth(_ : nk.nk_handle, _: f32, _: [*c]const u8, _: c_int) callconv(.C) f32
{
    return 50;
}

fn nkFontQuery(_: nk.nk_handle, _: f32, _: [*c]nk.struct_nk_user_font_glyph, _: nk.nk_rune, _: nk.nk_rune) callconv(.C) void
{

}

fn nkTextFormat(ctx: *nk.nk_context, comptime format: []const u8, args: anytype) void 
{
    var format_buf: [4096 * 8]u8 = undefined;

    const text = std.fmt.bufPrint(&format_buf, format, args) catch unreachable;

    nk.nk_text(ctx, text.ptr, @intCast(c_int, text.len), nk.NK_TEXT_ALIGN_LEFT);
}

//should be generated by the assets build step
const example_assets = struct 
{
    const sponza = @intToEnum(asset.Archive.AssetDescriptor, 0);
    const gm_construct = @intToEnum(asset.Archive.AssetDescriptor, 1);
    const gm_castle_island = @intToEnum(asset.Archive.AssetDescriptor, 2);
    const environment_map = @intToEnum(asset.Archive.AssetDescriptor, 3);
};

pub fn main() !void 
{
    std.log.debug("All your {s} are belong to us.", .{ "codebase" });
    std.log.debug("{s}", .{ "debug" });
    std.log.warn("{s}", .{ "warn" });
    std.log.err("{s}", .{ "err" });

    var gpa = if (builtin.mode == .Debug)
        std.heap.GeneralPurposeAllocator(.{}) {}
    else {};
    defer if (builtin.mode == .Debug) std.debug.assert(!gpa.deinit());

    const allocator = if (builtin.mode == .Debug) gpa.allocator() else std.heap.c_allocator;

    try window.init(1600, 900, "Quanta Example");
    defer window.deinit();

    const pipeline_cache_file_path = "pipeline_cache";

    {
        // var pipeline_cache_data: []u8 = &[_]u8 {};

        // const file = std.fs.cwd().openFile(pipeline_cache_file_path, .{}) catch try std.fs.cwd().createFile(pipeline_cache_file_path, .{ .read = true });
        // defer file.close();

        // pipeline_cache_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        // defer allocator.free(pipeline_cache_data);

        // std.log.debug("pipeline_cache_data.len = {}", .{ pipeline_cache_data.len });

        try GraphicsContext.init(allocator, &.{});
    }

    defer GraphicsContext.deinit();

    defer if (false)
    {
        const pipeline_cache_data = GraphicsContext.getPipelineCacheData() catch unreachable;
        defer allocator.free(pipeline_cache_data);

        const file = std.fs.cwd().openFile(pipeline_cache_file_path, .{ .mode = .write_only }) catch unreachable;
        defer file.close();

        file.seekTo(0) catch unreachable;

        file.writeAll(pipeline_cache_data) catch unreachable;
    };

    var swapchain = try Swapchain.init(allocator, .{ .width = window.getWidth(), .height = window.getHeight() });
    defer swapchain.deinit();

    try Renderer3D.init(allocator, &swapchain);
    defer Renderer3D.deinit();

    std.debug.assert(imgui.igCreateContext(null) != null);
    defer imgui.igDestroyContext(imgui.igGetCurrentContext());

    try quanta.imgui.driver.init();
    defer quanta.imgui.driver.deinit();

    try RendererGui.init(allocator, swapchain);
    defer RendererGui.deinit();

    var asset_archive_file_path = "zig-out/bin/assets/example_assets_archive";

    const asset_archive_fd = try std.os.open(asset_archive_file_path, std.os.O.RDONLY, std.os.S.IRUSR | std.os.S.IWUSR);
    defer std.os.close(asset_archive_fd);

    const asset_archive_fd_stat = try std.os.fstat(asset_archive_fd);

    std.log.info("assets_archive size = {}", .{ asset_archive_fd_stat.size });

    const asset_archive_blob = try std.os.mmap(null, @intCast(usize, asset_archive_fd_stat.size), std.os.PROT.READ, std.os.MAP.PRIVATE, asset_archive_fd, 0);
    defer std.os.munmap(asset_archive_blob);

    const asset_archive = try asset.Archive.decode(allocator, asset_archive_blob);

    std.log.info("{any}", .{ asset_archive.assets.len });
    std.log.info("{any}", .{ asset_archive.assets });
    
    const test_scene_blob = asset_archive.getAssetData(example_assets.sponza);

    const test_scene_import = try gltf.decode(allocator, test_scene_blob);
    defer gltf.decodeFree(test_scene_import, allocator);

    const test_scene_meshes = try allocator.alloc(Renderer3D.MeshHandle, test_scene_import.sub_meshes.len);
    defer allocator.free(test_scene_meshes);

    const test_scene_materials_by_texture = try allocator.alloc(Renderer3D.MaterialHandle, test_scene_import.textures.len);
    defer allocator.free(test_scene_materials_by_texture);

    const test_scene_materials = try allocator.alloc(Renderer3D.MaterialHandle, test_scene_import.materials.len);
    defer allocator.free(test_scene_materials);

    for (test_scene_import.sub_meshes) |sub_mesh, i|
    {
        test_scene_meshes[i] = try Renderer3D.createMesh(
            test_scene_import.vertex_positions[sub_mesh.vertex_offset..sub_mesh.vertex_offset + sub_mesh.vertex_count],
            test_scene_import.vertices[sub_mesh.vertex_offset..sub_mesh.vertex_offset + sub_mesh.vertex_count], 
            test_scene_import.indices[sub_mesh.index_offset..sub_mesh.index_offset + sub_mesh.index_count],
            sub_mesh.bounding_min,
            sub_mesh.bounding_max,
        );
    }

    for (test_scene_import.textures) |texture, i|
    {
        test_scene_materials_by_texture[i] = try Renderer3D.createMaterial(
            texture.data,
            texture.width, 
            texture.height, 
            .{ 1, 1, 1, 1 },
        );
    }

    if (test_scene_materials_by_texture.len != 0)
    {
        for (test_scene_import.materials) |material, i|
        {
            test_scene_materials[i] = test_scene_materials_by_texture[material.albedo_texture_index];
        }
    }
    else 
    {
        test_scene_materials[0] = try Renderer3D.createMaterial(null, null, null, .{ 1, 1, 1, 1 });
    }

    const triangle_mesh = try Renderer3D.createMesh(
        &[_][3]f32 
        {
            .{ 0.5, 0.5, 0 },
            .{ -0.5, 0.5, 0 },
            .{ 0, -0.5, 0 },
        },
        &[_]Renderer3D.Vertex
        {
            .{  
                .normal = .{ 0, 0, 0 },
                .color = packUnorm4x8(.{ 1, 0, 0, 1 }),
                .uv = .{ 0, 0 },
            },
            .{  
                .normal = .{ 0, 0, 0 },
                .color = packUnorm4x8(.{ 0, 1, 0, 1 }),
                .uv = .{ 1, 0 },
            },
            .{  
                .normal = .{ 0, 0, 0 },
                .color = packUnorm4x8(.{ 0, 0, 1, 0.25 }),
                .uv = .{ 0.5, 1 },
            },
        }, 
        &[_]u32 { 0, 1, 2 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    );

    _ = triangle_mesh;

    const second_mesh = try Renderer3D.createMesh(
        &[_][3]f32 
        {
            .{ 0.5, 0.5, 0 },
            .{ -0.5, 0.5, 0 },
            .{ 0, -0.5, 0 },
        },
        &[_]Renderer3D.Vertex
        {
            .{  
                .normal = .{ 0, 0, 0 },
                .color = packUnorm4x8(.{ 1, 1, 1, 1 }),
                .uv = .{ 0, 0 },
            },
            .{  
                .normal = .{ 0, 0, 0 },
                .color = packUnorm4x8(.{ 1, 1, 1, 1 }),
                .uv = .{ 1, 0 },
            },
            .{  
                .normal = .{ 0, 0, 0 },
                .color = packUnorm4x8(.{ 1, 1, 1, 1 }),
                .uv = .{ 0.5, 1 },
            },
        }, 
        &[_]u32 { 0, 1, 2 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    );

    const environment_map_data = asset_archive.getAssetData(example_assets.environment_map);

    const scene = try Renderer3D.createScene(
        1, 
        50_000, 
        environment_map_data, 
        1024, 1024
    );
    defer Renderer3D.destroyScene(scene);

    for (test_scene_import.sub_meshes) |sub_mesh, i|
    {
        try Renderer3D.sceneAddStaticMesh(
            scene, 
            test_scene_meshes[i], 
            test_scene_materials[sub_mesh.material_index], 
            quanta.math.zalgebra.Mat4 { .data = sub_mesh.transform }
        );
    }

    _ = second_mesh;

    const target_frame_time: f32 = 16; 

    var delta_time: f32 = target_frame_time;

    var camera = Renderer3D.Camera
    {
        .translation = .{ 0, 3, 12.5 },
        .target = .{ 0, 0, 0 },
        .fov = 60,
    };

    var camera_position = @Vector(3, f32) { 8.7, 5.7, 0.9 };
    var camera_front = @Vector(3, f32) { -0.9, -0.1, -0.2 };
    var camera_up = @Vector(3, f32) { 0, 1, 0 };
    var yaw: f32 = 168.1;
    var pitch: f32 = -9.1;

    var last_mouse_x: f32 = 0;
    var last_mouse_y: f32 = 0;
    var camera_enable = false;
    var camera_enable_changed = false;

    while (!window.shouldClose())
    {
        const time_begin = std.time.nanoTimestamp();

        if (!camera_enable_changed and window.window.getKey(.tab) == .press)
        {
            camera_enable = !camera_enable;

            if (camera_enable)
            {
                try window.window.setInputMode(.cursor, .disabled);
            }
            else 
            {
                try window.window.setInputMode(.cursor, .normal);
            }

            camera_enable_changed = true;
        }

        if (window.window.getKey(.tab) == .release)
        {
            camera_enable_changed = false;
        }

        //update
        {
            const x_position = @floatCast(f32, (try window.window.getCursorPos()).xpos);
            const y_position = @floatCast(f32, (try window.window.getCursorPos()).ypos);

            const x_offset = x_position - last_mouse_x;
            const y_offset = last_mouse_y - y_position;

            last_mouse_x = x_position;
            last_mouse_y = y_position;

            if (camera_enable)
            {
                const sensitivity = 0.1;
                const camera_speed = @splat(3, @as(f32, 10)) * @splat(3, delta_time / 1000);

                yaw += x_offset * sensitivity;
                pitch += y_offset * sensitivity;

                pitch = std.math.clamp(pitch, -89, 89);

                camera_front = zalgebra.Vec3.norm(
                    .{ 
                        .data = .{
                            @cos(zalgebra.toRadians(-yaw)) * @cos(zalgebra.toRadians(pitch)),
                            @sin(zalgebra.toRadians(pitch)),
                            @sin(zalgebra.toRadians(-yaw)) * @cos(zalgebra.toRadians(pitch)),
                        } 
                    }
                ).data;

                if (window.window.getKey(.w) == .press)
                {
                    camera_position += camera_speed * camera_front;
                } 
                else if (window.window.getKey(.s) == .press)
                {
                    camera_position -= camera_speed * camera_front;
                }

                if (window.window.getKey(.a) == .press)
                {
                    camera_position += zalgebra.Vec3.norm(zalgebra.Vec3.cross(.{ .data = camera_front }, .{ .data = camera_up })).mul(.{ .data = camera_speed }).data;
                }
                else if (window.window.getKey(.d) == .press)
                {
                    camera_position -= zalgebra.Vec3.norm(zalgebra.Vec3.cross(.{ .data = camera_front }, .{ .data = camera_up })).mul(.{ .data = camera_speed }).data;
                }
            }

            camera.target = camera_position + camera_front;
            camera.translation = camera_position;
        }

        const image_index = swapchain.image_index;
        const image = swapchain.swap_images[image_index];

        //sneaky hack due to our incomplete swapchain abstraction
        var color_image: Image = undefined;

        color_image.view = image.view;
        color_image.handle = image.image;
        color_image.aspect_mask = .{ .color_bit = true };

        {
            try Renderer3D.beginSceneRender(scene, &.{ Renderer3D.View { .camera = camera } });
            defer Renderer3D.endSceneRender(scene);
        }

        //imgui gui
        if (false)
        {
            try quanta.imgui.driver.begin();
            defer quanta.imgui.driver.end();

            const widgets = quanta.imgui.widgets;

            imgui.igNewFrame();

            imgui.igShowDemoWindow(null);

            if (widgets.begin("lol"))
            {
                widgets.textFormat("Frame time {d:.2}", .{ delta_time });
                widgets.textFormat("hello {s}!", .{ "world" });

                if (widgets.button("Lol"))
                {
                    std.log.info("sus", .{});
                }

                widgets.text("Renderer Statistics:");

                widgets.textFormat(
                    "depth_pre_pass_time = {d:.2}ms", 
                    .{ @intToFloat(f64, Renderer3D.getStatistics().depth_prepass_time) / @intToFloat(f64, std.time.ns_per_ms) }
                );

                widgets.textFormat(
                    "geometry_pass_time = {d:.2}ms", 
                    .{ @intToFloat(f64, Renderer3D.getStatistics().geometry_pass_time) / @intToFloat(f64, std.time.ns_per_ms) }
                );
            }
            widgets.end();

            imgui.igRender();
        }

        //draw imgui
        if (false)
        {
            RendererGui.begin(&color_image);
            RendererGui.renderImGuiDrawData(imgui.igGetDrawData()) catch unreachable;
        }

        _ = try GraphicsContext.self.vkd.queuePresentKHR(GraphicsContext.self.graphics_queue, &.{.wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &image.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &swapchain.handle),
            .p_image_indices = @ptrCast([*]const u32, &image_index),
            .p_results = null,
        });

        const result = try GraphicsContext.self.vkd.acquireNextImageKHR(
            GraphicsContext.self.device,
            swapchain.handle,
            std.math.maxInt(u64),
            swapchain.next_image_acquired,
            .null_handle,
        );

        std.mem.swap(vk.Semaphore, &swapchain.swap_images[result.image_index].image_acquired, &swapchain.next_image_acquired);
        swapchain.image_index = result.image_index;

        {
            delta_time = @intToFloat(f32, std.time.nanoTimestamp() - time_begin) / @intToFloat(f32, std.time.ns_per_ms);
        }
    }

    try GraphicsContext.self.vkd.deviceWaitIdle(GraphicsContext.self.device);
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void 
{
    const terminal_red = "\x1B[31m";
    const terminal_yellow = "\x1B[33m";
    const terminal_blue = "\x1B[34m";
    const terminal_green = "\x1B[32m";

    const color_begin = switch (message_level)
    {
        .err => terminal_red,
        .warn => terminal_yellow,
        .info => terminal_blue,
        .debug => terminal_green,
    };

    const color_end = "\x1B[0;39m";

    const level_txt = "[" ++ color_begin ++ comptime message_level.asText() ++ color_end ++ "]";
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    nosuspend stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}