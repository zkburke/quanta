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

const graphics = quanta.graphics;
const Renderer3D = quanta.renderer.Renderer3D;

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

    const test_scene_file_path = "zig-out/bin/assets/Suzanne";

    const test_scene_fd = try std.os.open(test_scene_file_path, std.os.O.RDONLY, std.os.S.IRUSR | std.os.S.IWUSR);
    defer std.os.close(test_scene_fd);

    const test_scene_fd_stat = try std.os.fstat(test_scene_fd);

    std.log.info("test_scene_fd_stat.size = {}", .{ test_scene_fd_stat.size });

    const test_scene_import_blob = try std.os.mmap(null, @intCast(usize, test_scene_fd_stat.size), std.os.PROT.READ, std.os.MAP.PRIVATE, test_scene_fd, 0);
    defer std.os.munmap(test_scene_import_blob);

    const test_scene_import = try gltf.decode(allocator, test_scene_import_blob);
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

    for (test_scene_import.materials) |material, i|
    {
        test_scene_materials[i] = test_scene_materials_by_texture[material.albedo_texture_index];
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

    _ = second_mesh;

    // const material2 = try Renderer3D.createMaterial(
    //     wood_floor_import.data, 
    //     wood_floor_import.width, 
    //     wood_floor_import.height, 
    //     .{ 1, 0.4, 0.4, 1 }
    // );

    // const material = try Renderer3D.createMaterial(
    //     tileset_import.data, 
    //     tileset_import.width, 
    //     tileset_import.height, 
    //     .{ 1, 1, 1, 1 }
    // );

    const time_start = std.time.milliTimestamp();

    const target_frame_time: i64 = 16; 

    var delta_time: i64 = target_frame_time;

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
        const time_begin = std.time.milliTimestamp();

        defer 
        {
            delta_time = std.time.milliTimestamp() - time_begin;
            
            if (delta_time < target_frame_time)
            {
                //Slow down the game loop
                // std.time.sleep(@intCast(u64, (target_frame_time - delta_time) * std.time.ns_per_ms));
            }
        }

        const time = std.time.milliTimestamp() - time_start;

        _ = time;

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
                const camera_speed = @splat(3, @as(f32, 10)) * @splat(3, @intToFloat(f32, delta_time) / 1000);

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

        //draw
        {
            try Renderer3D.beginRender(camera);
            defer Renderer3D.endRender();

            for (test_scene_import.sub_meshes) |sub_mesh, i|
            {
                Renderer3D.drawMesh(test_scene_meshes[i], test_scene_materials[sub_mesh.material_index], quanta.math.zalgebra.Mat4 { .data = sub_mesh.transform });
            }

            // const y_offset = std.math.sin(@intToFloat(f32, time) * 0.001);

            if (false)
            {
                var i: isize = 0;

                const mesh_square_size = 10;

                while (i < mesh_square_size) : (i += 1)
                {
                    var j: isize = 0;

                    while (j < mesh_square_size) : (j += 1)
                    {
                            // Renderer3D.drawMesh(if (@rem(i, 2) == 0) triangle_mesh else triangle_mesh, if (@rem(i, 2) == 0) material else material2, quanta.math.zalgebra.Mat4.fromTranslate(
                            // .{  
                                // .data = .{ 5 + @intToFloat(f32, -1 * i * 10), 0.5 + y_offset + @intToFloat(f32, (i + j * mesh_square_size)) / 100, @intToFloat(f32, -1 * j * 10) }
                            // }
                        // ));
                    }
                }

                // Renderer3D.drawMesh(triangle_mesh, material, quanta.math.zalgebra.Mat4.fromTranslate(
                    // .{  
                        // .data = .{ 0, y_offset, 0 }
                    // }
                // ));

                // Renderer3D.drawMesh(second_mesh, material2, quanta.math.zalgebra.Mat4.fromRotation(
                    // y_offset * 60,
                    // .{  
                        // .data = .{ 1, 0, 0 }
                    // }
                // ));
            }
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