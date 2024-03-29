const std = @import("std");
const components = @import("../components.zig");
const ComponentStore = @import("../ecs/ComponentStore.zig");
const Renderer3D = @import("../renderer_3d.zig").Renderer3D;
const zalgebra = @import("zalgebra");

const Position = components.Position;
const PointLight = components.PointLight;
const Visibility = components.Visibility;

const system = struct {
    pub fn run() void {}
};

pub fn run(
    component_store: *ComponentStore,
    scene: Renderer3D.SceneHandle,
) void {
    const without = ComponentStore.filterWithout;
    const filterOr = ComponentStore.filterOr;
    _ = filterOr;

    var query = component_store.query(.{
        Position,
        PointLight,
    }, .{
        without(Visibility), // !Visibility
    });

    while (query.nextBlock()) |block| {
        for (block.Position, block.PointLight) |position, point_light| {
            Renderer3D.scenePushPointLight(scene, .{
                .position = .{ position.x, position.y, position.z },
                .intensity = point_light.intensity,
                .diffuse = packUnorm4x8(.{ point_light.diffuse[0], point_light.diffuse[1], point_light.diffuse[2], 1 }),
            });
        }
    }

    var visibility_query = component_store.query(.{ Position, PointLight, Visibility }, .{});

    while (visibility_query.nextBlock()) |block| {
        for (
            block.Position,
            block.PointLight,
            block.Visibility,
        ) |position, point_light, visibility| {
            if (!visibility.is_visible) continue;

            Renderer3D.scenePushPointLight(scene, .{
                .position = .{ position.x, position.y, position.z },
                .intensity = point_light.intensity,
                .diffuse = packUnorm4x8(.{ point_light.diffuse[0], point_light.diffuse[1], point_light.diffuse[2], 1 }),
            });
        }
    }
}

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
