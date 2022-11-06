const Buffer = @This();

const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("Context.zig");
const CommandBuffer = @import("CommandBuffer.zig");

handle: vk.Buffer, 
memory: vk.DeviceMemory,
size: usize,
alignment: usize,
usage: Usage,

pub const Usage = enum 
{
    vertex,
    index,
    uniform,
    storage,
    indirect_draw,
    staging,
};

pub fn initData(comptime T: type, data: []const T, usage: Usage) !Buffer 
{
    var staging = try init(data.len * @sizeOf(T), .staging);
    defer staging.deinit();

    var buffer = try init(data.len * @sizeOf(T), usage);
    errdefer buffer.deinit();

    {
        const mapped_data = try staging.map(T);
        defer staging.unmap();

        std.mem.copy(T, mapped_data, data);
    }

    var command_buffer = try CommandBuffer.init(.graphics);
    defer command_buffer.deinit();

    {
        try command_buffer.begin();
        defer command_buffer.end();

        command_buffer.copyBuffer(staging, 0, buffer, 0);
    }

    try command_buffer.submitAndWait();

    return buffer;
}

pub fn init(size: usize, usage: Usage) !Buffer
{
    var self = Buffer 
    {
        .handle = .null_handle,
        .memory = .null_handle,
        .size = size,
        .alignment = 0,
        .usage = usage,
    };

    const create_info = vk.BufferCreateInfo 
    {
        .flags = .{},
        .size = size,
        .usage = switch (usage) 
        {
            .vertex => .{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
            .index => .{ .index_buffer_bit = true, .transfer_dst_bit = true },
            .uniform => .{ .uniform_buffer_bit = true, .transfer_dst_bit = true },
            .storage => .{ .storage_buffer_bit = true, .transfer_dst_bit = true },
            .indirect_draw => .{ .indirect_buffer_bit = true, .transfer_dst_bit = true, },
            .staging => .{ .transfer_src_bit = true },
        },
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
    };

    self.handle = try Context.self.vkd.createBuffer(Context.self.device, &create_info, &Context.self.allocation_callbacks);
    errdefer Context.self.vkd.destroyBuffer(Context.self.device, self.handle, &Context.self.allocation_callbacks);

    const memory_requirements = Context.self.vkd.getBufferMemoryRequirements(Context.self.device, self.handle);

    self.alignment = memory_requirements.alignment;

    self.memory = try Context.deviceAllocate(memory_requirements, switch (usage)
    {
        .staging => .{ .host_visible_bit = true, .host_coherent_bit = true },
        .vertex, .index, .uniform, .storage => .{ .device_local_bit = true },
        .indirect_draw => .{ .host_visible_bit = true, .host_coherent_bit = true },
    });
    errdefer Context.self.vkd.freeMemory(Context.self.device, self.memory, &Context.self.allocation_callbacks);

    try Context.self.vkd.bindBufferMemory(Context.self.device, self.handle, self.memory, 0);

    return self;
}

pub fn deinit(self: *Buffer) void 
{
    defer self.* = undefined;

    defer Context.self.vkd.destroyBuffer(Context.self.device, self.handle, &Context.self.allocation_callbacks);
    defer Context.self.vkd.freeMemory(Context.self.device, self.memory, &Context.self.allocation_callbacks);
}

pub fn map(self: Buffer, comptime T: type) ![]T
{
    const data = @ptrCast(?[*]T, @alignCast(@alignOf(T), try Context.self.vkd.mapMemory(Context.self.device, self.memory, 0, self.size, .{})));

    return data.?[0..self.size / @sizeOf(T)];
}

pub fn unmap(self: Buffer) void
{
    Context.self.vkd.unmapMemory(Context.self.device, self.memory);
}

pub fn update(self: Buffer, comptime T: type, offset: usize, data: []const T) !void 
{
    var staging = try init(data.len * @sizeOf(T), .staging);
    defer staging.deinit();

    {
        const mapped_data = try staging.map(T);
        defer staging.unmap();

        std.mem.copy(T, mapped_data, data);
    }

    var command_buffer = try CommandBuffer.init(.graphics);
    defer command_buffer.deinit();

    {
        try command_buffer.begin();
        defer command_buffer.end();

        command_buffer.copyBuffer(staging, 0, self, offset);
    }

    try command_buffer.submitAndWait();
}