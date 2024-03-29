const std = @import("std");
const ComponentStore = @import("ComponentStore.zig");
const CommandBuffer = @import("CommandBuffer.zig");

pub const QueryIterator = ComponentStore.QueryIterator;

pub const SystemInfo = struct {
    system_dependencies: []const type = .{},
    component_depencencies: []const type = .{},
};

///Indicates that a system is required to run in a loop
pub const UpdateInfo = struct {
    target_frequency: u32, //target updates per second
    delta_time: f32, //change in time in seconds
};

pub const example_system = struct {
    comptime {}

    pub const sys: SystemInfo = .{
        .system_dependencies = &.{u32},
        .component_depencencies = &.{u32},
    };

    ///Each system has a run function
    pub fn update(
        command_buffer: *CommandBuffer,
        query: *QueryIterator(.{}, .{}),
    ) void {
        _ = command_buffer;
        _ = query;
    }
};

///Register, schedule and run systems
pub fn run(component_store: *ComponentStore, command_buffer: *CommandBuffer, comptime systems: anytype) !void {
    _ = example_system;

    inline for (systems) |system| {
        const run_type_info = @typeInfo(@TypeOf(system.run)).Fn;

        const QueryIteratorType = run_type_info.params[1].type.?;

        var iter = std.meta.Child(QueryIteratorType).init(component_store);

        @call(.always_inline, system.run, .{
            command_buffer,
            &iter,
        });
    }

    try command_buffer.execute(component_store);
}
