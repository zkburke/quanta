handle: vk.Image,
type: Type,
view: vk.ImageView,
memory_page: Context.DevicePageHandle,
alignment: usize,
size: usize,
format: vk.Format,
layout: vk.ImageLayout,
aspect_mask: vk.ImageAspectFlags,
width: u32,
height: u32,
depth: u32,
levels: u32,

pub fn initData(
    @"type": Type,
    data: []const u8,
    width: u32,
    height: u32,
    depth: u32,
    levels: u32,
    format: vk.Format,
    layout: vk.ImageLayout,
    usage: vk.ImageUsageFlags,
) !Image {
    var image = try init(@"type", width, height, depth, levels, format, layout, usage);
    errdefer image.deinit();

    var source_buffer = try Buffer.init(image.size, .staging);
    defer source_buffer.deinit();

    {
        const mapped = try source_buffer.map(u8);
        defer source_buffer.unmap();

        @memcpy(mapped[0..data.len], data);
    }

    var command_buffer = try CommandBuffer.init(.graphics);
    defer command_buffer.deinit();

    {
        try command_buffer.begin();

        command_buffer.copyBufferToImage(source_buffer, image);

        command_buffer.end();

        try command_buffer.submitAndWait();
    }

    return image;
}

pub const Type = enum {
    @"1d",
    @"2d",
    @"3d",
    cube,
    @"1d_array",
    @"2d_array",
    cube_array,
};

pub fn init(
    @"type": Type,
    width: u32,
    height: u32,
    depth: u32,
    levels: u32,
    format: vk.Format,
    layout: vk.ImageLayout,
    usage: vk.ImageUsageFlags,
) !Image {
    var self = Image{
        .handle = .null_handle,
        .type = @"type",
        .view = .null_handle,
        .memory_page = undefined,
        .format = format,
        .layout = layout,
        .width = width,
        .height = height,
        .depth = depth,
        .levels = levels,
        .aspect_mask = .{
            .color_bit = format != vk.Format.d32_sfloat,
            .depth_bit = format == vk.Format.d32_sfloat,
        },
        .size = undefined,
        .alignment = undefined,
    };

    self.handle = try Context.self.vkd.createImage(Context.self.device, &.{
        .flags = vk.ImageCreateFlags{
            .alias_bit = true,
            .cube_compatible_bit = @"type" == .cube,
        },
        .image_type = @as(vk.ImageType, switch (@"type") {
            .@"1d" => .@"1d",
            .@"2d" => .@"2d",
            .@"3d" => .@"3d",
            .cube => .@"2d",
            .@"1d_array" => .@"2d",
            .@"2d_array" => .@"3d",
            .cube_array => .@"3d",
        }),
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = if (@"type" == .cube) 1 else depth },
        .mip_levels = levels,
        .array_layers = if (@"type" == .cube) depth else 1,
        .samples = .{
            .@"1_bit" = true,
        },
        .tiling = .optimal,
        .usage = usage,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .initial_layout = .undefined,
    }, Context.self.allocation_callbacks);
    errdefer Context.self.vkd.destroyImage(Context.self.device, self.handle, Context.self.allocation_callbacks);

    var memory_requirements: vk.MemoryRequirements2 = .{ .memory_requirements = undefined };

    Context.self.vkd.getImageMemoryRequirements2(Context.self.device, &vk.ImageMemoryRequirementsInfo2{
        .image = self.handle,
    }, &memory_requirements);

    self.size = memory_requirements.memory_requirements.size;
    self.alignment = memory_requirements.memory_requirements.alignment;

    self.memory_page = try Context.devicePageAllocateImage(self.handle, .{ .device_local_bit = true });
    errdefer Context.devicePageFree(self.memory_page);

    self.view = try Context.self.vkd.createImageView(Context.self.device, &.{
        .flags = .{},
        .image = self.handle,
        .view_type = @as(vk.ImageViewType, switch (@"type") {
            .@"1d" => .@"1d",
            .@"2d" => .@"2d",
            .@"3d" => .@"3d",
            .cube => .cube,
            .@"1d_array" => .@"1d_array",
            .@"2d_array" => .@"2d_array",
            .cube_array => .cube_array,
        }),
        .format = self.format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = self.aspect_mask,
            .base_mip_level = 0,
            .level_count = levels,
            .base_array_layer = 0,
            .layer_count = vk.REMAINING_ARRAY_LAYERS,
        },
    }, Context.self.allocation_callbacks);
    errdefer Context.self.vkd.destroyImageView(Context.self.device, self.view, Context.self.allocation_callbacks);

    if (layout == .transfer_dst_optimal or usage.transfer_dst_bit) {
        var command_buffer = try CommandBuffer.init(.graphics);
        defer command_buffer.deinit();

        {
            try command_buffer.begin();

            Context.self.vkd.cmdPipelineBarrier2(command_buffer.handle, &.{
                .dependency_flags = .{
                    .by_region_bit = true,
                },
                .memory_barrier_count = 0,
                .p_memory_barriers = undefined,
                .buffer_memory_barrier_count = 0,
                .p_buffer_memory_barriers = undefined,
                .image_memory_barrier_count = 1,
                .p_image_memory_barriers = @as([*]const vk.ImageMemoryBarrier2, @ptrCast(&vk.ImageMemoryBarrier2{
                    .src_stage_mask = .{
                        .top_of_pipe_bit = true,
                    },
                    .dst_stage_mask = .{
                        .copy_bit = true,
                    },
                    .src_access_mask = .{},
                    .dst_access_mask = .{
                        .transfer_write_bit = true,
                    },
                    .old_layout = .undefined,
                    .new_layout = .transfer_dst_optimal,
                    .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .image = self.handle,
                    .subresource_range = .{
                        .aspect_mask = self.aspect_mask,
                        .base_mip_level = 0,
                        .level_count = vk.REMAINING_MIP_LEVELS,
                        .base_array_layer = 0,
                        .layer_count = vk.REMAINING_ARRAY_LAYERS,
                    },
                })),
            });

            command_buffer.end();
            try command_buffer.submitAndWait();
        }
    }

    return self;
}

pub fn initInitialLayout(
    @"type": Type,
    width: u32,
    height: u32,
    depth: u32,
    levels: u32,
    format: vk.Format,
    usage: vk.ImageUsageFlags,
) !Image {
    var self = Image{
        .handle = .null_handle,
        .type = @"type",
        .view = .null_handle,
        .memory_page = undefined,
        .format = format,
        .layout = .undefined,
        .width = width,
        .height = height,
        .depth = depth,
        .levels = levels,
        .aspect_mask = .{
            .color_bit = format != vk.Format.d32_sfloat,
            .depth_bit = format == vk.Format.d32_sfloat,
        },
        .size = undefined,
        .alignment = undefined,
    };

    self.handle = try Context.self.vkd.createImage(Context.self.device, &.{
        .flags = vk.ImageCreateFlags{
            .alias_bit = true,
            .cube_compatible_bit = @"type" == .cube,
        },
        .image_type = @as(vk.ImageType, switch (@"type") {
            .@"1d" => .@"1d",
            .@"2d" => .@"2d",
            .@"3d" => .@"3d",
            .cube => .@"2d",
            .@"1d_array" => .@"2d",
            .@"2d_array" => .@"3d",
            .cube_array => .@"3d",
        }),
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = if (@"type" == .cube) 1 else depth },
        .mip_levels = levels,
        .array_layers = if (@"type" == .cube) depth else 1,
        .samples = .{
            .@"1_bit" = true,
        },
        .tiling = .optimal,
        .usage = usage,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
        .initial_layout = .undefined,
    }, Context.self.allocation_callbacks);
    errdefer Context.self.vkd.destroyImage(Context.self.device, self.handle, Context.self.allocation_callbacks);

    var memory_requirements: vk.MemoryRequirements2 = .{ .memory_requirements = undefined };

    Context.self.vkd.getImageMemoryRequirements2(Context.self.device, &vk.ImageMemoryRequirementsInfo2{
        .image = self.handle,
    }, &memory_requirements);

    self.size = memory_requirements.memory_requirements.size;
    self.alignment = memory_requirements.memory_requirements.alignment;

    self.memory_page = try Context.devicePageAllocateImage(self.handle, .{ .device_local_bit = true });
    errdefer Context.devicePageFree(self.memory_page);

    self.view = try Context.self.vkd.createImageView(Context.self.device, &.{
        .flags = .{},
        .image = self.handle,
        .view_type = @as(vk.ImageViewType, switch (@"type") {
            .@"1d" => .@"1d",
            .@"2d" => .@"2d",
            .@"3d" => .@"3d",
            .cube => .cube,
            .@"1d_array" => .@"1d_array",
            .@"2d_array" => .@"2d_array",
            .cube_array => .cube_array,
        }),
        .format = self.format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = self.aspect_mask,
            .base_mip_level = 0,
            .level_count = levels,
            .base_array_layer = 0,
            .layer_count = vk.REMAINING_ARRAY_LAYERS,
        },
    }, Context.self.allocation_callbacks);
    errdefer Context.self.vkd.destroyImageView(Context.self.device, self.view, Context.self.allocation_callbacks);

    return self;
}

pub fn deinit(self: *Image) void {
    defer self.* = undefined;

    defer Context.self.vkd.destroyImage(Context.self.device, self.handle, Context.self.allocation_callbacks);
    defer Context.self.vkd.destroyImageView(Context.self.device, self.view, Context.self.allocation_callbacks);
    defer Context.devicePageFree(self.memory_page);
}

pub const View = struct {
    image: *const Image,
    handle: vk.ImageView,
    level: u32,
    level_count: u32,
};

pub fn createView(self: *const Image, level: u32, level_count: u32) !View {
    var view = View{
        .image = self,
        .handle = .null_handle,
        .level = level,
        .level_count = level_count,
    };

    view.handle = try Context.self.vkd.createImageView(Context.self.device, &.{
        .flags = .{},
        .image = self.handle,
        .view_type = .@"2d",
        .format = self.format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = self.aspect_mask,
            .base_mip_level = level,
            .level_count = level_count,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, Context.self.allocation_callbacks);
    errdefer Context.self.vkd.destroyImageView(Context.self.device, view.handle, Context.self.allocation_callbacks);

    return view;
}

pub fn destroyView(self: Image, view: Image.View) void {
    _ = self;

    defer Context.self.vkd.destroyImageView(Context.self.device, view.handle, Context.self.allocation_callbacks);
}

const Image = @This();
const std = @import("std");
const vk = @import("vk.zig");
const Context = @import("Context.zig");
const CommandBuffer = @import("CommandBuffer.zig");
const Buffer = @import("Buffer.zig");
