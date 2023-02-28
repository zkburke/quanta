const std = @import("std");
const log = std.log.scoped(.velocity_system);
const components = @import("components.zig");
const ComponentStore = @import("ComponentStore.zig");
const CommandBuffer = @import("CommandBuffer.zig");

const Position = components.Position;
const Velocity = components.Velocity;

pub fn run(
    _: *CommandBuffer,
    query: *ComponentStore.QueryIterator(.{ Position, Velocity }, .{})
) void 
{
    const delta_time = 1.0 / 1000.0;

    while (query.nextBlock()) |block|
    {
        for (
            block.Position, 
            block.Velocity
        ) |*position, velocity|
        {
            position.*.x += velocity.x * delta_time;
            position.*.y += velocity.y * delta_time;
            position.*.z += velocity.z * delta_time;            
        }
    }
}