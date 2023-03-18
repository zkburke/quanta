const std = @import("std");
const components = @import("../components.zig");
const ComponentStore = @import("../ecs/ComponentStore.zig");
const Renderer3D = @import("../renderer.zig").Renderer3D;
const zalgebra = @import("zalgebra");

const Rotation = components.Rotation;
const DirectionalLight = components.DirectionalLight;
const Visibility = components.Visibility;

pub fn run(
    component_store: *ComponentStore,
    scene: Renderer3D.SceneHandle,
) void 
{
    const without = ComponentStore.filterWithout;
    
    var query = component_store.query(
        .{ Rotation, DirectionalLight, }, 
        .{ without(Visibility), }
    );

    while (query.nextBlock()) |block|
    {
        for (
            block.Rotation, 
            block.DirectionalLight
        ) |rotation, light|
        {
            Renderer3D.scenePushDirectionalLight(scene, .{
                .direction = zalgebra.Vec3.norm(.{ .data = .{ rotation.x, rotation.y, rotation.z } }).data,
                .intensity = light.intensity,
                .diffuse = packUnorm4x8(.{ light.diffuse[0], light.diffuse[1], light.diffuse[2], 1 }),
                .view_projection = zalgebra.Mat4.identity().data,
            });
        }
    }
}

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