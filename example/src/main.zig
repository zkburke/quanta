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
const imguizmo = quanta.imgui.guizmo;
const entity_editor = quanta.imgui.entity_editor;
const asset = quanta.asset;

const quanta_components = quanta.ecs.components;
const transform_system = quanta.ecs.transform_system;
const velocity_system = quanta.ecs.velocity_system;
const acceleration_system = quanta.ecs.acceleration_system;

const vk = quanta.graphics.vulkan;
const graphics = quanta.graphics;
const Renderer3D = quanta.renderer.Renderer3D;
const RendererGui = quanta.renderer_gui.RendererGui;

const assets = @import("assets");

//should be generated by the assets build step
const example_assets = struct 
{
    const sponza = @intToEnum(asset.Archive.AssetDescriptor, 0);
    const gm_construct = @intToEnum(asset.Archive.AssetDescriptor, 1);
    const gm_castle_island = @intToEnum(asset.Archive.AssetDescriptor, 2);
    const environment_map = @intToEnum(asset.Archive.AssetDescriptor, 3);
    const test_scene = @intToEnum(asset.Archive.AssetDescriptor, 4);
    const lights_test = @intToEnum(asset.Archive.AssetDescriptor, 5);
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

    std.log.info("asset_archive.assets.len = {any}", .{ asset_archive.assets.len });
    
    const test_scene_blob = asset_archive.getAssetData(@intToEnum(asset.Archive.AssetDescriptor, 3));

    const test_scene_import = try gltf.decode(allocator, test_scene_blob);
    defer gltf.decodeFree(test_scene_import, allocator);

    const test_scene_meshes = try allocator.alloc(Renderer3D.MeshHandle, test_scene_import.sub_meshes.len);
    defer allocator.free(test_scene_meshes);

    const test_scene_textures = try allocator.alloc(Renderer3D.TextureHandle, test_scene_import.textures.len);
    defer allocator.free(test_scene_textures);

    const test_scene_materials = try allocator.alloc(Renderer3D.MaterialHandle, test_scene_import.materials.len);
    defer allocator.free(test_scene_materials);

    for (test_scene_import.sub_meshes, 0..) |sub_mesh, i|
    {
        test_scene_meshes[i] = try Renderer3D.createMesh(
            test_scene_import.vertex_positions[sub_mesh.vertex_offset..sub_mesh.vertex_offset + sub_mesh.vertex_count],
            test_scene_import.vertices[sub_mesh.vertex_offset..sub_mesh.vertex_offset + sub_mesh.vertex_count], 
            test_scene_import.indices[sub_mesh.index_offset..sub_mesh.index_offset + sub_mesh.index_count],
            sub_mesh.bounding_min,
            sub_mesh.bounding_max,
        );
    }

    for (test_scene_import.textures, 0..) |texture, i|
    {
        test_scene_textures[i] = try Renderer3D.createTexture(
            texture.data,
            texture.width, 
            texture.height, 
        );
    }

    if (test_scene_import.materials.len != 0)
    {
        for (test_scene_import.materials, 0..) |material, i|
        {
            std.log.info("material albedo index {}", .{ material.albedo_texture_index });
            std.log.info("material albedo {any}", .{ material.albedo });

            test_scene_materials[i] = try Renderer3D.createMaterial(
                if (material.albedo_texture_index != 0) test_scene_textures[material.albedo_texture_index - 1] else null,
                material.albedo,
                null,
                material.metalness,
                if (material.roughness_texture_index != 0) test_scene_textures[material.roughness_texture_index - 1] else null,
                material.roughness,
            );
        }
    }

    const environment_map_data = asset_archive.getAssetData(@intToEnum(asset.Archive.AssetDescriptor, 2));

    var ecs_scene = try quanta.ecs.ComponentStore.init(allocator);
    defer ecs_scene.deinit();

    const scene = try Renderer3D.createScene(
        1, 
        50_000,
        4096,
        environment_map_data, 
        1024, 1024,
    );
    defer Renderer3D.destroyScene(scene);

    for (test_scene_import.sub_meshes, 0..) |sub_mesh, i|
    {
        const decomposed = zalgebra.Mat4.decompose(.{ .data = sub_mesh.transform });
        const translation = decomposed.t;
        const rotation = decomposed.r.extractEulerAngles();
        const scale = decomposed.s;

        _ = try ecs_scene.entityCreate(.{
            quanta.ecs.components.Position { .x = translation.x(), .y = translation.y(), .z = translation.z() },
            quanta.ecs.components.Rotation { .x = rotation.x(), .y = rotation.y(), .z = rotation.z() },
            quanta.ecs.components.NonUniformScale { .x = scale.x(), .y = scale.y(), .z = scale.z() },
            quanta.ecs.components.RendererMesh { .mesh = test_scene_meshes[i], .material = test_scene_materials[sub_mesh.material_index] },
        });
    }

    const target_frame_time: f32 = 16; 

    var delta_time: f32 = target_frame_time;

    var camera = Renderer3D.Camera
    {
        .translation = .{ 0, 3, 12.5 },
        .target = .{ 0, 0, 0 },
        .fov = 60,
        .exposure = 1,
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

    var directional_light: Renderer3D.DirectionalLight = .{
        .direction = .{ -0.5, -1, -0.3 },  
        .diffuse = packUnorm4x8(.{ 0.45, 0.45, 0.45, 1 }),
        .intensity = 1
    };
    var enable_directional_light: bool = true;

    const time_at_start = std.time.milliTimestamp();

    const TestEnumComponent = enum 
    {
        no_state,
        state_0,
        state_1,
        ect_state,
    };

    const TestUnionComponent = union(enum)
    {
        no_state: void,
        state_0: u32,
        state_1: void,
        ect_state: void,
    };

    _ = try ecs_scene.entityCreate(
        .{
            quanta_components.Position { .x = 0, .y = 2, .z = 0 },
            quanta_components.Velocity { .x = 0, .y = 1, .z = 0 },
            TestEnumComponent.state_1,
            TestUnionComponent.state_1,
        }
    );

    const test_entity = try ecs_scene.entityCreate(
        .{
            quanta_components.Position { .x = 0, .y = 50, .z = 0 },
            quanta_components.PointLight {
                .intensity = 1000,
                .diffuse = .{ 1, 1, 1 },
            },
            quanta_components.Visibility { .is_visible = true },
        }
    );

    _ = try ecs_scene.entityCreate(
        .{
            quanta_components.Position { .x = 0, .y = 4, .z = 0 },
            quanta_components.Velocity { .x = 0, .y = 0.5, .z = 0 },
            quanta.ecs.ComponentStore.Entity.nil,
        }
    );

    const entity_b = try ecs_scene.entityCreate(
        .{
            quanta_components.Position { .x = 0, .y = -2, .z = 0 },
            quanta_components.Velocity { .x = 0, .y = 1, .z = 0 },
            quanta_components.Force { .x = 2, .y = 9.81, .z = 0 },
            quanta_components.Mass { .value = 10 },
            quanta_components.TerminalVelocity { .x = 0, .y = 0.01, .z = 0 },
            quanta_components.RendererMesh { .mesh = test_scene_meshes[0], .material = test_scene_materials[0] }
        }
    );    

    const entity_a = try ecs_scene.entityCreate(
        .{
            quanta_components.Position { .x = 0, .y = -2, .z = 0 },
            quanta_components.Velocity { .x = 0, .y = 1, .z = 0 },
            quanta_components.Force { .x = 2, .y = 9.81, .z = 0 },
            quanta_components.Mass { .value = 10 },
            quanta_components.TerminalVelocity { .x = 0, .y = 0.01, .z = 0 },
            quanta_components.RendererMesh { .mesh = test_scene_meshes[0], .material = test_scene_materials[0] },
        }
    );

    std.debug.assert(ecs_scene.entitiesAreIsomers(entity_a, entity_b));   

    var entity_debugger_commands = quanta.ecs.CommandBuffer.init(allocator);
    defer entity_debugger_commands.deinit();

    var selected_entity: ?quanta.ecs.ComponentStore.Entity = test_entity;

    var cloned_entity_last_frame: bool = false;

    var mouse_pressed_last_Frame: bool = false;

    while (!window.shouldClose())
    {
        const time_begin = std.time.nanoTimestamp();

        if (!camera_enable_changed and window.window.getKey(.tab) == .press)
        {
            camera_enable = !camera_enable;

            if (camera_enable)
            {
                window.window.setInputMode(.cursor, .disabled);
            }
            else 
            {
                window.window.setInputMode(.cursor, .normal);
            }

            camera_enable_changed = true;
        }

        if (window.window.getKey(.tab) == .release)
        {
            camera_enable_changed = false;
        }

        //update
        {
            const x_position = @floatCast(f32, window.window.getCursorPos().xpos);
            const y_position = @floatCast(f32, window.window.getCursorPos().ypos);

            const x_offset = x_position - last_mouse_x;
            const y_offset = last_mouse_y - y_position;

            last_mouse_x = x_position;
            last_mouse_y = y_position;

            if (camera_enable)
            {
                const sensitivity = 0.1;
                const camera_speed = @splat(3, @as(f32, 30)) * @splat(3, delta_time / 1000);

                yaw += x_offset * sensitivity;
                pitch += y_offset * sensitivity;

                pitch = std.math.clamp(pitch, -89, 89);

                camera_front = zalgebra.Vec3.norm(
                    .{ 
                        .data = .{
                            @cos(zalgebra.toRadians(yaw)) * @cos(zalgebra.toRadians(-pitch)),
                            @sin(zalgebra.toRadians(pitch)),
                            @sin(zalgebra.toRadians(yaw)) * @cos(zalgebra.toRadians(-pitch)),
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
                    camera_position -= zalgebra.Vec3.norm(zalgebra.Vec3.cross(.{ .data = camera_front }, .{ .data = camera_up })).mul(.{ .data = camera_speed }).data;
                }
                else if (window.window.getKey(.d) == .press)
                {
                    camera_position += zalgebra.Vec3.norm(zalgebra.Vec3.cross(.{ .data = camera_front }, .{ .data = camera_up })).mul(.{ .data = camera_speed }).data;
                }
            }

            camera.target = camera_position + camera_front;
            camera.translation = camera_position;
        }

        transform_system.run(&ecs_scene);
        acceleration_system.run(&ecs_scene, delta_time);
        quanta.ecs.force_system.run(&ecs_scene, delta_time);

        try quanta.ecs.system_scheduler.run(
            &ecs_scene, 
            &entity_debugger_commands, 
            .{
                velocity_system
            }
        );

        quanta.ecs.terminal_velocity_system.run(&ecs_scene);

        const image_index = swapchain.image_index;
        const image = swapchain.swap_images[image_index];

        //sneaky hack due to our incomplete swapchain abstraction
        var color_image: Image = undefined;

        color_image.view = image.view;
        color_image.handle = image.image;
        color_image.aspect_mask = .{ .color_bit = true };

        {
            try Renderer3D.beginSceneRender(
                scene, 
                &.{ Renderer3D.View { .camera = camera } },
                .{ .diffuse = packUnorm4x8(.{ 0.005, 0.005, 0.005, 1 }) },
                if (enable_directional_light) directional_light else null
            );
            defer Renderer3D.endSceneRender(scene);

            quanta.ecs.renderer3d_system.run(&ecs_scene, scene);   
            quanta.ecs.point_light_system.run(&ecs_scene, scene);

            if (true)
            {
                Renderer3D.scenePushPointLight(scene, .{
                    .position = .{ 0, 1, -4 },
                    .intensity = 10 + 40 * std.math.fabs(@sin(@intToFloat(f32, std.time.milliTimestamp() - time_at_start) / 1000)), 
                    .diffuse = packUnorm4x8(.{ 0.8, 0.4, 0.1, 1 }),
                });

                Renderer3D.scenePushPointLight(scene, .{
                    .position = .{ 4, 4, 4 },
                    .intensity = 10 + 40 * std.math.fabs(@sin(@intToFloat(f32, std.time.milliTimestamp() - time_at_start) / 1000)), 
                    .diffuse = packUnorm4x8(.{ 0.4, 0.8, 0.1, 1 }),
                });

                Renderer3D.scenePushPointLight(scene, .{
                    .position = .{ 80, 4, 4 },
                    .intensity = 400 + 600 * std.math.fabs(@sin(@intToFloat(f32, std.time.milliTimestamp() - time_at_start) / 1000)), 
                    .diffuse = packUnorm4x8(.{ 0.6, 0.6, 0.8, 1 }),
                });

                Renderer3D.scenePushPointLight(scene, .{
                    .position = .{ -80, 4, 4 },
                    .intensity = 600 + 600 * std.math.fabs(@sin(@intToFloat(f32, std.time.milliTimestamp() - time_at_start) / 1000)), 
                    .diffuse = packUnorm4x8(.{ 0.8, 0.5, 0.5, 1 }),
                });
            }

            Renderer3D.scenePushPointLight(scene, .{
                .position = .{ 4.0762, 35, 5.9 },
                .intensity = 1000, 
                .diffuse = packUnorm4x8(.{ 1, 1, 1, 1 }),
            });

            for (test_scene_import.point_lights) |point_light|
            {
                Renderer3D.scenePushPointLight(scene, .{ .position = point_light.position, .intensity = point_light.intensity, .diffuse = std.math.maxInt(u32) });
            }
        }

        //imgui gui
        if (true)
        {
            {
                try quanta.imgui.driver.begin();
                defer quanta.imgui.driver.end();

                const widgets = quanta.imgui.widgets;

                imgui.igNewFrame();
                imguizmo.ImGuizmo_SetOrthographic(false);
                imguizmo.ImGuizmo_BeginFrame();

                imgui.igShowDemoWindow(null);

                if (widgets.begin("Basic properties"))
                {
                    widgets.textFormat("Frame time {d:.2}", .{ delta_time });

                    if (widgets.button("Button test"))
                    {
                        std.log.info("Praise be the {s}", .{ "BIG BUTTON" });
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

                    _ = imgui.igDragFloat("Camera Exposure: ", &camera.exposure, 0.1, 0.1, 15, null, 0);

                    widgets.text("Directional Light: ");

                    _ = imgui.igDragFloat3("Direction: ", &directional_light.direction[0], 0.05, -1, 1, null, 0);
                    _ = imgui.igDragFloat("Intensity: ", &directional_light.intensity, 0.1, 0, 1, null, 0);
                }
                widgets.end();

                //Duplicate
                if (
                    window.getKeyDown(.left_control) and
                    window.getKeyDown(.d) and 
                    !cloned_entity_last_frame and 
                    selected_entity != null
                )
                {
                    entity_debugger_commands.entityClone(selected_entity.?);

                    cloned_entity_last_frame = true;
                }
                
                if (
                    !window.getKeyDown(.left_control) and 
                    !window.getKeyDown(.d)
                )
                {
                    cloned_entity_last_frame = false;
                }

                //Selection
                if (window.getMouseDown(.left) and !mouse_pressed_last_Frame)
                {
                    const mouse_pos = window.getMousePos();

                    std.log.info("mouse_pos = {d}, {d}", .{ mouse_pos[0], mouse_pos[1] });

                    const inverse_projection = zalgebra.Mat4.inv(.{ .data = camera.getProjectionNonInverse() });
                    const inverse_view = zalgebra.Mat4.inv(.{ .data = camera.getView() });

                    const normalized_pos = [2]f32 { 
                        ((mouse_pos[0] / @intToFloat(f32, window.getWidth())) - 0.5) * 2, 
                        ((mouse_pos[1] / @intToFloat(f32, window.getHeight())) - 0.5) * 2,
                    };

                    const screen_space_pos = inverse_projection.mulByVec4(.{ .data = .{ normalized_pos[0], normalized_pos[1], 0, 1 } });
                    const world_space_pos = inverse_view.mulByVec4(screen_space_pos);

                    std.log.info("world_space_pos (ray_origin) = {d}, {d}, {d}", .{ 
                        world_space_pos.data[0] / 1000.0, 
                        world_space_pos.data[1] / 1000.0,
                        world_space_pos.data[2] / 1000.0,
                    });

                    std.log.info("world_space_pos (ray_dir) = {d}, {d}, {d}", .{
                        camera_front[0],
                        camera_front[1],
                        camera_front[2],
                    });

                    const ray_origin = @Vector(3, f32) {
                        world_space_pos.data[0] / 1000.0, 
                        world_space_pos.data[1] / 1000.0,
                        world_space_pos.data[2] / 1000.0,
                    };

                    const ray_length = 1000;

                    const ray_direction = @Vector(3, f32) {
                        camera_front[0] * ray_length,
                        camera_front[1] * ray_length,
                        camera_front[2] * ray_length,
                    };

                    const intersection = quanta.physics.intersection;

                    var query = ecs_scene.query(
                        .{ 
                            quanta.ecs.components.Position, 
                            quanta.ecs.components.NonUniformScale, 
                            quanta.ecs.components.RendererMesh, 
                        }, .{}
                    );

                    var found_entity: ?quanta.ecs.ComponentStore.Entity = null;
                    var closest_t_max: f32 = std.math.inf_f32;

                    while (query.nextBlock()) |block|
                    {
                        for (
                            block.Position,
                            block.NonUniformScale,
                            block.RendererMesh,
                            0..
                        ) |position, scale, mesh, i|
                        {
                            const mesh_box = Renderer3D.getMeshBox(mesh.mesh);

                            const position_vector = @Vector(3, f32) { position.x, position.y, position.z };

                            const bounding_min = position_vector + (mesh_box.min * @Vector(3, f32) { scale.x, scale.y, scale.z });
                            const bounding_max = position_vector + (mesh_box.max * @Vector(3, f32) { scale.x, scale.y, scale.z });

                            const box_intersection = intersection.rayAABBIntersection(
                                ray_origin, ray_direction, 
                                bounding_min, bounding_max
                            );

                            if (box_intersection.hit)
                            {
                                {
                                    found_entity = block.entities[i];
                                }

                                closest_t_max = @min(closest_t_max, box_intersection.t_max - box_intersection.t_min);
                            }
                        }
                    }

                    if (found_entity != null)
                    {
                        selected_entity = found_entity;
                    }

                    mouse_pressed_last_Frame = true;
                }

                if (!window.getMouseDown(.left))
                {
                    mouse_pressed_last_Frame = false;
                }

                entity_editor.entityViewer(&ecs_scene, &entity_debugger_commands);
                entity_editor.chunkViewer(&ecs_scene);
                quanta.imgui.log.viewer("Log");

                if (selected_entity != null and !ecs_scene.entityExists(selected_entity.?))
                {
                    selected_entity = null;
                }

                if (
                    selected_entity != null and
                    ecs_scene.entityHasComponent(selected_entity.?, quanta.ecs.components.Position)
                )
                {
                    const entity_position = ecs_scene.entityGetComponent(selected_entity.?, quanta.ecs.components.Position) orelse unreachable;  
                    const entity_rotation = ecs_scene.entityGetComponent(selected_entity.?, quanta.ecs.components.Rotation);  
                    // const entity_scale = ecs_scene.entityGetComponent(selected_entity.?, quanta.ecs.components.NonUniformScale);  

                    imguizmo.ImGuizmo_SetImGuiContext(imgui.igGetCurrentContext());
                    imguizmo.ImGuizmo_Enable(true);
                    imguizmo.ImGuizmo_SetDrawlist(imgui.igGetBackgroundDrawList_Nil());
                    imguizmo.ImGuizmo_AllowAxisFlip(false);
                    imguizmo.ImGuizmo_SetID(0);
                    imguizmo.ImGuizmo_SetRect(0, 0, @intToFloat(f32, window.getWidth()), @intToFloat(f32, window.getHeight()));

                    const camera_view = camera.getView();
                    const camera_projection = camera.getProjectionNonInverse();

                    var operation = imguizmo.Operation.translate;

                    var manip_matrix = zalgebra.Mat4.identity();

                    if (entity_rotation != null)
                    {
                        manip_matrix = manip_matrix.mul(zalgebra.Mat4.fromEulerAngles(.{ .data = .{ entity_rotation.?.x, entity_rotation.?.y, entity_rotation.?.z } }));

                        operation.rotate_x = true;
                        operation.rotate_y = true;
                        operation.rotate_z = true;
                        operation.rotate_screen = true;
                    }

                    manip_matrix = zalgebra.Mat4.fromTranslate(.{ .data = .{ entity_position.x, entity_position.y, entity_position.z } }).mul(manip_matrix);

                    _ = imguizmo.ImGuizmo_Manipulate(
                        @ptrCast([*]const f32, &camera_view),
                        @ptrCast([*]const f32, &camera_projection),
                        operation,
                        .world,
                        @ptrCast([*]f32, &manip_matrix),
                        null,
                        null,
                        null,
                        null,
                    );

                    var position: [3]f32 = undefined;
                    var rotation: [3]f32 = undefined;
                    var scale: [3]f32 = undefined;

                    imguizmo.ImGuizmo_DecomposeMatrixToComponents(
                        @ptrCast([*]f32, &manip_matrix),
                        &position,
                        &rotation,
                        &scale
                    );

                    entity_position.x = position[0];
                    entity_position.y = position[1];
                    entity_position.z = position[2];

                    if (entity_rotation != null)
                    {
                        entity_rotation.?.* = .{ .x = rotation[0], .y = rotation[1], .z = rotation[2] };
                    }
                }

                try entity_debugger_commands.execute(&ecs_scene);
            }
            
            imgui.igRender();

            {
                RendererGui.begin(&color_image);
                RendererGui.renderImGuiDrawData(imgui.igGetDrawData()) catch unreachable;
            }
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

pub const std_options = struct 
{
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void 
    {
        const log_to_terminal = true;

        if (log_to_terminal)
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
            const prefix2 = if (scope == .default) ": " else "[" ++ @tagName(scope) ++ "]: ";
            const stderr = std.io.getStdErr().writer();
            std.debug.getStderrMutex().lock();
            defer std.debug.getStderrMutex().unlock();
            nosuspend stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
        }

        quanta.imgui.log.logMessage(message_level, scope, format, args) catch return;
    }
};

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