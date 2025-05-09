pub const enable_khronos_validation = quanta_options.graphics.api_validation;
pub const enable_debug_messenger = @import("builtin").mode == .Debug;
pub const enable_debug_labels = @import("builtin").mode == .Debug;
pub const vulkan_version = std.SemanticVersion{
    .major = 1,
    .minor = 3,
    .patch = 0,
};

pub const vk_apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .createInstance = true,
            .enumerateInstanceLayerProperties = true,
        },
        .instance_commands = .{
            .destroyInstance = true,
            .createDevice = true,
            .destroySurfaceKHR = true,
            .enumeratePhysicalDevices = true,
            .getPhysicalDeviceProperties2 = true,
            .enumerateDeviceExtensionProperties = true,
            .getPhysicalDeviceSurfaceFormatsKHR = true,
            .getPhysicalDeviceSurfacePresentModesKHR = true,
            .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
            .getPhysicalDeviceQueueFamilyProperties = true,
            .getPhysicalDeviceSurfaceSupportKHR = true,
            .getPhysicalDeviceMemoryProperties2 = true,
            .getPhysicalDeviceFeatures2 = true,
            .getDeviceProcAddr = true,
            .getPhysicalDeviceFeatures = true,
            .createDebugUtilsMessengerEXT = enable_debug_messenger,
            .destroyDebugUtilsMessengerEXT = enable_debug_messenger,
            .createXcbSurfaceKHR = quanta_options.windowing.preferred_backend == .xcb,
            .createWin32SurfaceKHR = quanta_options.windowing.preferred_backend == .win32,
        },
        .device_commands = .{
            .destroyDevice = true,
            .getDeviceQueue = true,
            .createPipelineCache = true,
            .createDescriptorSetLayout = true,
            .createSemaphore = true,
            .createFence = true,
            .createImageView = true,
            .destroyImageView = true,
            .destroySemaphore = true,
            .destroyFence = true,
            .getSwapchainImagesKHR = true,
            .createSwapchainKHR = true,
            .destroySwapchainKHR = true,
            .deviceWaitIdle = true,
            .waitForFences = true,
            .resetFences = true,
            .queueSubmit2 = true,
            .queuePresentKHR = true,
            .createCommandPool = true,
            .destroyCommandPool = true,
            .allocateCommandBuffers = true,
            .freeCommandBuffers = true,
            .queueWaitIdle = true,
            .createShaderModule = true,
            .destroyShaderModule = true,
            .createPipelineLayout = true,
            .destroyPipelineLayout = true,
            .createRenderPass = true,
            .destroyRenderPass = true,
            .createGraphicsPipelines = true,
            .createComputePipelines = true,
            .destroyPipeline = true,
            .createFramebuffer = true,
            .destroyFramebuffer = true,
            .beginCommandBuffer = true,
            .endCommandBuffer = true,
            .allocateMemory = true,
            .freeMemory = true,
            .createBuffer = true,
            .destroyBuffer = true,
            .getBufferMemoryRequirements2 = true,
            .mapMemory = true,
            .unmapMemory = true,
            .bindBufferMemory = true,
            .cmdBindPipeline = true,
            .cmdDraw = true,
            .cmdSetViewport = true,
            .cmdSetScissor = true,
            .cmdBindVertexBuffers = true,
            .cmdCopyBuffer = true,
            .cmdFillBuffer = true,
            .cmdUpdateBuffer = true,
            .createImage = true,
            .getImageMemoryRequirements2 = true,
            .destroyImage = true,
            .bindImageMemory = true,
            .getPipelineCacheData = true,
            .resetCommandBuffer = true,
            .cmdBindIndexBuffer = true,
            .cmdPushConstants = true,
            .cmdDrawIndexed = true,
            .destroyDescriptorPool = true,
            .destroyDescriptorSetLayout = true,
            .destroyPipelineCache = true,
            .cmdBeginRendering = true,
            .cmdEndRendering = true,
            .cmdDispatch = true,
            .cmdBindDescriptorSets = true,
            .allocateDescriptorSets = true,
            .freeDescriptorSets = true,
            .createDescriptorPool = true,
            .updateDescriptorSets = true,
            .cmdPipelineBarrier2 = true,
            .cmdCopyBufferToImage2 = true,
            .createSampler = true,
            .destroySampler = true,
            .cmdDispatchIndirect = true,
            .cmdDrawIndexedIndirect = true,
            .cmdDrawIndexedIndirectCount = true,
            .cmdDrawIndirectCount = true,
            .cmdSetEvent = true,
            .cmdSetEvent2 = true,
            .getEventStatus = true,
            .createEvent = true,
            .destroyEvent = true,
            .getFenceStatus = true,
            .createQueryPool = false,
            .destroyQueryPool = false,
            .cmdWriteTimestamp2 = false,
            .resetQueryPool = false,
            .cmdResetQueryPool = false,
            .cmdBeginQuery = false,
            .cmdEndQuery = false,
            .getQueryPoolResults = false,
            .getBufferDeviceAddress = true,
            .waitSemaphores = true,
            .acquireNextImage2KHR = true,
            .releaseSwapchainImagesEXT = true,
            .cmdBlitImage2 = true,
            .cmdBeginDebugUtilsLabelEXT = enable_debug_labels,
            .cmdEndDebugUtilsLabelEXT = enable_debug_labels,
            .setDebugUtilsObjectNameEXT = enable_debug_labels,
        },
    },
    vk.features.version_1_3,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};

pub const BaseDispatch = vk.BaseWrapper(vk_apis);
pub const InstanceDispatch = vk.InstanceWrapper(vk_apis);
pub const DeviceDispatch = vk.DeviceWrapper(vk_apis);

var vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr = undefined;

fn getInstanceProcAddress(instance: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    log.info("Loading {s}", .{name});

    return vkGetInstanceProcAddr(instance, name);
}

fn debugUtilsMessengerCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_types;
    _ = p_user_data;

    //I don't know if a message can have multiple severity bits set, but I don't even know what that would mean semantically
    if (message_severity.error_bit_ext) {
        log.err("(vulkan_validation):\n\n({s}): {s}\n\n", .{
            p_callback_data.?.p_message_id_name orelse "",
            p_callback_data.?.p_message.?,
        });

        if (quanta_options.graphics.panic_on_validation_error) blk: {
            const message_id_name = std.mem.span(p_callback_data.?.p_message_id_name.?);

            for (quanta_options.graphics.validation_error_id_blacklist) |blacklisted_id| {
                if (std.mem.eql(u8, message_id_name, blacklisted_id)) {
                    break :blk;
                }
            }

            @panic("(vulkan_validation): Validation Error");
        }
    } else if (message_severity.warning_bit_ext) {
        log.warn("(vulkan_validation):\n\n{s} {s}\n\n", .{
            p_callback_data.?.p_message_id_name orelse "",
            p_callback_data.?.p_message.?,
        });

        //This is inherently supposed to be unrecoverable: The prorgam is in an invalid state: fix it
        // @panic("");
    } else {
        log.debug("{s} {s}", .{ p_callback_data.?.p_message_id_name orelse "", p_callback_data.?.p_message.? });
    }

    return vk.FALSE;
}

fn vulkanAllocate(
    user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    _: vk.SystemAllocationScope,
) callconv(vk.vulkan_call_conv) ?*anyopaque {
    _ = user_data;

    const memory = (self.gpa.rawAlloc(size + @sizeOf(usize), .fromByteUnits(@as(u8, @intCast(alignment))), @returnAddress()) orelse
        {
            @panic("Allocation failed!");
        })[0 .. size + @sizeOf(usize)];

    @as(*usize, @ptrCast(@alignCast(memory.ptr))).* = size;

    return memory.ptr + @sizeOf(usize);
}

fn vulkanReallocate(
    user_data: ?*anyopaque,
    original: ?*anyopaque,
    new_size: usize,
    alignment: usize,
    _: vk.SystemAllocationScope,
) callconv(vk.vulkan_call_conv) ?*anyopaque {
    const original_pointer = @as([*]u8, @ptrCast(original.?)) - @sizeOf(usize);
    const old_size = @as(*usize, @ptrCast(@alignCast(original_pointer))).*;

    const old_memory = original_pointer[0 .. old_size + @sizeOf(usize)];

    if (new_size > old_size) {
        const memory_ptr = self.gpa.rawAlloc(new_size + @sizeOf(usize), .fromByteUnits(@as(u8, @intCast(alignment))), @returnAddress()) orelse {
            @panic("Allocation failed!");
        };

        @as(*usize, @ptrCast(@alignCast(memory_ptr))).* = new_size;

        const allocation_ptr = memory_ptr + @sizeOf(usize);

        @memcpy(allocation_ptr[0..old_size], old_memory[@sizeOf(usize) .. @sizeOf(usize) + old_size]);

        vulkanFree(user_data, original);

        return allocation_ptr;
    } else {
        if (!self.gpa.rawResize(old_memory, .fromByteUnits(@as(u8, @intCast(alignment))), new_size, @returnAddress())) {
            @panic("Allocation failed!");
        }
    }

    @as(*usize, @ptrCast(@alignCast(old_memory.ptr))).* = new_size;

    return old_memory.ptr + @sizeOf(usize);
}

fn vulkanFree(
    user_data: ?*anyopaque,
    memory: ?*anyopaque,
) callconv(vk.vulkan_call_conv) void {
    if (memory == null) return;

    _ = user_data;

    const pointer = @as([*]u8, @ptrCast(memory.?)) - @sizeOf(usize);
    const size = @as(*usize, @ptrCast(@alignCast(pointer))).*;
    //TODO: This is VERY dodgy, and we *might* have to store alignment in the allocation
    const alignment = 256;

    self.gpa.rawFree(pointer[0 .. size + @sizeOf(usize)], .fromByteUnits(std.math.log2(alignment)), @returnAddress());
}

pub var self: Context = undefined;

gpa: std.mem.Allocator,
arena: std.mem.Allocator,

vulkan_loader: std.DynLib,
vkb: BaseDispatch,
vki: InstanceDispatch,
vkd: DeviceDispatch,
allocation_callbacks_data: vk.AllocationCallbacks,
allocation_callbacks: ?*vk.AllocationCallbacks,
instance: vk.Instance,
device: vk.Device,
physical_device: vk.PhysicalDevice,
physical_device_properties: vk.PhysicalDeviceProperties,
physical_device_subgroup_properties: vk.PhysicalDeviceSubgroupProperties,
physical_device_features: vk.PhysicalDeviceFeatures,
physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
surface: WindowSurface,
surface_capabilities: vk.SurfaceCapabilitiesKHR,
surface_format: vk.SurfaceFormatKHR,
surface_present_mode: vk.PresentModeKHR,
graphics_family_index: ?u32,
present_family_index: ?u32,
compute_family_index: ?u32,
transfer_family_index: ?u32,
graphics_queue: vk.Queue,
present_queue: vk.Queue,
compute_queue: vk.Queue,
transfer_queue: vk.Queue,
graphics_command_pool: vk.CommandPool,
present_command_pool: vk.CommandPool,
compute_command_pool: vk.CommandPool,
transfer_command_pool: vk.CommandPool,
pipeline_cache: vk.PipelineCache,
debug_messenger: if (enable_debug_messenger) vk.DebugUtilsMessengerEXT else void,
memories_by_type: []std.ArrayListUnmanaged(DeviceMemory),
pages: std.ArrayListUnmanaged(DevicePageMemory),
initial_memory_budgets: []usize,
required_extensions: RequiredExtensions,
optional_extensions: OptionalExtensions,

///Required *device* extensions
pub const RequiredExtensions = struct {
    khr_swapchain: [:0]const u8 = vk.extensions.khr_swapchain.name,
    khr_spirv_1_4: [:0]const u8 = vk.extensions.khr_spirv_1_4.name,
};

///Optional *device* extensions
///If the extension is supported at runtime, it is kept as non-null, otherwise it's set to null
pub const OptionalExtensions = struct {
    ext_memory_budget: ?[:0]const u8 = vk.extensions.ext_memory_budget.name,
    ext_swapchain_maintenance_1: ?[:0]const u8 = vk.extensions.ext_swapchain_maintenance_1.name,
    ext_surface_maintenance_1: ?[:0]const u8 = vk.extensions.ext_surface_maintenance_1.name,
};

pub const InitOptions = struct {
    ///Specify the preferred physical device to use
    ///a value of null indicates that a device selection algorithm should be used
    preferred_device_index: ?u32 = null,
};

pub fn init(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    window: *Window,
    pipeline_cache_data: []const u8,
    init_options: InitOptions,
) !void {
    self.gpa = gpa;
    self.arena = arena;
    self.required_extensions = .{};
    self.optional_extensions = .{};

    var init_arena_instance: std.heap.ArenaAllocator = .init(arena);
    defer init_arena_instance.deinit();

    const init_arena = init_arena_instance.allocator();

    const vulkan_loader_path = switch (builtin.os.tag) {
        .linux, .freebsd => "libvulkan.so.1",
        .windows => "vulkan-1.dll",
        .macos => "libvulkan.1.dylib",
        else => @compileError("Targeted os doesn't support the Khronos vulkan loader!"),
    };

    self.vulkan_loader = try std.DynLib.open(vulkan_loader_path);
    errdefer self.vulkan_loader.close();

    vkGetInstanceProcAddr = self.vulkan_loader.lookup(@TypeOf(vkGetInstanceProcAddr), "vkGetInstanceProcAddr") orelse return error.LoaderProcedureNotFound;

    self.allocation_callbacks_data = .{
        .p_user_data = null,
        .pfn_allocation = &vulkanAllocate,
        .pfn_reallocation = &vulkanReallocate,
        .pfn_free = &vulkanFree,
        .pfn_internal_allocation = null,
        .pfn_internal_free = null,
    };
    self.allocation_callbacks = if (quanta_options.graphics.use_custom_allocator) &self.allocation_callbacks_data else null;

    self.vkb = try BaseDispatch.load(getInstanceProcAddress);

    comptime var instance_extentions: []const [*:0]const u8 = &.{};

    if (enable_debug_messenger) {
        instance_extentions = instance_extentions ++ [_][*:0]const u8{vk.extensions.ext_debug_utils.name};
    }

    instance_extentions = instance_extentions ++ [_][*:0]const u8{vk.extensions.khr_surface.name};

    switch (quanta_options.windowing.preferred_backend) {
        .xcb => {
            instance_extentions = instance_extentions ++ [_][*:0]const u8{vk.extensions.khr_xcb_surface.name};
        },
        .win32 => {
            instance_extentions = instance_extentions ++ [_][*:0]const u8{vk.extensions.khr_win_32_surface.name};
        },
        else => @compileError("Windowing backend not supported by vulkan"),
    }

    log.info("Vulkan Version: {}", .{vulkan_version});
    log.info("Vulkan Instance Extentions: {s}", .{instance_extentions});

    comptime var requested_layers: []const [*:0]const u8 = &.{};

    if (enable_khronos_validation) {
        requested_layers = requested_layers ++ &[_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
        requested_layers = requested_layers ++ &[_][*:0]const u8{"VK_LAYER_KHRONOS_synchronization2"};
    }

    log.info("layers: {s}", .{requested_layers});

    var layers_array: [requested_layers.len][*:0]const u8 = undefined;
    var layers: [][*:0]const u8 = layers_array[0..0];

    if (requested_layers.len != 0) {
        var layer_count: u32 = 0;

        _ = try self.vkb.enumerateInstanceLayerProperties(&layer_count, null);

        const layer_properties = try init_arena.alloc(vk.LayerProperties, layer_count);

        _ = try self.vkb.enumerateInstanceLayerProperties(&layer_count, layer_properties.ptr);

        log.info("Available Layers:", .{});

        for (layer_properties) |layer_property| {
            const sentinel_index = std.mem.indexOfSentinel(u8, 0, @as([*:0]const u8, @ptrCast(&layer_property.layer_name)));

            log.info("  {s}", .{layer_property.layer_name[0..sentinel_index]});
        }

        inline for (requested_layers) |layer| {
            const found = block: for (layer_properties) |layer_property| {
                const first_sentinel_index = std.mem.indexOfSentinel(u8, 0, layer);
                const second_sentinel_index = std.mem.indexOfSentinel(u8, 0, @as([*:0]const u8, @ptrCast(&layer_property.layer_name)));

                const sentinel_index = @min(first_sentinel_index, second_sentinel_index);

                if (std.mem.eql(u8, layer[0..sentinel_index], layer_property.layer_name[0..sentinel_index])) {
                    break :block true;
                }
            } else false;

            if (found) {
                layers_array[layers.len] = layer;
                layers.len += 1;
            } else {
                log.err("Failed to find layer {s}", .{layer});
            }
        }
    }

    //Layer Settings if validation is enabled
    const layer_settings = [_]vk.LayerSettingEXT{
        .{
            .p_layer_name = "VK_LAYER_KHRONOS_validation",
            .p_setting_name = "validate_sync",
            .type = vk.LayerSettingTypeEXT.bool32_ext,
            .value_count = 1,
            .p_values = &@as(u32, vk.TRUE),
        },
        .{
            .p_layer_name = "VK_LAYER_KHRONOS_validation",
            .p_setting_name = "validate_best_practices",
            .type = vk.LayerSettingTypeEXT.bool32_ext,
            .value_count = 1,
            .p_values = &@as(u32, vk.TRUE),
        },
        .{
            .p_layer_name = "VK_LAYER_KHRONOS_validation",
            .p_setting_name = "validate_best_practices_nvidia",
            .type = vk.LayerSettingTypeEXT.bool32_ext,
            .value_count = 1,
            .p_values = &@as(u32, vk.TRUE),
        },
        .{
            .p_layer_name = "VK_LAYER_KHRONOS_validation",
            .p_setting_name = "check_image_layout",
            .type = vk.LayerSettingTypeEXT.bool32_ext,
            .value_count = 1,
            .p_values = &@as(u32, vk.TRUE),
        },
    };

    self.instance = try self.vkb.createInstance(&.{
        .p_next = if (enable_khronos_validation)
            &vk.LayerSettingsCreateInfoEXT{
                .setting_count = @intCast(layer_settings.len),
                .p_settings = &layer_settings,
            }
        else
            null,
        .flags = .{},
        .p_application_info = &vk.ApplicationInfo{
            .api_version = vk.makeApiVersion(
                0,
                vulkan_version.major,
                vulkan_version.minor,
                vulkan_version.patch,
            ),
            .application_version = 0,
            .engine_version = 0,
            .p_application_name = null,
            .p_engine_name = null,
        },
        .enabled_layer_count = @as(u32, @intCast(layers.len)),
        .pp_enabled_layer_names = requested_layers.ptr,
        .enabled_extension_count = @as(u32, @intCast(instance_extentions.len)),
        .pp_enabled_extension_names = instance_extentions.ptr,
    }, self.allocation_callbacks);

    self.vki = try InstanceDispatch.load(self.instance, getInstanceProcAddress);

    errdefer self.vki.destroyInstance(self.instance, self.allocation_callbacks);

    if (enable_debug_messenger) {
        self.debug_messenger = try self.vki.createDebugUtilsMessengerEXT(self.instance, &.{
            .flags = .{},
            .message_severity = .{ .info_bit_ext = true, .error_bit_ext = true },
            .message_type = .{ .performance_bit_ext = true, .validation_bit_ext = enable_khronos_validation },
            .pfn_user_callback = &debugUtilsMessengerCallback,
            .p_user_data = null,
        }, self.allocation_callbacks);
    }

    errdefer if (enable_debug_messenger) self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, self.allocation_callbacks);

    self.surface = try WindowSurface.init(window);
    errdefer self.surface.deinit();

    var device_extensions_buffer: [std.meta.fields(RequiredExtensions).len + std.meta.fields(OptionalExtensions).len][*:0]const u8 = undefined;
    var device_extension_count: usize = 0;

    inline for (comptime std.meta.fieldNames(RequiredExtensions)) |field_name| {
        device_extensions_buffer[device_extension_count] = @field(self.required_extensions, field_name);
        device_extension_count += 1;
    }

    const device_extentions = device_extensions_buffer[0..device_extension_count];

    var device_vulkan13_features = vk.PhysicalDeviceVulkan13Features{
        .dynamic_rendering = vk.TRUE,
        .synchronization_2 = vk.TRUE,
        .maintenance_4 = vk.TRUE,
        .subgroup_size_control = vk.TRUE,
        .compute_full_subgroups = vk.TRUE,
    };

    var device_vulkan12_features = vk.PhysicalDeviceVulkan12Features{
        .p_next = &device_vulkan13_features,
        .draw_indirect_count = vk.TRUE,
        .scalar_block_layout = vk.TRUE,
        .buffer_device_address = vk.TRUE,
        // .shader_input_attachment_array_dynamic_indexing = vk.TRUE,
        .shader_uniform_texel_buffer_array_dynamic_indexing = vk.TRUE,
        .shader_storage_texel_buffer_array_dynamic_indexing = vk.TRUE,
        .shader_uniform_buffer_array_non_uniform_indexing = vk.TRUE,
        .shader_sampled_image_array_non_uniform_indexing = vk.TRUE,
        .shader_storage_buffer_array_non_uniform_indexing = vk.TRUE,
        .shader_storage_image_array_non_uniform_indexing = vk.TRUE,
        // .shader_input_attachment_array_non_uniform_indexing = vk.FALSE,
        .shader_uniform_texel_buffer_array_non_uniform_indexing = vk.TRUE,
        .shader_storage_texel_buffer_array_non_uniform_indexing = vk.TRUE,
        .descriptor_binding_uniform_buffer_update_after_bind = vk.TRUE,
        .descriptor_binding_sampled_image_update_after_bind = vk.TRUE,
        .descriptor_binding_storage_image_update_after_bind = vk.TRUE,
        .descriptor_binding_storage_buffer_update_after_bind = vk.TRUE,
        .descriptor_binding_uniform_texel_buffer_update_after_bind = vk.TRUE,
        .descriptor_binding_storage_texel_buffer_update_after_bind = vk.TRUE,
        .descriptor_binding_update_unused_while_pending = vk.TRUE,
        .descriptor_binding_partially_bound = vk.TRUE,
        .descriptor_binding_variable_descriptor_count = vk.TRUE,
        .runtime_descriptor_array = vk.TRUE,
    };

    var device_vulkan11_features = vk.PhysicalDeviceVulkan11Features{
        .p_next = &device_vulkan12_features,
        .shader_draw_parameters = vk.TRUE,
    };

    log.info("Required device extensions: {s}", .{device_extentions});
    log.info("Required device features:", .{});

    inline for ((comptime std.meta.fieldNames(@TypeOf(device_vulkan13_features))[2..])) |feature_name| {
        if (@field(device_vulkan13_features, feature_name) == vk.TRUE) {
            log.info("  {s}", .{feature_name});
        }
    }

    //Find physical device
    {
        var physical_device_count: u32 = 0;

        _ = try self.vki.enumeratePhysicalDevices(self.instance, &physical_device_count, null);

        const physical_devices = try init_arena.alloc(vk.PhysicalDevice, physical_device_count);

        _ = try self.vki.enumeratePhysicalDevices(self.instance, &physical_device_count, physical_devices.ptr);

        var found_suitable_device = false;

        log.info("Available devices:", .{});

        for (physical_devices, 0..) |physical_device, i| {
            var properties: vk.PhysicalDeviceProperties2 = .{
                .properties = undefined,
            };

            self.vki.getPhysicalDeviceProperties2(physical_device, &properties);

            log.info("Device [{}] {s}: api_version: {}.{}.{}.{}", .{
                i,
                properties.properties.device_name[0..std.mem.indexOfScalar(u8, &properties.properties.device_name, 0).?],
                vk.apiVersionMajor(properties.properties.api_version),
                vk.apiVersionMinor(properties.properties.api_version),
                vk.apiVersionPatch(properties.properties.api_version),
                vk.apiVersionVariant(properties.properties.api_version),
            });
        }

        for (physical_devices, 0..) |physical_device, device_index| {
            var subgroup_properties: vk.PhysicalDeviceSubgroupProperties = .{
                .subgroup_size = 0,
                .supported_stages = .{},
                .supported_operations = .{},
                .quad_operations_in_all_stages = vk.FALSE,
            };

            var properties: vk.PhysicalDeviceProperties2 = .{
                .p_next = &subgroup_properties,
                .properties = undefined,
            };

            self.vki.getPhysicalDeviceProperties2(physical_device, &properties);
            self.physical_device_properties = properties.properties;
            self.physical_device_subgroup_properties = subgroup_properties;
            self.physical_device_features = self.vki.getPhysicalDeviceFeatures(physical_device);

            log.info("Device Subgroup size: {}", .{subgroup_properties.subgroup_size});

            log.info("Device [{}] {s}: api_version: {}.{}.{}.{}", .{
                device_index,
                self.physical_device_properties.device_name,
                vk.apiVersionMajor(self.physical_device_properties.api_version),
                vk.apiVersionMinor(self.physical_device_properties.api_version),
                vk.apiVersionPatch(self.physical_device_properties.api_version),
                vk.apiVersionVariant(self.physical_device_properties.api_version),
            });

            const is_version_suitable = vk.apiVersionMajor(self.physical_device_properties.api_version) >= vulkan_version.major and
                vk.apiVersionMinor(self.physical_device_properties.api_version) >= vulkan_version.minor;

            if (!is_version_suitable) {
                continue;
            }

            var queue_family_count: u32 = 0;

            self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);

            const queue_families = try init_arena.alloc(vk.QueueFamilyProperties, queue_family_count);

            self.vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_families.ptr);

            for (queue_families, 0..) |queue_family, queue_family_index| {
                if (queue_family.queue_flags.graphics_bit) {
                    self.graphics_family_index = @as(u32, @intCast(queue_family_index));
                    //Set transfer family to graphics family just in case no dedicated transfer queue is supported
                    self.transfer_family_index = @as(u32, @intCast(queue_family_index));
                }

                if (queue_family.queue_flags.compute_bit) {
                    self.compute_family_index = @as(u32, @intCast(queue_family_index));
                }

                //TODO: If a dedicated transfer queue doesn't exist, assign it to a non dedicated one such as compute or graphics
                if (queue_family.queue_flags.transfer_bit and
                    queue_family.queue_flags.sparse_binding_bit and
                    !queue_family.queue_flags.video_decode_bit_khr and
                    !queue_family.queue_flags.compute_bit and
                    !queue_family.queue_flags.graphics_bit)
                {
                    self.transfer_family_index = @as(u32, @intCast(queue_family_index));
                }

                const surface_supported = try self.vki.getPhysicalDeviceSurfaceSupportKHR(physical_device, @as(u32, @intCast(queue_family_index)), self.surface.surface);

                if (surface_supported == vk.TRUE) {
                    self.present_family_index = @as(u32, @intCast(queue_family_index));
                } else {
                    std.log.info("Suface properties: cap: {} fmt: {} are not supported by the device", .{ self.surface_capabilities, self.surface_format });
                }
            }

            var physical_device_extention_count: u32 = undefined;

            _ = try self.vki.enumerateDeviceExtensionProperties(physical_device, null, &physical_device_extention_count, null);

            const physical_device_extentions = try init_arena.alloc(vk.ExtensionProperties, physical_device_extention_count);

            _ = try self.vki.enumerateDeviceExtensionProperties(physical_device, null, &physical_device_extention_count, physical_device_extentions.ptr);

            const supports_extentions = block: for (device_extentions) |required_extention| {
                for (physical_device_extentions) |physical_device_extention| {
                    const sentinel_index = std.mem.indexOfSentinel(u8, 0, required_extention);

                    if (std.mem.eql(u8, physical_device_extention.extension_name[0..sentinel_index], required_extention[0..sentinel_index])) {
                        break :block true;
                    }
                } else {
                    log.info("Device {s} doesn't support required extention {s}", .{ self.physical_device_properties.device_name, required_extention });

                    break :block false;
                }
            } else false;

            var physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties2 = .{
                .memory_properties = undefined,
            };

            self.vki.getPhysicalDeviceMemoryProperties2(physical_device, &physical_device_memory_properties);

            self.physical_device_memory_properties = physical_device_memory_properties.memory_properties;
            self.surface_capabilities = try self.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, self.surface.surface);

            var surface_format_count: u32 = 0;

            _ = try self.vki.getPhysicalDeviceSurfaceFormatsKHR(physical_device, self.surface.surface, &surface_format_count, null);

            const surface_formats = try init_arena.alloc(vk.SurfaceFormatKHR, surface_format_count);

            _ = try self.vki.getPhysicalDeviceSurfaceFormatsKHR(physical_device, self.surface.surface, &surface_format_count, surface_formats.ptr);

            var surface_present_mode_count: u32 = 0;

            _ = try self.vki.getPhysicalDeviceSurfacePresentModesKHR(physical_device, self.surface.surface, &surface_present_mode_count, null);

            const surface_present_modes = try init_arena.alloc(vk.PresentModeKHR, surface_present_mode_count);

            _ = try self.vki.getPhysicalDeviceSurfacePresentModesKHR(physical_device, self.surface.surface, &surface_present_mode_count, surface_present_modes.ptr);

            if (surface_formats.len == 0 or surface_present_modes.len == 0) {
                continue;
            }

            for (surface_formats) |surface_format| {
                if (surface_format.format == .b8g8r8a8_srgb and surface_format.color_space == .srgb_nonlinear_khr) {
                    self.surface_format = surface_format;

                    break;
                }
            }

            for (surface_present_modes) |surface_present_mode| {
                log.info("  surface_present_mode: {}", .{surface_present_mode});

                if (surface_present_mode == .mailbox_khr or surface_present_mode == .fifo_khr) {
                    self.surface_present_mode = surface_present_mode;

                    break;
                }
            }

            if (init_options.preferred_device_index) |preferred_device_index| {
                if (preferred_device_index == device_index) {
                    //TODO: check that the preferred device supports everything
                    self.physical_device = physical_device;
                    found_suitable_device = true;
                }
            }

            //If there's only one gpu, use it even if it's integrated
            const use_integrated = physical_devices.len == 1;

            if (self.physical_device_features.geometry_shader == 1 and
                self.graphics_family_index != null and
                self.present_family_index != null and
                self.compute_family_index != null and
                self.transfer_family_index != null and
                supports_extentions)
            blk: {
                if (!use_integrated and self.physical_device_properties.device_type != .discrete_gpu) {
                    break :blk;
                }

                if (init_options.preferred_device_index) |preferred_index| {
                    if (device_index != preferred_index) {
                        break :blk;
                    }
                }

                self.physical_device = physical_device;
                found_suitable_device = true;

                break;
            }
        }

        if (!found_suitable_device) {
            return error.FailedToFindSuitableDevice;
        }
    }

    //Create queue command pools
    {
        var queue_family_indices: [4]usize = undefined;

        var queue_create_info_buffer: [4]vk.DeviceQueueCreateInfo = undefined;
        var queue_create_info_count: usize = 0;

        if (self.graphics_family_index) |queue_idx| add_queue_family: {
            if (std.mem.indexOfScalar(usize, queue_family_indices[0..queue_create_info_count], queue_idx)) |_| {
                break :add_queue_family;
            }

            queue_family_indices[queue_create_info_count] = queue_idx;
            queue_create_info_buffer[queue_create_info_count] = .{
                .flags = .{},
                .queue_family_index = queue_idx,
                .queue_count = 1,
                .p_queue_priorities = @as([*]const f32, @ptrCast(&@as(f32, 1.0))),
            };
            queue_create_info_count += 1;
        }

        if (self.compute_family_index) |queue_idx| add_queue_family: {
            if (std.mem.indexOfScalar(usize, queue_family_indices[0..queue_create_info_count], queue_idx)) |_| {
                break :add_queue_family;
            }

            queue_family_indices[queue_create_info_count] = queue_idx;
            queue_create_info_buffer[queue_create_info_count] = .{
                .flags = .{},
                .queue_family_index = queue_idx,
                .queue_count = 1,
                .p_queue_priorities = @as([*]const f32, @ptrCast(&@as(f32, 1.0))),
            };
            queue_create_info_count += 1;
        }

        if (self.transfer_family_index) |queue_idx| add_queue_family: {
            if (std.mem.indexOfScalar(usize, queue_family_indices[0..queue_create_info_count], queue_idx)) |_| {
                break :add_queue_family;
            }

            queue_family_indices[queue_create_info_count] = queue_idx;
            queue_create_info_buffer[queue_create_info_count] = .{
                .flags = .{},
                .queue_family_index = queue_idx,
                .queue_count = 1,
                .p_queue_priorities = @as([*]const f32, @ptrCast(&@as(f32, 1.0))),
            };
            queue_create_info_count += 1;
        }

        const queue_create_infos = queue_create_info_buffer[0..queue_create_info_count];

        log.info("self.graphics_family_index = {?}", .{self.graphics_family_index});
        log.info("self.present_family_index = {?}", .{self.present_family_index});
        log.info("self.compute_family_index = {?}", .{self.compute_family_index});
        log.info("self.transfer_family_index = {?}", .{self.transfer_family_index});

        var physical_device_features: vk.PhysicalDeviceFeatures2 = .{
            .p_next = &device_vulkan11_features,
            .features = .{},
        };

        self.vki.getPhysicalDeviceFeatures2(self.physical_device, &physical_device_features);

        var physical_device_extention_count: u32 = 0;

        _ = try self.vki.enumerateDeviceExtensionProperties(self.physical_device, null, &physical_device_extention_count, null);

        const physical_device_extentions = try init_arena.alloc(vk.ExtensionProperties, physical_device_extention_count);

        _ = try self.vki.enumerateDeviceExtensionProperties(self.physical_device, null, &physical_device_extention_count, physical_device_extentions.ptr);

        inline for (comptime std.meta.fieldNames(OptionalExtensions)) |field_name| {
            const extention_name = &@field(self.optional_extensions, field_name);
            const sentinel_index = std.mem.indexOfSentinel(u8, 0, extention_name.*.?);

            const supports_extention = block: for (physical_device_extentions) |physical_device_extention| {
                if (std.mem.eql(u8, physical_device_extention.extension_name[0..sentinel_index], extention_name.*.?[0..sentinel_index])) {
                    break :block true;
                }
            } else {
                log.info("Device {s} doesn't support optional extention {s}", .{ self.physical_device_properties.device_name, extention_name.*.? });

                extention_name.* = null;

                break :block false;
            };

            if (supports_extention) {
                device_extensions_buffer[device_extension_count] = @field(self.optional_extensions, field_name).?;
                device_extension_count += 1;
            }
        }

        const device_create_info = vk.DeviceCreateInfo{
            .p_next = &physical_device_features,
            .flags = .{},
            .p_queue_create_infos = queue_create_infos.ptr,
            .queue_create_info_count = @as(u32, @intCast(queue_create_infos.len)),
            .p_enabled_features = null,
            .enabled_extension_count = @as(u32, @intCast(device_extension_count)),
            .pp_enabled_extension_names = device_extentions.ptr,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
        };

        self.device = try self.vki.createDevice(self.physical_device, &device_create_info, self.allocation_callbacks);

        //TODO: handle failures again
        self.vkd = DeviceDispatch.loadNoFail(self.device, self.vki.dispatch.vkGetDeviceProcAddr);

        errdefer self.vkd.destroyDevice(self.device, self.allocation_callbacks);

        if (self.graphics_family_index) |index| {
            self.graphics_queue = self.vkd.getDeviceQueue(self.device, index, 0);
            self.graphics_command_pool = try self.vkd.createCommandPool(self.device, &.{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = index,
            }, self.allocation_callbacks);
        }

        if (self.present_family_index) |index| {
            self.present_queue = self.vkd.getDeviceQueue(self.device, index, 0);
            self.present_command_pool = try self.vkd.createCommandPool(self.device, &.{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = index,
            }, self.allocation_callbacks);
        }

        if (self.compute_family_index) |index| {
            self.compute_queue = self.vkd.getDeviceQueue(self.device, index, 0);
            self.compute_command_pool = try self.vkd.createCommandPool(self.device, &.{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = index,
            }, self.allocation_callbacks);
        }

        if (self.transfer_family_index) |index| {
            _ = index;
            //Whilst we can get a dedicated transfer queue, we currently assume elsewhere in the code that
            //this queue has graphics capability (and as such is not technically treated as dedicated yet)
            self.transfer_queue = self.vkd.getDeviceQueue(self.device, self.graphics_family_index.?, 0);
            self.transfer_command_pool = try self.vkd.createCommandPool(self.device, &.{
                .flags = .{ .reset_command_buffer_bit = true },
                .queue_family_index = self.graphics_family_index.?,
            }, self.allocation_callbacks);
        }
    }

    self.pipeline_cache = try self.vkd.createPipelineCache(
        self.device,
        &.{
            .flags = .{},
            .initial_data_size = pipeline_cache_data.len,
            .p_initial_data = if (pipeline_cache_data.len != 0) pipeline_cache_data.ptr else undefined,
        },
        self.allocation_callbacks,
    );
    errdefer self.vkd.destroyPipelineCache(self.device, self.pipeline_cache, self.allocation_callbacks);

    self.memories_by_type = try arena.alloc(std.ArrayListUnmanaged(DeviceMemory), self.physical_device_memory_properties.memory_heap_count);

    for (self.memories_by_type) |*memories| {
        memories.* = .{};
    }

    self.pages = .{};
    self.initial_memory_budgets = try arena.alloc(usize, self.physical_device_memory_properties.memory_heap_count);

    for (self.initial_memory_budgets, 0..) |*budget, i| {
        budget.* = getMemoryHeapBudget(@as(u32, @intCast(i)));

        log.info("Budget[{}] = {}", .{ i, budget.* });
    }
}

pub fn deinit() void {
    self.vkd.deviceWaitIdle(self.device) catch unreachable;

    defer self.vulkan_loader.close();
    defer self.vki.destroyInstance(self.instance, self.allocation_callbacks);
    defer if (enable_debug_messenger) self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, self.allocation_callbacks);
    defer self.surface.deinit();
    defer self.vkd.destroyDevice(self.device, self.allocation_callbacks);
    defer if (self.graphics_command_pool != .null_handle) self.vkd.destroyCommandPool(self.device, self.graphics_command_pool, self.allocation_callbacks);
    defer if (self.present_command_pool != .null_handle) self.vkd.destroyCommandPool(self.device, self.present_command_pool, self.allocation_callbacks);
    defer if (self.compute_command_pool != .null_handle) self.vkd.destroyCommandPool(self.device, self.compute_command_pool, self.allocation_callbacks);
    defer if (self.transfer_command_pool != .null_handle) self.vkd.destroyCommandPool(self.device, self.transfer_command_pool, self.allocation_callbacks);
    defer self.vkd.destroyPipelineCache(self.device, self.pipeline_cache, self.allocation_callbacks);
    defer for (self.memories_by_type) |*memories| {
        for (memories.items) |*memory| {
            deviceFree(memory.handle);
        }

        memories.deinit(self.gpa);
    };
    defer self.pages.deinit(self.gpa);
}

pub fn imageMemoryBarrier(
    command_buffer: vk.CommandBuffer,
    image: vk.Image,
    src_stage: vk.PipelineStageFlags2,
    dst_stage: vk.PipelineStageFlags2,
    src_access: vk.AccessFlags2,
    dst_access: vk.AccessFlags2,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) void {
    self.vkd.cmdPipelineBarrier2(command_buffer, &.{
        .dependency_flags = .{},
        .memory_barrier_count = 0,
        .p_memory_barriers = undefined,
        .buffer_memory_barrier_count = 0,
        .p_buffer_memory_barriers = undefined,
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = @as([*]const vk.ImageMemoryBarrier2, @ptrCast(&vk.ImageMemoryBarrier2{
            .src_stage_mask = src_stage,
            .dst_stage_mask = dst_stage,
            .src_access_mask = src_access,
            .dst_access_mask = dst_access,
            .old_layout = old_layout,
            .new_layout = new_layout,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = vk.REMAINING_MIP_LEVELS,
                .base_array_layer = 0,
                .layer_count = vk.REMAINING_ARRAY_LAYERS,
            },
        })),
    });
}

pub const MemoryType = struct {
    index: u32,
    heap_index: u32,
};

pub fn getMemoryType(requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !MemoryType {
    var memory_type_index: u32 = 0;

    while (memory_type_index < self.physical_device_memory_properties.memory_type_count) : (memory_type_index += 1) {
        const memory_type = self.physical_device_memory_properties.memory_types[memory_type_index];
        const has_properties = memory_type.property_flags.contains(properties);

        if (has_properties and
            ((@as(u32, 1) << @as(u5, @intCast(memory_type_index))) & requirements.memory_type_bits) != 0)
        {
            return .{ .index = memory_type_index, .heap_index = memory_type.heap_index };
        }
    }

    return error.MemoryTypeNotFound;
}

pub fn deviceAllocateWithMemoryType(size: usize, memory_type: MemoryType, dedicated_info: ?vk.MemoryDedicatedAllocateInfo) !vk.DeviceMemory {
    var device_memory_budget_properties: vk.PhysicalDeviceMemoryBudgetPropertiesEXT = .{
        .heap_budget = undefined,
        .heap_usage = undefined,
    };

    var device_memory_properties: vk.PhysicalDeviceMemoryProperties2 = .{
        .p_next = if (self.optional_extensions.ext_memory_budget != null) &device_memory_budget_properties else null,
        .memory_properties = undefined,
    };

    self.vki.getPhysicalDeviceMemoryProperties2(self.physical_device, &device_memory_properties);

    if (self.optional_extensions.ext_memory_budget != null) {
        const heap_usage = device_memory_budget_properties.heap_usage[memory_type.heap_index];
        const heap_budget = device_memory_budget_properties.heap_budget[memory_type.heap_index];

        if (heap_usage + size >= heap_budget) {
            return error.OutOfMemory;
        }

        log.info("gpu heap usage {}mb; budget {}mb", .{
            heap_usage / (1024 * 1024),
            heap_budget / (1024 * 1024),
        });
    }

    var memory_allocate_flags_info = vk.MemoryAllocateFlagsInfo{
        .p_next = if (dedicated_info != null) &dedicated_info.? else null,
        .flags = .{
            .device_address_bit = true,
        },
        .device_mask = 0,
    };

    return try self.vkd.allocateMemory(self.device, &.{
        .p_next = &memory_allocate_flags_info,
        .allocation_size = size,
        .memory_type_index = memory_type.index,
    }, self.allocation_callbacks);
}

pub fn deviceAllocate(requirements: vk.MemoryRequirements, properties: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    return try deviceAllocateWithMemoryType(
        requirements.size,
        try getMemoryType(requirements, properties),
        null,
    );
}

pub fn deviceFree(memory: vk.DeviceMemory) void {
    self.vkd.freeMemory(self.device, memory, self.allocation_callbacks);
}

pub const DeviceMemory = struct {
    handle: vk.DeviceMemory,
    next_offset: usize,
    size: vk.DeviceSize,
    mapped_address: ?[*]u8,
    ///Reference count for mapping memory
    map_count: u32,
};

pub const DevicePageMemory = struct {
    memory_index: u32,
    heap_index: u32,
    offset: vk.DeviceSize,
    size: vk.DeviceSize,
};

pub fn getMemoryHeapBudget(heap_index: u32) usize {
    if (self.optional_extensions.ext_memory_budget == null) {
        unreachable;
    }

    var device_memory_budget_properties: vk.PhysicalDeviceMemoryBudgetPropertiesEXT = .{
        .heap_budget = undefined,
        .heap_usage = undefined,
    };

    var device_memory_properties: vk.PhysicalDeviceMemoryProperties2 = .{
        .p_next = if (self.optional_extensions.ext_memory_budget != null) &device_memory_budget_properties else null,
        .memory_properties = undefined,
    };

    self.vki.getPhysicalDeviceMemoryProperties2(self.physical_device, &device_memory_properties);

    return device_memory_budget_properties.heap_budget[heap_index] - device_memory_budget_properties.heap_usage[heap_index];
}

pub const DevicePageHandle = enum(u32) { _ };

pub fn devicePageAllocate(
    size: usize,
    alignment: usize,
    memory_type_bits: u32,
    properties: vk.MemoryPropertyFlags,
    dedicated_info: ?vk.MemoryDedicatedAllocateInfo,
) !DevicePageHandle {
    const handle = @as(DevicePageHandle, @enumFromInt(@as(u32, @intCast(self.pages.items.len))));

    const requirements = vk.MemoryRequirements{ .size = size, .alignment = alignment, .memory_type_bits = memory_type_bits };
    const memory_type = try getMemoryType(requirements, properties);

    const memories = &self.memories_by_type[memory_type.heap_index];

    var page_memory_index: ?u32 = null;
    var page_memory_offset: usize = 0;

    for (memories.items, 0..) |*memory, i| {
        const next_offset = std.mem.alignForward(usize, memory.next_offset, alignment);

        const new_next_offset = next_offset + size;
        const suitable = new_next_offset <= memory.size;

        if (!suitable) {
            continue;
        }

        log.info("SUITABLE = {}", .{suitable});

        page_memory_index = @as(u32, @intCast(i));
        page_memory_offset = next_offset;

        memory.next_offset = new_next_offset;

        break;
    }

    //If there is no suitable memory, allocate a new one
    if (page_memory_index == null) {
        // const budget = self.initial_memory_budgets[memory_type.heap_index];
        // const budget = getMemoryHeapBudget(memory_type.heap_index);

        // const minimum_memory_size = budget / 8;

        // const initial_memory_size = if (memory_type.heap_index == 0 and dedicated_info == null) @max(minimum_memory_size, (alignment + size)) else size;
        const initial_memory_size = size;

        page_memory_index = @as(u32, @intCast(memories.items.len));

        const page_memory = try deviceAllocateWithMemoryType(initial_memory_size, memory_type, dedicated_info);
        errdefer deviceFree(page_memory);

        if (quanta_options.graphics.debug_logging) {
            log.info("Allocated a page of device memory: size = {}, alignment = {}", .{ size, alignment });
        }

        try memories.append(self.gpa, .{
            .handle = page_memory,
            .next_offset = alignment + size,
            .size = initial_memory_size,
            .map_count = 0,
            .mapped_address = null,
        });
    }

    try self.pages.append(self.gpa, .{
        .memory_index = page_memory_index.?,
        .heap_index = memory_type.heap_index,
        .offset = page_memory_offset,
        .size = size,
    });

    return handle;
}

pub fn devicePageFree(page: DevicePageHandle) void {
    const memory = devicePageGetMemory(page);
    const memory_handle = &self.memories_by_type[memory.heap_index].items[memory.memory_index];

    if (memory_handle.next_offset - memory.size == memory.offset) {
        memory_handle.next_offset -= memory.size;
    }

    if (memory_handle.next_offset == 0) {
        deviceFree(memory_handle.handle);

        memory_handle.handle = .null_handle;
        memory_handle.size = 0;
    }
}

pub fn devicePageGetMemory(page: DevicePageHandle) DevicePageMemory {
    return self.pages.items[@intFromEnum(page)];
}

pub fn devicePageMap(page: DevicePageHandle, comptime T: type, length: usize) ![]T {
    const page_memory = devicePageGetMemory(page);
    const memory = &self.memories_by_type[page_memory.heap_index].items[page_memory.memory_index];

    var data = @as(?[*]T, @ptrCast(@alignCast(memory.mapped_address)));

    if (memory.map_count == 0) {
        data = @as(?[*]T, @ptrCast(@alignCast(try Context.self.vkd.mapMemory(Context.self.device, memory.handle, 0, memory.size, .{}))));

        memory.mapped_address = @as([*]u8, @ptrCast(data));
    }

    data.? = data.? + page_memory.offset;

    memory.map_count += 1;

    return data.?[0..length];
}

pub fn devicePageUnmap(page: DevicePageHandle) void {
    const page_memory = devicePageGetMemory(page);
    const memory = &self.memories_by_type[page_memory.heap_index].items[page_memory.memory_index];

    memory.map_count -= 1;

    if (memory.map_count == 0) {
        Context.self.vkd.unmapMemory(self.device, memory.handle);
    }
}

pub fn devicePageBindToBuffer(buffer: vk.Buffer, page: DevicePageHandle, offset: usize) !void {
    const memory = devicePageGetMemory(page);
    const memory_handle = self.memories_by_type[memory.heap_index].items[memory.memory_index];

    try self.vkd.bindBufferMemory(self.device, buffer, memory_handle.handle, memory.offset + offset);
}

pub fn devicePageBindToImage(image: vk.Image, page: DevicePageHandle, offset: usize) !void {
    const memory = devicePageGetMemory(page);
    const memory_handle = self.memories_by_type[memory.heap_index].items[memory.memory_index];

    try self.vkd.bindImageMemory(self.device, image, memory_handle.handle, memory.offset + offset);
}

pub const BufferMemory = struct {
    memory: vk.DeviceMemory,
};

///Allocates a page dedicated to the specified buffer resource
pub fn deviceAllocateBuffer(buffer: vk.Buffer, properties: vk.MemoryPropertyFlags) !BufferMemory {
    var dedicated_requirements: vk.MemoryDedicatedRequirements = .{
        .prefers_dedicated_allocation = vk.FALSE,
        .requires_dedicated_allocation = vk.FALSE,
    };

    var memory_requirements: vk.MemoryRequirements2 = .{
        .p_next = &dedicated_requirements,
        .memory_requirements = undefined,
    };

    Context.self.vkd.getBufferMemoryRequirements2(Context.self.device, &vk.BufferMemoryRequirementsInfo2{
        .buffer = buffer,
    }, &memory_requirements);

    const memory_type = try getMemoryType(memory_requirements.memory_requirements, properties);

    const memory = try deviceAllocateWithMemoryType(
        memory_requirements.memory_requirements.size,
        memory_type,
        null,
    );
    errdefer deviceFree(memory);

    try self.vkd.bindBufferMemory(self.device, buffer, memory, 0);

    return .{
        .memory = memory,
    };
}

pub fn deviceMapBuffer(page: BufferMemory, comptime T: type, length: usize) ![]T {
    const data = @as(?[*]T, @ptrCast(@alignCast(try Context.self.vkd.mapMemory(Context.self.device, page.memory, 0, length * @sizeOf(T), .{}))));

    return data.?[0..length];
}

///Allocates a page dedicated to the specified image resource
pub fn devicePageAllocateImage(image: vk.Image, properties: vk.MemoryPropertyFlags) !DevicePageHandle {
    var dedicated_requirements: vk.MemoryDedicatedRequirements = .{
        .prefers_dedicated_allocation = vk.FALSE,
        .requires_dedicated_allocation = vk.FALSE,
    };

    var memory_requirements: vk.MemoryRequirements2 = .{
        .p_next = &dedicated_requirements,
        .memory_requirements = undefined,
    };

    Context.self.vkd.getImageMemoryRequirements2(Context.self.device, &vk.ImageMemoryRequirementsInfo2{
        .image = image,
    }, &memory_requirements);

    const page = try Context.devicePageAllocate(memory_requirements.memory_requirements.size, memory_requirements.memory_requirements.alignment, memory_requirements.memory_requirements.memory_type_bits, properties, if (dedicated_requirements.prefers_dedicated_allocation == vk.TRUE or
        dedicated_requirements.requires_dedicated_allocation == vk.TRUE)
        .{
            .image = image,
            .buffer = .null_handle,
        }
    else
        null);
    errdefer Context.devicePageFree(page);

    try devicePageBindToImage(image, page, 0);

    return page;
}

pub fn getPipelineCacheData() ![]const u8 {
    var data: []u8 = undefined;

    _ = try self.vkd.getPipelineCacheData(self.device, self.pipeline_cache, &data.len, null);

    data = try self.gpa.alloc(u8, data.len);

    _ = try self.vkd.getPipelineCacheData(self.device, self.pipeline_cache, &data.len, @as(*anyopaque, @ptrCast(data.ptr)));

    return data;
}

///Wait for the graphics device to complete all workloads
pub fn waitIdle() void {
    self.vkd.deviceWaitIdle(self.device) catch unreachable;
}

test {
    _ = std.testing.refAllDecls(@This());
}

const Context = @This();
const builtin = @import("builtin");
const std = @import("std");
const vk = @import("vulkan");
const windowing = @import("../windowing.zig");
const Window = windowing.Window;
const log = @import("../log.zig").log;
const WindowSurface = @import("WindowSurface.zig");
const quanta_options = @import("../root.zig").quanta_options;
