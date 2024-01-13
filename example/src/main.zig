const std = @import("std");
const builtin = @import("builtin");
const quanta = @import("quanta");
const windowing = quanta.windowing;
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
const imgui = quanta.imgui.cimgui;
const imguizmo = quanta.imgui.guizmo;
const entity_editor = quanta.imgui.entity_editor;
const asset = quanta.asset;

const quanta_components = quanta.components;
const velocity_system = quanta.systems.velocity_system;
const acceleration_system = quanta.systems.acceleration_system;

const vk = quanta.graphics.vulkan;
const graphics = quanta.graphics;
const Renderer3D = quanta.renderer.Renderer3D;
const RendererGui = quanta.renderer_gui.RendererGui;

//should be generated by the assets build step
const example_assets = struct {
    const sponza = @as(asset.Archive.AssetDescriptor, @enumFromInt(0));
    const gm_construct = @as(asset.Archive.AssetDescriptor, @enumFromInt(1));
    const gm_castle_island = @as(asset.Archive.AssetDescriptor, @enumFromInt(2));
    const environment_map = @as(asset.Archive.AssetDescriptor, @enumFromInt(3));
    const test_scene = @as(asset.Archive.AssetDescriptor, @enumFromInt(4));
    const lights_test = @as(asset.Archive.AssetDescriptor, @enumFromInt(5));
};

const log = std.log.scoped(.example);

var state: struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},
    allocator: std.mem.Allocator = undefined,
    window: windowing.Window = undefined,
    swapchain: graphics.Swapchain = undefined,
    asset_archive_blob: []align(std.mem.page_size) u8 = undefined,
    asset_archive: asset.Archive = undefined,

    test_scene_meshes: []Renderer3D.MeshHandle = &.{},
    test_scene_textures: []Renderer3D.TextureHandle = &.{},
    test_scene_materials: []Renderer3D.MaterialHandle = &.{},

    renderer_scene: Renderer3D.SceneHandle = undefined,
    ecs_scene: quanta.ecs.ComponentStore = undefined,
    asset_storage: asset.AssetStorage = undefined,

    entity_debugger_commands: quanta.ecs.CommandBuffer = undefined,

    camera: Renderer3D.Camera = .{
        .translation = .{ 0, 3, 12.5 },
        .target = .{ 0, 0, 0 },
        .fov = 60,
        .exposure = 1,
    },

    camera_position: @Vector(3, f32) = .{ 8.7, 5.7, 0.9 },
    camera_front: @Vector(3, f32) = .{ -0.9, -0.1, -0.2 },
    camera_up: @Vector(3, f32) = .{ 0, 1, 0 },
    yaw: f32 = 168.1,
    pitch: f32 = -9.1,

    last_mouse_x: f32 = 0,
    last_mouse_y: f32 = 0,
    camera_enable: bool = false,
    camera_enable_changed: bool = false,

    selected_entity: ?quanta.ecs.ComponentStore.Entity = null,
    selected_entities: std.ArrayList(quanta.ecs.ComponentStore.Entity) = undefined,
    cloned_entity_last_frame: bool = false,
    mouse_pressed_last_Frame: bool = false,

    delta_time: f32 = 0.016,
} = .{};

const enable_pipeline_cache = true;
const pipeline_cache_file_path = "pipeline_cache";

pub fn init() !void {
    log.debug("All your {s} are belong to us.", .{"codebase"});
    log.debug("{s}", .{"debug"});
    log.warn("{s}", .{"warn"});
    log.err("{s}", .{"err"});

    state.gpa = std.heap.GeneralPurposeAllocator(.{}){};
    state.allocator = if (builtin.mode == .Debug) state.gpa.allocator() else std.heap.c_allocator;

    state.window = try windowing.Window.init(state.allocator, 1600, 900, "Quanta Example");
    errdefer state.window.deinit(state.allocator);

    {
        var pipeline_cache_data: []u8 = &[_]u8{};

        if (enable_pipeline_cache) {
            const file = std.fs.cwd().openFile(pipeline_cache_file_path, .{ .mode = .read_only }) catch try std.fs.cwd().createFile(pipeline_cache_file_path, .{ .read = true });
            defer file.close();

            pipeline_cache_data = try file.readToEndAlloc(state.allocator, std.math.maxInt(usize));

            log.debug("pipeline_cache_data.len = {}", .{pipeline_cache_data.len});
        }

        try GraphicsContext.init(state.allocator, &state.window, pipeline_cache_data);

        state.allocator.free(pipeline_cache_data);
    }

    state.swapchain = try Swapchain.init(
        state.allocator,
        GraphicsContext.self.surface,
    );

    try Renderer3D.init(state.allocator);

    const imgui_context = imgui.igCreateContext(null);

    std.debug.assert(imgui_context != null);
    imgui.igSetCurrentContext(imgui_context);

    try quanta.imgui.driver.init();
    try RendererGui.init(state.allocator, state.swapchain);

    const asset_archive_file_path = "assets/example_assets_archive";

    const asset_archive_fd = try std.os.open(asset_archive_file_path, std.os.O.RDONLY, std.os.S.IRUSR | std.os.S.IWUSR);
    defer std.os.close(asset_archive_fd);

    const asset_archive_fd_stat = try std.os.fstat(asset_archive_fd);

    log.info("assets_archive size = {}", .{asset_archive_fd_stat.size});

    state.asset_archive_blob = try std.os.mmap(null, @as(usize, @intCast(asset_archive_fd_stat.size)), std.os.PROT.READ, std.os.MAP.PRIVATE, asset_archive_fd, 0);

    state.asset_archive = try asset.Archive.decode(state.allocator, state.asset_archive_blob);

    log.info("asset_archive.assets.len = {any}", .{state.asset_archive.assets.len});

    state.asset_storage = asset.AssetStorage.init(state.allocator, state.asset_archive);
    errdefer state.asset_storage.deinit();

    const test_scene_handle = state.asset_storage.load(gltf.Import, "example/src/assets/test_scene/test_scene.gltf");

    const test_scene_import = state.asset_storage.get(gltf.Import, test_scene_handle).?;

    state.test_scene_meshes = try state.allocator.alloc(Renderer3D.MeshHandle, test_scene_import.sub_meshes.len);
    state.test_scene_textures = try state.allocator.alloc(Renderer3D.TextureHandle, test_scene_import.textures.len);
    state.test_scene_materials = try state.allocator.alloc(Renderer3D.MaterialHandle, test_scene_import.materials.len);

    for (test_scene_import.sub_meshes, 0..) |sub_mesh, i| {
        state.test_scene_meshes[i] = try Renderer3D.createMesh(
            test_scene_import.vertex_positions[sub_mesh.vertex_offset .. sub_mesh.vertex_offset + sub_mesh.vertex_count],
            test_scene_import.vertices[sub_mesh.vertex_offset .. sub_mesh.vertex_offset + sub_mesh.vertex_count],
            test_scene_import.indices[sub_mesh.index_offset .. sub_mesh.index_offset + sub_mesh.index_count],
            sub_mesh.bounding_min,
            sub_mesh.bounding_max,
        );
    }

    for (test_scene_import.textures, 0..) |texture, i| {
        state.test_scene_textures[i] = try Renderer3D.createTexture(
            texture.data,
            texture.width,
            texture.height,
        );
    }

    if (test_scene_import.materials.len != 0) {
        for (test_scene_import.materials, 0..) |material, i| {
            log.info("material albedo index {}", .{material.albedo_texture_index});
            log.info("material albedo {any}", .{material.albedo});

            state.test_scene_materials[i] = try Renderer3D.createMaterial(
                if (material.albedo_texture_index != 0) state.test_scene_textures[material.albedo_texture_index - 1] else null,
                material.albedo,
                null,
                material.metalness,
                if (material.roughness_texture_index != 0) state.test_scene_textures[material.roughness_texture_index - 1] else null,
                material.roughness,
            );
        }
    }

    const environment_map = state.asset_storage.load(asset.CubeMap, "example/src/assets/skybox/right.png");
    const environment_map_data = state.asset_storage.get(asset.CubeMap, environment_map).?;

    state.ecs_scene = try quanta.ecs.ComponentStore.init(state.allocator);

    state.renderer_scene = try Renderer3D.createScene(
        1,
        50_000,
        4,
        4096,
        environment_map_data.data,
        environment_map_data.width,
        environment_map_data.height,
    );

    for (test_scene_import.sub_meshes, 0..) |sub_mesh, i| {
        const decomposed = zalgebra.Mat4.decompose(.{ .data = sub_mesh.transform });
        const translation = decomposed.t;
        const rotation = decomposed.r.extractEulerAngles();
        const scale = decomposed.s;

        _ = try state.ecs_scene.entityCreate(.{
            quanta.components.Position{ .x = translation.x(), .y = translation.y(), .z = translation.z() },
            quanta.components.Rotation{ .x = rotation.x(), .y = rotation.y(), .z = rotation.z() },
            quanta.components.NonUniformScale{ .x = scale.x(), .y = scale.y(), .z = scale.z() },
            quanta.components.RendererMesh{ .mesh = state.test_scene_meshes[i], .material = state.test_scene_materials[sub_mesh.material_index] },
        });
    }

    const target_frame_time: f32 = 16;

    state.delta_time = target_frame_time;

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Rotation{ .x = -0.5, .y = -1, .z = -0.3 },
        quanta_components.DirectionalLight{
            .intensity = 1,
            .diffuse = .{
                0.45,
                0.45,
                0.45,
            },
        },
    });

    const TestEnumComponent = enum {
        no_state,
        state_0,
        state_1,
        ect_state,
    };

    const TestUnionComponent = union(enum) {
        no_state: void,
        state_0: u32,
        state_1: void,
        ect_state: void,
    };

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 0, .y = 2, .z = 0 },
        quanta_components.Velocity{ .x = 0, .y = 1, .z = 0 },
        TestEnumComponent.state_1,
        TestUnionComponent{ .state_1 = {} },
    });

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 0, .y = 2, .z = 0 },
        quanta_components.Velocity{ .x = 0, .y = 1, .z = 0 },
        TestEnumComponent.state_1,
        TestUnionComponent{ .state_1 = {} },
    });

    const test_entity = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 0, .y = 50, .z = 0 },
        quanta_components.PointLight{
            .intensity = 1000,
            .diffuse = .{ 1, 1, 1 },
        },
        quanta_components.Visibility{ .is_visible = true },
    });

    state.selected_entity = test_entity;

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 0, .y = 4, .z = 0 },
        quanta_components.Velocity{ .x = 0, .y = 0.5, .z = 0 },
        quanta.ecs.ComponentStore.Entity.nil,
    });

    const entity_b = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 0, .y = -2, .z = 0 },
        quanta_components.Velocity{ .x = 0, .y = 1, .z = 0 },
        quanta_components.Force{ .x = 2, .y = 9.81, .z = 0 },
        quanta_components.Mass{ .value = 10 },
        quanta_components.TerminalVelocity{ .x = 0, .y = 0.01, .z = 0 },
        quanta_components.RendererMesh{ .mesh = state.test_scene_meshes[0], .material = state.test_scene_materials[0] },
    });

    const entity_a = try state.ecs_scene.entityCreate(.{
        quanta_components.Mass{ .value = 10 },
        quanta_components.Force{ .x = 2, .y = 9.81, .z = 0 },
        quanta_components.Position{ .x = 0, .y = -2, .z = 0 },
        quanta_components.RendererMesh{ .mesh = state.test_scene_meshes[0], .material = state.test_scene_materials[0] },
        quanta_components.Velocity{ .x = 0, .y = 1, .z = 0 },
        quanta_components.TerminalVelocity{ .x = 0, .y = 0.01, .z = 0 },
    });

    std.debug.assert(state.ecs_scene.entitiesAreIsomers(entity_a, entity_b));

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 0, .y = 1, .z = -4 },
        quanta_components.PointLight{
            .intensity = 10 + 40,
            .diffuse = .{ 0.8, 0.4, 0.1 },
        },
    });

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 4, .y = 4, .z = 4 },
        quanta_components.PointLight{
            .intensity = 10 + 40,
            .diffuse = .{ 0.4, 0.8, 0.1 },
        },
    });

    _ = try state.ecs_scene.entityCreate(.{
        quanta_components.Position{ .x = 80, .y = 4, .z = 4 },
        quanta_components.PointLight{
            .intensity = 1000,
            .diffuse = .{ 0.6, 0.6, 0.8 },
        },
    });

    state.entity_debugger_commands = quanta.ecs.CommandBuffer.init(state.allocator);
    state.selected_entities = std.ArrayList(quanta.ecs.ComponentStore.Entity).init(state.allocator);
}

pub fn deinit() void {
    GraphicsContext.self.vkd.deviceWaitIdle(GraphicsContext.self.device) catch unreachable;

    defer log.info("Exiting gracefully", .{});
    defer if (builtin.mode == .Debug) std.debug.assert(state.gpa.deinit() != .leak);

    defer state.window.deinit(state.allocator);
    defer GraphicsContext.deinit();

    defer if (enable_pipeline_cache) {
        const pipeline_cache_data = GraphicsContext.getPipelineCacheData() catch unreachable;
        defer state.allocator.free(pipeline_cache_data);

        const file = std.fs.cwd().openFile(pipeline_cache_file_path, .{ .mode = .write_only }) catch unreachable;
        defer file.close();

        file.setEndPos(0) catch unreachable;
        file.seekTo(0) catch unreachable;

        file.writeAll(pipeline_cache_data) catch unreachable;
    };

    defer state.swapchain.deinit();
    defer Renderer3D.deinit();
    defer imgui.igDestroyContext(imgui.igGetCurrentContext());
    defer quanta.imgui.driver.deinit();
    defer RendererGui.deinit();
    defer std.os.munmap(state.asset_archive_blob);
    defer state.allocator.free(state.test_scene_meshes);
    defer state.allocator.free(state.test_scene_textures);
    defer state.allocator.free(state.test_scene_materials);
    defer state.ecs_scene.deinit();
    defer Renderer3D.destroyScene(state.renderer_scene);
    defer state.entity_debugger_commands.deinit();
    defer state.selected_entities.deinit();
    defer state.asset_storage.deinit();
}

pub fn update() !quanta.app.UpdateResult {
    if (state.window.shouldClose()) return .exit;

    const time_begin = std.time.nanoTimestamp();

    if (!state.camera_enable_changed and state.window.getKey(.tab) == .press) {
        state.camera_enable = !state.camera_enable;

        if (state.camera_enable) {
            // state.window.setInputMode(.cursor, .disabled);
            state.window.grabMouse();
        } else {
            // state.window.setInputMode(.cursor, .normal);
            state.window.ungrabMouse();
        }

        state.camera_enable_changed = true;

        std.log.info("tab pressedeeeeed", .{});
    }

    if (state.window.getKey(.tab) == .release) {
        state.camera_enable_changed = false;
    }

    //update
    {
        const x_position: f32 = @floatFromInt(state.window.getCursorPosition()[0]);
        const y_position: f32 = @floatFromInt(state.window.getCursorPosition()[1]);

        const x_offset = x_position - state.last_mouse_x;
        const y_offset = state.last_mouse_y - y_position;

        state.last_mouse_x = x_position;
        state.last_mouse_y = y_position;

        if (state.camera_enable) {
            const sensitivity = 0.1;
            var camera_speed: @Vector(3, f32) = @splat(30 * state.delta_time / 1000);

            if (state.window.getKey(.left_control) == .down) {
                camera_speed *= @splat(2);
            }

            state.yaw += x_offset * sensitivity;
            state.pitch += y_offset * sensitivity;

            state.pitch = std.math.clamp(state.pitch, -89, 89);

            state.camera_front = zalgebra.Vec3.norm(.{ .data = .{
                @cos(zalgebra.toRadians(state.yaw)) * @cos(zalgebra.toRadians(-state.pitch)),
                @sin(zalgebra.toRadians(state.pitch)),
                @sin(zalgebra.toRadians(state.yaw)) * @cos(zalgebra.toRadians(-state.pitch)),
            } }).data;

            if (state.window.getKey(.w) == .down) {
                state.camera_position += camera_speed * state.camera_front;
            } else if (state.window.getKey(.s) == .down) {
                state.camera_position -= camera_speed * state.camera_front;
            }

            if (state.window.getKey(.a) == .down) {
                state.camera_position -= zalgebra.Vec3.norm(zalgebra.Vec3.cross(.{ .data = state.camera_front }, .{ .data = state.camera_up })).mul(.{ .data = camera_speed }).data;
            } else if (state.window.getKey(.d) == .down) {
                state.camera_position += zalgebra.Vec3.norm(zalgebra.Vec3.cross(.{ .data = state.camera_front }, .{ .data = state.camera_up })).mul(.{ .data = camera_speed }).data;
            }

            if (state.window.getKey(.space) == .down) {
                state.camera_position[1] += camera_speed[1];
            } else if (state.window.getKey(.left_shift) == .down) {
                state.camera_position[1] -= camera_speed[1];
            }
        }

        state.camera.target = state.camera_position + state.camera_front;
        state.camera.translation = state.camera_position;
    }

    state.ecs_scene.beginQueryWindow();

    acceleration_system.run(&state.ecs_scene, state.delta_time);
    quanta.systems.force_system.run(&state.ecs_scene, state.delta_time);

    try quanta.ecs.system_scheduler.run(&state.ecs_scene, &state.entity_debugger_commands, .{velocity_system});

    quanta.systems.terminal_velocity_system.run(&state.ecs_scene);

    const image_index = state.swapchain.image_index;
    const image = state.swapchain.swap_images[image_index];

    //sneaky hack due to our incomplete swapchain abstraction
    var color_image: Image = undefined;

    color_image.view = image.view;
    color_image.handle = image.image;
    color_image.aspect_mask = .{ .color_bit = true };
    color_image.width = state.swapchain.extent.width;
    color_image.height = state.swapchain.extent.height;

    {
        try Renderer3D.beginSceneRender(
            state.renderer_scene,
            &.{Renderer3D.View{ .camera = state.camera }},
            .{ .diffuse = packUnorm4x8(.{ 0.005, 0.005, 0.005, 1 }) },
            0,
        );
        defer Renderer3D.endSceneRender(state.renderer_scene, state.swapchain, &state.window);

        quanta.systems.mesh_instance_system.run(&state.ecs_scene, state.renderer_scene);
        quanta.systems.point_light_system.run(&state.ecs_scene, state.renderer_scene);
        quanta.systems.directional_light_system.run(&state.ecs_scene, state.renderer_scene);
    }

    //imgui gui
    if (true) {
        {
            try quanta.imgui.driver.begin(&state.window);
            defer quanta.imgui.driver.end();

            const widgets = quanta.imgui.widgets;

            imgui.igNewFrame();
            imguizmo.ImGuizmo_SetOrthographic(false);
            imguizmo.ImGuizmo_BeginFrame();

            imgui.igShowDemoWindow(null);

            if (widgets.begin("Basic properties")) {
                widgets.textFormat("Frame time {d:.2}ms", .{state.delta_time});
                widgets.textFormat("Frame rate {d:.2}Hz", .{1 / (state.delta_time / 1000)});

                if (widgets.button("Button test")) {
                    log.info("Praise be the {s}", .{"BIG BUTTON"});
                }

                widgets.text("Renderer Statistics:");

                widgets.textFormat("depth_pre_pass_time = {d:.2}ms", .{@as(f64, @floatFromInt(Renderer3D.getStatistics().depth_prepass_time)) / @as(f64, @floatFromInt(std.time.ns_per_ms))});

                widgets.textFormat("geometry_pass_time = {d:.2}ms", .{@as(f64, @floatFromInt(Renderer3D.getStatistics().geometry_pass_time)) / @as(f64, @floatFromInt(std.time.ns_per_ms))});

                _ = imgui.igDragFloat("Camera Exposure: ", &state.camera.exposure, 0.1, 0.1, 15, null, 0);
            }
            widgets.end();

            try entity_editor.entitySelector(
                &state.ecs_scene,
                &state.entity_debugger_commands,
                state.camera,
                &state.selected_entities,
                &state.window,
            );

            // //Selection
            // if (window.getMouseDown(.left) and !state.mouse_pressed_last_Frame and !imguizmo.ImGuizmo_IsUsing() and !imguizmo.ImGuizmo_IsOver() and !imgui.igIsAnyItemFocused()) {
            //     const mouse_pos = window.getMousePos();

            //     log.info("mouse_pos = {d}, {d}", .{ mouse_pos[0], mouse_pos[1] });

            //     const view_projection = zalgebra.Mat4.mul(
            //         .{ .data = state.camera.getView() },
            //         .{ .data = state.camera.getProjectionNonInverse() },
            //     );

            //     const inverse_view_projection = view_projection.inv();

            //     const normalized_pos = [2]f32{
            //         ((mouse_pos[0] / @intToFloat(f32, window.getWidth())) * 2) - 1,
            //         (((mouse_pos[1] - @intToFloat(f32, window.getHeight())) / @intToFloat(f32, window.getHeight())) * 2) - 1,
            //     };

            //     const world_space_pos = inverse_view_projection.mulByVec4(.{ .data = .{ normalized_pos[0], normalized_pos[1], 0, 1 } });

            //     log.info("world_space_pos (ray_origin) = {d}, {d}, {d}", .{
            //         world_space_pos.data[0] / 1000.0,
            //         world_space_pos.data[1] / 1000.0,
            //         world_space_pos.data[2] / 1000.0,
            //     });

            //     log.info("world_space_pos (ray_dir) = {d}, {d}, {d}", .{
            //         state.camera_front[0],
            //         state.camera_front[1],
            //         state.camera_front[2],
            //     });

            //     const ray_origin = @Vector(3, f32){
            //         world_space_pos.data[0] / 1000.0,
            //         world_space_pos.data[1] / 1000.0,
            //         world_space_pos.data[2] / 1000.0,
            //     };

            //     const ray_length = 1000;

            //     const ray_direction = @Vector(3, f32){
            //         state.camera_front[0] * ray_length,
            //         state.camera_front[1] * ray_length,
            //         state.camera_front[2] * ray_length,
            //     };

            //     const intersection = quanta.physics.intersection;

            //     var query = state.ecs_scene.query(.{
            //         quanta.components.Position,
            //         quanta.components.NonUniformScale,
            //         quanta.components.RendererMesh,
            //     }, .{});

            //     var found_entity: ?quanta.ecs.ComponentStore.Entity = null;
            //     var closest_t_max: f32 = std.math.inf_f32;

            //     if (false) while (query.nextBlock()) |block| {
            //         for (block.Position, block.NonUniformScale, block.RendererMesh, 0..) |position, scale, mesh, i| {
            //             const mesh_box = Renderer3D.getMeshBox(mesh.mesh);

            //             const position_vector = @Vector(3, f32){ position.x, position.y, position.z };

            //             const bounding_min = position_vector + (mesh_box.min * @Vector(3, f32){ scale.x, scale.y, scale.z });
            //             const bounding_max = position_vector + (mesh_box.max * @Vector(3, f32){ scale.x, scale.y, scale.z });

            //             if (intersection.rayAABBIntersection(ray_origin, ray_direction, bounding_min, bounding_max)) |hit| {
            //                 {
            //                     found_entity = block.entities[i];
            //                 }

            //                 closest_t_max = @min(closest_t_max, hit.t_max - hit.t_min);
            //             }
            //         }
            //     };
            // }

            const primary_selected_entity = if (state.selected_entities.items.len != 0) state.selected_entities.items[0] else quanta.ecs.ComponentStore.Entity.nil;

            if (state.selected_entities.items.len != 0 and state.ecs_scene.entityHasComponent(primary_selected_entity, quanta.components.Position)) {
                const entity_position = state.ecs_scene.entityGetComponent(primary_selected_entity, quanta.components.Position) orelse unreachable;
                const entity_rotation = state.ecs_scene.entityGetComponent(primary_selected_entity, quanta.components.Rotation);
                const entity_scale = state.ecs_scene.entityGetComponent(primary_selected_entity, quanta.components.NonUniformScale);

                imguizmo.ImGuizmo_SetImGuiContext(imgui.igGetCurrentContext());
                imguizmo.ImGuizmo_Enable(true);
                imguizmo.ImGuizmo_SetDrawlist(imgui.igGetBackgroundDrawList_Nil());
                imguizmo.ImGuizmo_AllowAxisFlip(false);
                imguizmo.ImGuizmo_SetID(0);
                imguizmo.ImGuizmo_SetRect(0, 0, @as(f32, @floatFromInt(state.window.getWidth())), @as(f32, @floatFromInt(state.window.getHeight())));

                const camera_view = state.camera.getView();
                const camera_projection = state.camera.getProjectionNonInverse(&state.window);
                const camera_view_projection = zalgebra.Mat4.mul(.{ .data = camera_projection }, .{ .data = camera_view });

                var operation = imguizmo.Operation.translate;

                var manip_matrix = zalgebra.Mat4.identity();

                manip_matrix = manip_matrix.mul(zalgebra.Mat4.fromTranslate(.{ .data = .{ entity_position.x, entity_position.y, entity_position.z } }));

                if (entity_rotation != null) {
                    manip_matrix = manip_matrix.mul(zalgebra.Mat4.fromEulerAngles(.{ .data = .{ entity_rotation.?.x, entity_rotation.?.y, entity_rotation.?.z } }));

                    operation.rotate_x = true;
                    operation.rotate_y = true;
                    operation.rotate_z = true;
                    operation.rotate_screen = true;
                }

                if (entity_scale != null) {
                    manip_matrix = manip_matrix.mul(zalgebra.Mat4.fromScale(.{ .data = .{ entity_scale.?.x, entity_scale.?.y, entity_scale.?.z } }));

                    operation.scale_x = true;
                    operation.scale_y = true;
                    operation.scale_z = true;
                }

                _ = imguizmo.ImGuizmo_Manipulate(
                    @as([*]const f32, @ptrCast(&camera_view)),
                    @as([*]const f32, @ptrCast(&camera_projection)),
                    operation,
                    imguizmo.Mode.world,
                    @as([*]f32, @ptrCast(&manip_matrix.data)),
                    null,
                    null,
                    null,
                    null,
                );

                const decomposed = manip_matrix.decompose();

                const position = decomposed.t.data;
                const scale = decomposed.s.data;
                const rotation = decomposed.r.extractEulerAngles().data;

                const position_change = position - @Vector(3, f32){ entity_position.x, entity_position.y, entity_position.z };
                const scale_change = if (entity_scale != null) scale - @Vector(3, f32){ entity_scale.?.x, entity_scale.?.y, entity_scale.?.z } else @Vector(3, f32){ 0, 0, 0 };
                const rotation_change = if (entity_rotation != null) rotation - @Vector(3, f32){ entity_rotation.?.x, entity_rotation.?.y, entity_rotation.?.z } else @Vector(3, f32){ 0, 0, 0 };

                for (state.selected_entities.items) |selected_entity| {
                    const selected_position = state.ecs_scene.entityGetComponent(selected_entity, quanta_components.Position);
                    const selected_rotation = state.ecs_scene.entityGetComponent(selected_entity, quanta_components.Rotation);
                    const selected_scale = state.ecs_scene.entityGetComponent(selected_entity, quanta_components.NonUniformScale);

                    if (selected_position != null) {
                        selected_position.?.* = .{
                            .x = selected_position.?.x + position_change[0],
                            .y = selected_position.?.y + position_change[1],
                            .z = selected_position.?.z + position_change[2],
                        };
                    }

                    if (selected_rotation != null) {
                        selected_rotation.?.* = .{
                            .x = selected_rotation.?.x + rotation_change[0],
                            .y = selected_rotation.?.y + rotation_change[1],
                            .z = selected_rotation.?.z + rotation_change[2],
                        };
                    }

                    if (selected_scale != null) {
                        selected_scale.?.* = .{
                            .x = selected_scale.?.x + scale_change[0],
                            .y = selected_scale.?.y + scale_change[1],
                            .z = selected_scale.?.z + scale_change[2],
                        };
                    }

                    if (state.ecs_scene.entityGetComponent(selected_entity, quanta_components.RendererMesh)) |mesh| {
                        const mesh_box = Renderer3D.getMeshBox(mesh.mesh);

                        const bounding_min = mesh_box.min;
                        const bounding_max = mesh_box.max;

                        var matrix = zalgebra.Mat4.identity();

                        matrix = matrix.mul(zalgebra.Mat4.fromTranslate(.{ .data = .{ selected_position.?.x, selected_position.?.y, selected_position.?.z } }));

                        if (selected_rotation != null) {
                            matrix = matrix.mul(zalgebra.Mat4.fromEulerAngles(.{ .data = .{ selected_rotation.?.x, selected_rotation.?.y, selected_rotation.?.z } }));

                            operation.rotate_x = true;
                            operation.rotate_y = true;
                            operation.rotate_z = true;
                            operation.rotate_screen = true;
                        }

                        if (selected_scale != null) {
                            matrix = matrix.mul(zalgebra.Mat4.fromScale(.{ .data = .{ selected_scale.?.x, selected_scale.?.y, selected_scale.?.z } }));

                            operation.scale_x = true;
                            operation.scale_y = true;
                            operation.scale_z = true;
                        }

                        widgets.drawBoundingBox(camera_view_projection, matrix, bounding_min, bounding_max);
                    }
                }
            }

            entity_editor.entityViewer(&state.ecs_scene, &state.entity_debugger_commands, &state.selected_entities);
            entity_editor.chunkViewer(&state.ecs_scene);
            quanta.imgui.log.viewer("Log");

            try state.entity_debugger_commands.execute(&state.ecs_scene);
        }

        //Draw point light gizmos
        {
            const camera_view = state.camera.getView();
            const camera_projection = state.camera.getProjectionNonInverse(&state.window);
            const camera_view_projection = zalgebra.Mat4.mul(.{ .data = camera_projection }, .{ .data = camera_view });

            var query = state.ecs_scene.query(.{quanta_components.Position}, .{});

            while (query.nextBlock()) |block| {
                for (block.Position) |position| {
                    quanta.imgui.widgets.drawBillboard(camera_view_projection, .{ position.x, position.y, position.z }, 10);
                }
            }
        }

        imgui.igRender();

        {
            RendererGui.begin(&color_image);
            RendererGui.renderImGuiDrawData(imgui.igGetDrawData(), &state.window) catch unreachable;
        }
    }

    for (state.ecs_scene.changes.added_chunks.items) |added_chunk| {
        std.log.info("added chunk to scene: {any}", .{added_chunk});
    }

    state.ecs_scene.endQueryWindow();

    try state.swapchain.present();
    try state.swapchain.swap();

    {
        state.delta_time = @as(f32, @floatFromInt(std.time.nanoTimestamp() - time_begin)) / @as(f32, @floatFromInt(std.time.ns_per_ms));
    }

    return .pass;
}

pub fn main() !void {
    try init();
    defer deinit();

    while (true) {
        switch (try update()) {
            .pass => continue,
            .exit => break,
        }
    }
}

pub const std_options = struct {
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const log_to_terminal = true;

        if (log_to_terminal) {
            const terminal_red = "\x1B[31m";
            const terminal_yellow = "\x1B[33m";
            const terminal_blue = "\x1B[34m";
            const terminal_green = "\x1B[32m";

            const color_begin = switch (message_level) {
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

fn packUnorm4x8(v: [4]f32) u32 {
    const Unorm4x8 = packed struct(u32) {
        x: u8,
        y: u8,
        z: u8,
        w: u8,
    };

    const x = @as(u8, @intFromFloat(v[0] * @as(f32, @floatFromInt(std.math.maxInt(u8)))));
    const y = @as(u8, @intFromFloat(v[1] * @as(f32, @floatFromInt(std.math.maxInt(u8)))));
    const z = @as(u8, @intFromFloat(v[2] * @as(f32, @floatFromInt(std.math.maxInt(u8)))));
    const w = @as(u8, @intFromFloat(v[3] * @as(f32, @floatFromInt(std.math.maxInt(u8)))));

    return @as(u32, @bitCast(Unorm4x8{
        .x = x,
        .y = y,
        .z = z,
        .w = w,
    }));
}
