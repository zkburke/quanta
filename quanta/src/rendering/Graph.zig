//!Render Graph implementation built on top of quanta.graphics

pub fn init() Graph {
    return undefined;
}

pub fn deinit(self: *Graph) void {
    self.* = undefined;
}

///Graph builder for compiling a graph
///Works like an immediate-mode-gui-type api
pub const Builder = struct {
    allocator: std.mem.Allocator,
    scratch_allocator: std.heap.ArenaAllocator,
    ///List of created resources
    raster_pipelines: std.MultiArrayList(struct {
        handle: RasterPipeline,
        ///Number of times the pipeline was referenced in the graph
        reference_count: u32,

        vertex_module: RasterModule,
        fragment_module: RasterModule,
        push_constant_size: u32,
        attachment_formats: []const ImageFormat,
    }),
    buffers: std.MultiArrayList(struct {
        handle: Buffer,
        reference_count: u32,

        //The static, inital size for this buffer
        //TODO: make this a dynamic size?
        size: usize,
    }),
    ///Need to handle imported images
    images: std.MultiArrayList(struct {
        handle: ImageUntyped,
        reference_count: u32,
        layout: ImageLayout,
        format: ImageFormat,
        width: u32,
        height: u32,
        depth: u32,
    }) = .{},
    ///List of top level passes (not render passes)
    passes: std.MultiArrayList(struct {
        handle: u64,
        reference_count: u32,
        tag: PassTag,
        //Ordered Command list
        command_offset: u32,
        command_count: u32,
        input_offset: u32,
        //Could we make these counts u8? (max 255 inputs/outputs)
        input_count: u16,
        output_offset: u32,
        output_count: u16,

        //For raster pass
        //TODO: store passes of different types in different arrays?
        render_offset_x: i32,
        render_offset_y: i32,
        render_width: u32,
        render_height: u32,
        attachments: []const RasterAttachment,
    }),
    pass_inputs: std.MultiArrayList(struct {
        //What pass is this from, if any
        pass_index: ?u32,
        //The number of times this input was referenced (for culling)
        reference_count: u32,
        resource_type: ResourceType,
        resource_handle: ResourceHandle,
        ///layout if any
        layout: ImageLayout,
        //Represents any transformations that were applied during the pass that this comes from
        transform: InputOutputTransform,
    }) = .{},
    pass_outputs: std.MultiArrayList(struct {
        //What pass is this from. All outputs come from passes
        //TODO: make this a pass id rather than index
        pass_index: u32,
        reference_count: u32,
        resource_type: ResourceType,
        resource_handle: ResourceHandle,
        layout: ImageLayout,
        //Represents any transformations that were applied during the pass
        transform: InputOutputTransform,
    }) = .{},
    ///Ordered list of commands
    commands: std.MultiArrayList(Command),
    ///TODO: is this too cumbersome/unoptimal?
    update_buffer_commands: std.ArrayListUnmanaged(Command.UpdateBuffer) = .{},
    set_pipeline_commands: std.ArrayListUnmanaged(Command.SetRasterPipeline) = .{},
    set_raster_pipeline_resource_buffer_commands: std.ArrayListUnmanaged(Command.SetRasterPipelineResourceBuffer) = .{},
    set_viewport_commands: std.ArrayListUnmanaged(Command.SetViewport) = .{},
    set_scissor_commands: std.ArrayListUnmanaged(Command.SetScissor) = .{},
    set_index_buffer_commands: std.ArrayListUnmanaged(Command.SetIndexBuffer) = .{},
    set_push_data_commands: std.ArrayListUnmanaged(Command.SetPushData) = .{},
    draw_indexed_commands: std.ArrayListUnmanaged(Command.DrawIndexed) = .{},

    ///TODO: Handle nested passes?
    current_pass_index: u32,

    ///Represents a transformation (potential mutation) applied to a resource
    ///When all flags are set to zero, it represents a nop (no writes applied)
    pub const InputOutputTransform = packed struct(u16) {
        shader_write: bool,
        transfer_write: bool,
        padding: u14 = 0,

        pub const no_op = InputOutputTransform{
            .shader_write = false,
            .transfer_write = false,
        };
    };

    pub const PassTag = enum {
        transfer,
        raster,
    };

    ///High level command as part of a pass
    pub const Command = struct {
        index: u32,
        tag: Tag,

        pub const Tag = enum {
            update_buffer,
            set_raster_pipeline,
            set_raster_pipeline_resource_buffer,
            set_viewport,
            set_scissor,
            set_index_buffer,
            set_push_data,
            draw_indexed,
        };

        pub const UpdateBuffer = struct {
            buffer: Buffer,
            buffer_offset: usize,
            contents: []const u8,
        };

        pub const SetRasterPipeline = struct {
            pipeline: RasterPipeline,
        };

        pub const SetRasterPipelineResourceBuffer = struct {
            pipeline: RasterPipeline,
            binding_index: u32,
            array_index: u32,
            buffer: Buffer,
        };

        pub const SetViewport = struct {
            x: f32,
            y: f32,
            width: f32,
            height: f32,
            min_depth: f32,
            max_depth: f32,
        };

        pub const SetScissor = struct {
            x: u32,
            y: u32,
            width: u32,
            height: u32,
        };

        pub const SetIndexBuffer = struct {
            index_buffer: Buffer,
            type: IndexType,
        };

        pub const SetPushData = struct {
            contents: []const u8,
        };

        pub const DrawIndexed = struct {
            index_count: u32,
            instance_count: u32,
            first_index: u32,
            vertex_offset: i32,
            first_instance: u32,
        };
    };

    ///Compile time constant to include debug information into each graph builder
    ///Includes source locations for each
    pub const include_debug_info = false;

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .scratch_allocator = std.heap.ArenaAllocator.init(allocator),
            .raster_pipelines = .{},
            .buffers = .{},
            .passes = .{},
            .commands = .{},
            .update_buffer_commands = .{},
            .current_pass_index = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.raster_pipelines.deinit(self.allocator);
        self.buffers.deinit(self.allocator);
        self.images.deinit(self.allocator);

        self.passes.deinit(self.allocator);
        self.pass_inputs.deinit(self.allocator);
        self.pass_outputs.deinit(self.allocator);

        self.commands.deinit(self.allocator);

        self.update_buffer_commands.deinit(self.allocator);
        self.set_pipeline_commands.deinit(self.allocator);
        self.set_raster_pipeline_resource_buffer_commands.deinit(self.allocator);
        self.set_viewport_commands.deinit(self.allocator);
        self.set_scissor_commands.deinit(self.allocator);
        self.set_index_buffer_commands.deinit(self.allocator);
        self.set_push_data_commands.deinit(self.allocator);
        self.draw_indexed_commands.deinit(self.allocator);
        self.scratch_allocator.deinit();

        self.* = undefined;
    }

    ///Clear the graph to its default state. Allows for graph reuse for dynamically building graphs.
    pub fn clear(self: *@This()) void {
        self.raster_pipelines.len = 0;
        self.buffers.len = 0;
        self.images.len = 0;
        self.passes.len = 0;
        self.pass_inputs.len = 0;
        self.pass_outputs.len = 0;
        self.commands.len = 0;
        self.set_pipeline_commands.items.len = 0;
        self.set_raster_pipeline_resource_buffer_commands.items.len = 0;
        self.update_buffer_commands.items.len = 0;
        self.set_viewport_commands.items.len = 0;
        self.set_scissor_commands.items.len = 0;
        self.set_index_buffer_commands.items.len = 0;
        self.set_push_data_commands.items.len = 0;
        self.draw_indexed_commands.items.len = 0;
        self.current_pass_index = 0;

        _ = self.scratch_allocator.reset(std.heap.ArenaAllocator.ResetMode{ .retain_capacity = {} });

        std.debug.assert(self.passes.len == 0);
    }

    const CreateRasterPipelineOptions = struct {
        attachment_formats: []const ImageFormat,
    };

    ///Resource creation
    ///Can be created outside or inside a pass
    pub fn createRasterPipeline(
        self: *@This(),
        comptime src: SourceLocation,
        vertex_module: RasterModule,
        fragment_module: RasterModule,
        options: CreateRasterPipelineOptions,
        push_constant_size: usize,
    ) RasterPipeline {
        const handle_id = comptime idFromSourceLocation(src);

        const handle: RasterPipeline = .{
            .id = handle_id,
        };

        self.raster_pipelines.append(self.allocator, .{
            .handle = handle,
            .vertex_module = vertex_module,
            .fragment_module = fragment_module,
            .reference_count = 0,
            .push_constant_size = @intCast(push_constant_size),
            .attachment_formats = self.scratch_allocator.allocator().dupe(ImageFormat, options.attachment_formats) catch unreachable,
        }) catch unreachable;

        return handle;
    }

    pub fn createComputePipeline(
        self: *@This(),
        comptime src: SourceLocation,
    ) ComputePipeline {
        _ = self; // autofix
        _ = src; // autofix

        @compileError("Not yet implemented");
    }

    ///Create a buffer with a fixed size
    pub fn createBuffer(
        self: *@This(),
        comptime src: SourceLocation,
        size: usize,
    ) Buffer {
        const handle_id = comptime idFromSourceLocation(src);

        const handle: Buffer = .{
            .id = handle_id,
        };

        self.buffers.append(self.allocator, .{
            .handle = handle,
            .size = size,
            .reference_count = 0,
        }) catch unreachable;

        return handle;
    }

    pub fn createImage(
        self: *@This(),
        comptime src: SourceLocation,
        comptime layout: ImageLayout,
        format: ImageFormat,
        width: u32,
        height: u32,
        depth: u32,
    ) Image(layout) {
        const handle_id = comptime idFromSourceLocation(src);

        const handle: Image(layout) = .{
            .id = handle_id,
        };

        self.images.append(self.allocator, .{
            .handle = .{ .id = handle_id },
            .layout = layout,
            .format = format,
            .reference_count = 0,
            .width = width,
            .height = height,
            .depth = depth,
        }) catch unreachable;

        return handle;
    }

    pub fn imageGetWidth(
        self: *@This(),
        image: anytype,
    ) u32 {
        const index = self.referenceResource(image);

        return self.images.items(.width)[index];
    }

    pub fn imageGetHeight(
        self: *@This(),
        image: anytype,
    ) u32 {
        const index = self.referenceResource(image);

        return self.images.items(.height)[index];
    }

    pub fn imageGetDepth(
        self: *@This(),
        image: anytype,
    ) u32 {
        const index = self.referenceResource(image);

        return self.images.items(.depth)[index];
    }

    pub fn imageGetFormat(
        self: *@This(),
        image: anytype,
    ) ImageFormat {
        const index = self.referenceResource(image);

        return self.images.items(.format)[index];
    }

    pub fn createSampler(
        self: *@This(),
        comptime src: SourceLocation,
    ) Sampler {
        _ = self; // autofix
        _ = src; // autofix

        @compileError("Unimplemented");
    }

    pub fn InputType(comptime InputTuple: type) type {
        var fields: [std.meta.fields(InputTuple).len]std.builtin.Type.StructField = undefined;

        inline for (std.meta.fields(InputTuple), 0..) |tuple_field, index| {
            var field_type: type = undefined;

            switch (tuple_field.type) {
                Buffer => {
                    field_type = PassInput(Buffer);
                },
                else => {
                    if (@hasDecl(tuple_field.type, "pass_input")) {
                        field_type = tuple_field.type;
                    } else if (@hasDecl(tuple_field.type, "pass_output")) {
                        field_type = PassInput(tuple_field.type.ResourceType);
                    } else {
                        @compileError("Input Type not supported");
                    }
                },
            }

            fields[index] = .{
                .name = tuple_field.name,
                .type = field_type,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(field_type),
            };
        }

        return @Type(.{
            .Struct = std.builtin.Type.Struct{
                .layout = .Auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    }

    fn parseInputs(self: *@This(), inputs: anytype) InputType(@TypeOf(inputs)) {
        var result: InputType(@TypeOf(inputs)) = undefined;

        inline for (std.meta.fields(@TypeOf(inputs))) |input| {
            const T = input.type;

            const field = @field(inputs, input.name);

            const input_index: u32 = @intCast(self.pass_inputs.len);

            switch (T) {
                Buffer => {
                    self.pass_inputs.append(self.allocator, .{
                        .pass_index = null,
                        .reference_count = 0,
                        .resource_type = .buffer,
                        .resource_handle = .{ .id = field.id },
                        .layout = .general,
                        .transform = InputOutputTransform.no_op,
                    }) catch unreachable;

                    @field(result, input.name) = PassInput(Buffer){
                        .index = input_index,
                        .resource = field,
                    };
                },
                Image(.general), Image(.attachment) => @compileError(""),
                else => {
                    if (@hasDecl(input.type, "pass_input")) {
                        @field(result, input.name) = @field(inputs, input.name);
                    } else if (@hasDecl(input.type, "pass_output")) {
                        self.referencePassOutput(field);

                        self.pass_inputs.append(self.allocator, .{
                            .pass_index = self.pass_outputs.items(.pass_index)[field.index],
                            .reference_count = 0,
                            .resource_type = .buffer,
                            .resource_handle = .{ .id = field.resource.id },
                            .layout = .general,
                            .transform = InputOutputTransform.no_op,
                        }) catch unreachable;

                        @field(result, input.name) = PassInput(input.type.ResourceType){
                            .index = input_index,
                            .resource = field.resource,
                        };
                    } else {
                        @compileError("Input Type not supported");
                    }
                },
            }
        }

        return result;
    }

    pub fn OutputType(comptime OutputTuple: type) type {
        var fields: [std.meta.fields(OutputTuple).len]std.builtin.Type.StructField = undefined;

        inline for (std.meta.fields(OutputTuple), 0..) |tuple_field, index| {
            var field_type: type = undefined;

            switch (tuple_field.type) {
                else => {
                    if (@hasDecl(tuple_field.type, "pass_output")) {
                        field_type = tuple_field.type;
                    } else if (@hasDecl(tuple_field.type, "pass_input")) {
                        field_type = PassOutput(tuple_field.type.ResourceType);
                    } else {
                        @compileError("Input Type not supported");
                    }
                },
            }

            fields[index] = .{
                .name = tuple_field.name,
                .type = field_type,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(field_type),
            };
        }

        return @Type(.{
            .Struct = std.builtin.Type.Struct{
                .layout = .Auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    }

    fn parseOutputs(self: *@This(), outputs: anytype) OutputType(@TypeOf(outputs)) {
        var result: OutputType(@TypeOf(outputs)) = undefined;

        inline for (std.meta.fields(@TypeOf(outputs))) |output| {
            const T = output.type;

            const field = @field(outputs, output.name);

            const output_index: u32 = @intCast(self.pass_outputs.len);

            switch (T) {
                else => {
                    if (@hasDecl(output.type, "pass_output")) {
                        //Output passthrough
                        @field(result, output.name) = @field(outputs, output.name);
                    } else if (@hasDecl(output.type, "pass_input")) {
                        self.pass_outputs.append(self.allocator, .{
                            .pass_index = self.current_pass_index,
                            .reference_count = 0,
                            .resource_type = .buffer,
                            .resource_handle = .{ .id = field.resource.id },
                            .layout = .general,
                            .transform = InputOutputTransform.no_op,
                        }) catch unreachable;

                        @field(result, output.name) = PassOutput(Buffer){
                            .index = output_index,
                            .resource = field.resource,
                        };
                    } else {
                        @compileError("Input Type not supported");
                    }
                },
            }
        }

        return result;
    }

    fn referencePassInput(self: *@This(), pass_input: anytype) void {
        self.pass_inputs.items(.reference_count)[pass_input.index] += 1;

        _ = self.referenceResource(pass_input.resource);
    }

    fn referencePassOutput(self: *@This(), pass_output: anytype) void {
        self.pass_outputs.items(.reference_count)[pass_output.index] += 1;

        _ = self.referenceResource(pass_output.resource);
    }

    ///Begins a pass for transferring, copying and updating resources
    pub fn beginTransferPass(
        self: *@This(),
        ///Uniquely identifies the pass
        comptime src: SourceLocation,
        ///The input dependencies for the pass
        inputs: anytype,
    ) InputType(@TypeOf(inputs)) {
        const pass_id = comptime idFromSourceLocation(src);

        self.current_pass_index = @intCast(self.passes.len);

        self.passes.append(self.allocator, .{
            .handle = pass_id,
            .reference_count = 0,
            .command_offset = @intCast(self.commands.len),
            .command_count = 0,
            .tag = .transfer,
            .input_offset = @intCast(self.pass_inputs.len),
            .input_count = std.meta.fields(@TypeOf(inputs)).len,
            .output_offset = @intCast(self.pass_outputs.len),
            .output_count = 0,
            .render_offset_x = 0,
            .render_offset_y = 0,
            .render_width = 1,
            .render_height = 1,
            .attachments = &.{},
        }) catch unreachable;

        return self.parseInputs(inputs);
    }

    pub fn endTransferPass(
        self: *@This(),
        outputs: anytype,
    ) OutputType(@TypeOf(outputs)) {
        const output_result = self.parseOutputs(outputs);

        const command_count = self.commands.len - self.passes.items(.command_offset)[self.current_pass_index];
        const output_count = self.pass_outputs.len - self.passes.items(.output_offset)[self.current_pass_index];

        self.passes.items(.command_count)[self.current_pass_index] = @intCast(command_count);
        self.passes.items(.output_count)[self.current_pass_index] = @intCast(output_count);

        return output_result;
    }

    ///Update the buffer with contents.
    ///Must be in a pass.
    ///Returns the modified buffer.
    pub fn updateBuffer(
        self: *@This(),
        buffer: PassInput(Buffer),
        ///The offset into buffer from which contents are written
        buffer_offset: usize,
        comptime T: type,
        contents: []const T,
    ) void {
        self.referencePassInput(buffer);

        self.commands.append(self.allocator, .{
            .tag = .update_buffer,
            .index = @intCast(self.update_buffer_commands.items.len),
        }) catch unreachable;

        self.update_buffer_commands.append(self.allocator, .{
            .buffer = buffer.resource,
            .buffer_offset = buffer_offset,
            .contents = std.mem.sliceAsBytes(contents),
        }) catch unreachable;
    }

    pub const RasterAttachment = struct {
        image: Image(.attachment),
        clear: ?Clear = null,
        ///TODO: determine this at graph compile
        store: bool = true,

        pub const Clear = union(enum) {
            color: [4]f32,
            depth: f32,
        };
    };

    pub fn beginRasterPass(
        self: *@This(),
        ///Uniquely identifies the pass
        comptime src: SourceLocation,
        attachments: []const RasterAttachment,
        offset_x: i32,
        offset_y: i32,
        width: u32,
        height: u32,
        ///The input dependencies for the pass
        inputs: anytype,
    ) InputType(@TypeOf(inputs)) {
        const pass_id = comptime idFromSourceLocation(src);

        self.current_pass_index = @intCast(self.passes.len);

        const attachments_allocated = self.scratch_allocator.allocator().dupe(RasterAttachment, attachments) catch unreachable;

        self.passes.append(self.allocator, .{
            .handle = pass_id,
            .reference_count = 0,
            .command_offset = @intCast(self.commands.len),
            .command_count = 0,
            .tag = .raster,
            .input_offset = @intCast(self.pass_inputs.len),
            .input_count = std.meta.fields(@TypeOf(inputs)).len,
            .output_offset = @intCast(self.pass_outputs.len),
            .output_count = 0,
            .attachments = attachments_allocated,
            .render_offset_x = offset_x,
            .render_offset_y = offset_y,
            .render_width = width,
            .render_height = height,
        }) catch unreachable;

        return self.parseInputs(inputs);
    }

    pub fn endRasterPass(
        self: *@This(),
        outputs: anytype,
    ) @TypeOf(outputs) {
        const command_count = self.commands.len - self.passes.items(.command_offset)[self.current_pass_index];

        self.passes.items(.command_count)[self.current_pass_index] = @intCast(command_count);

        return outputs;
    }

    pub fn setRasterPipeline(
        self: *@This(),
        pipeline: RasterPipeline,
    ) void {
        const pipeline_index = self.referenceRasterPipeline(pipeline);
        _ = pipeline_index; // autofix

        self.commands.append(self.allocator, .{
            .tag = .set_raster_pipeline,
            .index = @intCast(self.set_pipeline_commands.items.len),
        }) catch unreachable;

        self.set_pipeline_commands.append(self.allocator, .{
            .pipeline = pipeline,
        }) catch unreachable;
    }

    pub fn setPushData(
        self: *@This(),
        comptime T: type,
        data: T,
    ) void {
        self.commands.append(self.allocator, .{
            .tag = .set_push_data,
            .index = @intCast(self.set_push_data_commands.items.len),
        }) catch unreachable;

        self.set_push_data_commands.append(self.allocator, .{
            .contents = self.scratch_allocator.allocator().dupe(u8, std.mem.asBytes(&data)) catch unreachable,
        }) catch unreachable;
    }

    ///Dynamically set a resource binding in a shader interface
    pub fn setRasterPipelineResourceBuffer(
        self: *@This(),
        pipeline: RasterPipeline,
        binding_index: u32,
        array_index: u32,
        buffer: PassInput(Buffer),
    ) void {
        self.referencePassInput(buffer);

        self.commands.append(self.allocator, .{
            .tag = .set_raster_pipeline_resource_buffer,
            .index = @intCast(self.set_raster_pipeline_resource_buffer_commands.items.len),
        }) catch unreachable;

        self.set_raster_pipeline_resource_buffer_commands.append(self.allocator, .{
            .pipeline = pipeline,
            .binding_index = binding_index,
            .array_index = array_index,
            .buffer = buffer.resource,
        }) catch unreachable;
    }

    pub fn setViewport(
        self: *@This(),
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        min_depth: f32,
        max_depth: f32,
    ) void {
        self.commands.append(self.allocator, .{
            .tag = .set_viewport,
            .index = @intCast(self.set_viewport_commands.items.len),
        }) catch unreachable;

        self.set_viewport_commands.append(self.allocator, .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .min_depth = min_depth,
            .max_depth = max_depth,
        }) catch unreachable;
    }

    pub fn setScissor(
        self: *@This(),
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    ) void {
        self.commands.append(self.allocator, .{
            .tag = .set_scissor,
            .index = @intCast(self.set_scissor_commands.items.len),
        }) catch unreachable;

        self.set_scissor_commands.append(self.allocator, .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        }) catch unreachable;
    }

    pub const IndexType = enum {
        u16,
        u32,
    };

    pub fn setIndexBuffer(
        self: *@This(),
        buffer: PassInput(Buffer),
        index_type: IndexType,
    ) void {
        self.referencePassInput(buffer);

        self.commands.append(self.allocator, .{
            .tag = .set_index_buffer,
            .index = @intCast(self.set_index_buffer_commands.items.len),
        }) catch unreachable;

        self.set_index_buffer_commands.append(self.allocator, .{
            .index_buffer = buffer.resource,
            .type = index_type,
        }) catch unreachable;
    }

    pub fn drawIndexed(
        self: *@This(),
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        self.commands.append(self.allocator, .{
            .tag = .draw_indexed,
            .index = @intCast(self.draw_indexed_commands.items.len),
        }) catch unreachable;

        self.draw_indexed_commands.append(self.allocator, .{
            .index_count = index_count,
            .instance_count = instance_count,
            .first_index = first_index,
            .vertex_offset = vertex_offset,
            .first_instance = first_instance,
        }) catch unreachable;
    }

    ///Incrementes the refence count for buffer and resolves the buffer index
    pub fn referenceBuffer(self: *@This(), buffer: Buffer) usize {
        return self.referenceResource(buffer);
    }

    ///Incrementes the refence count for buffer and resolves the buffer index
    pub fn referenceRasterPipeline(self: *@This(), pipeline: RasterPipeline) usize {
        return self.referenceResource(pipeline);
    }

    ///Incrementes the refence count for buffer and resolves the resource index
    fn referenceResource(self: *@This(), resource: anytype) usize {
        const resources = switch (@TypeOf(resource)) {
            RasterPipeline => &self.raster_pipelines,
            Buffer => &self.buffers,
            Image(.general), Image(.attachment) => &self.images,
            else => @compileError("Resource Type not yet supported"),
        };

        const handles = resources.items(.handle);

        //TODO: implement more scalable way to search for buffers (bin into buckets?)
        for (handles, 0..) |handle, buffer_index| {
            if (handle.id == resource.id) {
                resources.items(.reference_count)[buffer_index] += 1;

                return buffer_index;
            }
        }

        @panic("Invalid resource handle");
    }

    ///Returns a unique id (for resources and passes) based on source location
    ///By definition going to be unique for each call to a function assuming correct use of @src()
    fn idFromSourceLocation(src: SourceLocation) u64 {
        @setEvalBranchQuota(10000);

        var hasher = std.hash.SipHash64(2, 4).init("ID" ** 8);

        std.hash.autoHashStrat(&hasher, src, std.hash.Strategy.Deep);

        // return hashSourceLocation({}, src);

        return hasher.finalInt();
    }

    pub const SourceLocation = std.builtin.SourceLocation;
};

///Contains all graphics resources (pipelines, buffers, textures ect..)
pub const CompileContext = struct {
    allocator: std.mem.Allocator,
    ///TODO: better way to do this?
    double_buffer: [2]struct {
        graphics_command_buffer: ?graphics.CommandBuffer = null,

        //global staging buffer pool
        staging_buffer: ?graphics.Buffer = null,
        staging_buffer_size: usize = 0,
        staging_buffer_offset: usize = 0,
        staging_buffer_mapping: [*]u8 = undefined,
    } = .{ .{}, .{} },
    buffer_index: u32 = 0,

    //TODO: exploit SourceLocation to make a more efficient mapping
    raster_pipelines: std.AutoArrayHashMapUnmanaged(u64, graphics.GraphicsPipeline) = .{},
    buffers: std.AutoArrayHashMapUnmanaged(u64, graphics.Buffer) = .{},
    images: std.AutoArrayHashMapUnmanaged(u64, struct {
        imported: bool = false,
        //TODO: use pointer for external image maybe?
        image: graphics.Image,
    }) = .{},

    pub fn init(allocator: std.mem.Allocator) CompileContext {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.raster_pipelines.values()) |*raster_pipeline| {
            raster_pipeline.deinit(self.allocator);
        }

        for (self.buffers.values()) |*buffer| {
            buffer.deinit();
        }

        for (self.images.values()) |*image| {
            if (!image.imported) {
                image.image.deinit();
            }
        }

        for (&self.double_buffer) |*buffer| {
            if (buffer.graphics_command_buffer != null) buffer.graphics_command_buffer.?.deinit();

            if (buffer.staging_buffer != null) {
                buffer.staging_buffer.?.deinit();
            }
        }

        self.raster_pipelines.deinit(self.allocator);
        self.buffers.deinit(self.allocator);
        self.images.deinit(self.allocator);

        self.* = undefined;
    }

    ///Imports and underlying gpu api image and provides a handle that is usable from graph building code
    pub fn importExternalImage(
        self: *@This(),
        builder: *Builder,
        comptime src: std.builtin.SourceLocation,
        image: graphics.Image,
        comptime layout: ImageLayout,
    ) Image(layout) {
        const handle = builder.createImage(
            src,
            layout,
            @enumFromInt(@intFromEnum(image.format)),
            image.width,
            image.height,
            1,
        );

        const get_or_put_result = self.images.getOrPut(self.allocator, handle.id) catch unreachable;

        get_or_put_result.value_ptr.image = image;
        get_or_put_result.value_ptr.imported = true;

        return handle;
    }

    ///Compiles a built graph to low level api commands
    pub fn compile(
        self: *@This(),
        builder: Builder,
    ) !CompileResult {
        defer {
            self.buffer_index = if (self.buffer_index != 0) 1 else 0;
        }

        const compile_buffer = &self.double_buffer[self.buffer_index];

        compile_buffer.staging_buffer_offset = 0;
        compile_buffer.staging_buffer_size = 0;

        if (compile_buffer.graphics_command_buffer == null) {
            compile_buffer.graphics_command_buffer = try graphics.CommandBuffer.init(.graphics);
        }

        //GPU Resource creation/fetching/allocation/deallocation/destruction pass
        {
            const raster_pipeline_reference_counts = builder.raster_pipelines.items(.reference_count);

            for (raster_pipeline_reference_counts, 0..) |reference_count, pipeline_index| {
                if (reference_count == 0) {
                    //TODO: deallocate unreferenced pipelines if they have a backing store
                    continue;
                }

                const handle: RasterPipeline = builder.raster_pipelines.items(.handle)[pipeline_index];

                const get_or_put_res = try self.raster_pipelines.getOrPut(self.allocator, handle.id);

                //cache hit
                if (get_or_put_res.found_existing) {
                    continue;
                }

                const vertex_module: RasterModule = builder.raster_pipelines.items(.vertex_module)[pipeline_index];
                const fragment_module: RasterModule = builder.raster_pipelines.items(.fragment_module)[pipeline_index];
                const push_constant_size = builder.raster_pipelines.items(.push_constant_size)[pipeline_index];
                const attachment_formats = builder.raster_pipelines.items(.attachment_formats)[pipeline_index];

                //otherwise create the pipeline
                get_or_put_res.value_ptr.* = try graphics.GraphicsPipeline.init(
                    self.allocator,
                    .{
                        .color_attachment_formats = @as([*]const graphics.vulkan.Format, @alignCast(@ptrCast(attachment_formats.ptr)))[0..attachment_formats.len],
                        .vertex_shader_binary = @alignCast(vertex_module.code),
                        .fragment_shader_binary = @alignCast(fragment_module.code),
                        .depth_state = .{
                            .write_enabled = false,
                            .test_enabled = false,
                            .compare_op = .greater,
                        },
                        .rasterisation_state = .{
                            .polygon_mode = .fill,
                        },
                        .blend_state = .{
                            .blend_enabled = true,
                        },
                    },
                    //TODO: handle vertex layouts (if anyone's using that in 2024)
                    null,
                    //TODO: runtime push constants
                    push_constant_size,
                );
                errdefer get_or_put_res.value_ptr.deinit(self.allocator);
            }

            for (builder.buffers.items(.reference_count), 0..) |reference_count, buffer_index| {
                if (reference_count == 0) {
                    //TODO: deallocate unreferenced pipelines if they have a backing store
                    continue;
                }

                const handle: Buffer = builder.buffers.items(.handle)[buffer_index];

                const get_or_put_res = try self.buffers.getOrPut(self.allocator, handle.id);

                //cache hit
                if (get_or_put_res.found_existing) {
                    continue;
                }

                const buffer_size = builder.buffers.items(.size)[buffer_index];

                //TODO: aggregate global usage of each buffer
                get_or_put_res.value_ptr.* = try graphics.Buffer.init(buffer_size, .index);
                errdefer get_or_put_res.value_ptr.deinit();
            }
        }

        //ordered list of dependencies for the root pass
        var dependencies: std.ArrayListUnmanaged(Dependency) = .{};
        defer dependencies.deinit(self.allocator);

        //Second pass: pass dependency analysis
        {
            //The first pass to evaluate. Evaluation goes bottom up (from last executed to first)
            const root_pass_index: u32 = @intCast(builder.passes.len - 1);

            try self.compilePassDependencies(
                builder,
                root_pass_index,
                &dependencies,
            );
        }

        //Staging memory allocate pass
        {
            for (dependencies.items) |*dependency| {
                if (dependency.generated_commands) continue;

                const pass_index = dependency.pass_index;

                const command_offset = builder.passes.items(.command_offset)[pass_index];
                const command_count = builder.passes.items(.command_count)[pass_index];

                for (0..command_count) |command_index| {
                    const command_tag = builder.commands.items(.tag)[command_offset + command_index];
                    const command_data_index = builder.commands.items(.index)[command_offset + command_index];

                    switch (command_tag) {
                        .update_buffer => {
                            const update_buffer = builder.update_buffer_commands.items[command_data_index];

                            //TODO: move this to staging resource allocation?
                            self.preAllocateStagingMemory(update_buffer.contents.len);
                        },
                        else => {},
                    }
                }
            }
        }

        //Final pass: Encode commands
        {
            const command_buffer = &compile_buffer.graphics_command_buffer.?;

            try command_buffer.begin();
            // defer command_buffer.end();

            //add to this if you write to a resource, or read from one
            var buffer_barrier_map: std.AutoHashMapUnmanaged(*const graphics.Buffer, graphics.CommandBuffer.BufferBarrier) = .{};
            defer buffer_barrier_map.deinit(self.allocator);

            for (dependencies.items) |*dependency| {
                if (dependency.generated_commands) continue;
                defer dependency.generated_commands = true;

                const pass_index = dependency.pass_index;

                const command_offset = builder.passes.items(.command_offset)[pass_index];
                const command_count = builder.passes.items(.command_count)[pass_index];
                const pass_tag = builder.passes.items(.tag)[pass_index];

                var current_pipline: ?*graphics.GraphicsPipeline = null;
                var current_index_buffer: ?*graphics.Buffer = null;

                var pass_buffer_barriers: std.ArrayListUnmanaged(struct {
                    buffer: *const graphics.Buffer,
                    barrier: graphics.CommandBuffer.BufferBarrier,
                }) = .{};
                defer pass_buffer_barriers.deinit(self.allocator);

                //barrier prepass
                for (0..command_count) |command_index| {
                    const command_tag = builder.commands.items(.tag)[command_offset + command_index];
                    const command_data_index = builder.commands.items(.index)[command_offset + command_index];

                    switch (command_tag) {
                        .update_buffer => {
                            const update_buffer = builder.update_buffer_commands.items[command_data_index];

                            const buffer = self.buffers.getPtr(update_buffer.buffer.id).?;

                            const barrier_result = try buffer_barrier_map.getOrPut(self.allocator, buffer);

                            if (!barrier_result.found_existing) {
                                barrier_result.value_ptr.source_stage = .{ .copy = true };
                                barrier_result.value_ptr.source_access = .{ .transfer_write = true };
                            }
                        },
                        .set_raster_pipeline_resource_buffer => {
                            const command_data = builder.set_raster_pipeline_resource_buffer_commands.items[command_data_index];

                            const buffer = self.buffers.getPtr(command_data.buffer.id).?;

                            const buffer_barrier = buffer_barrier_map.get(buffer);

                            if (buffer_barrier) |barrier| {
                                //emit the actual complete barrier
                                try pass_buffer_barriers.append(self.allocator, .{
                                    .buffer = buffer,
                                    .barrier = .{
                                        .source_access = barrier.source_access,
                                        .source_stage = barrier.source_stage,
                                        .destination_stage = .{
                                            .vertex_shader = true,
                                        },
                                        .destination_access = .{
                                            .shader_read = true,
                                        },
                                    },
                                });
                            }
                        },
                        .set_index_buffer => {
                            const command_data = builder.set_index_buffer_commands.items[command_data_index];

                            current_index_buffer = self.buffers.getPtr(command_data.index_buffer.id).?;
                        },
                        .draw_indexed => {
                            const command_data = builder.draw_indexed_commands.items[command_data_index];
                            _ = command_data; // autofix

                            const index_buffer_barrier = buffer_barrier_map.get(current_index_buffer.?);

                            if (index_buffer_barrier) |barrier| {
                                try pass_buffer_barriers.append(self.allocator, .{
                                    .buffer = current_index_buffer.?,
                                    .barrier = .{
                                        .source_access = barrier.source_access,
                                        .source_stage = barrier.source_stage,
                                        .destination_stage = .{ .index_input = true },
                                        .destination_access = .{ .index_read = true },
                                    },
                                });
                            }
                        },
                        else => {},
                    }
                }

                for (pass_buffer_barriers.items) |barrier| {
                    command_buffer.bufferBarrier(barrier.buffer.*, barrier.barrier);
                }

                if (pass_tag == .raster) {
                    const x = builder.passes.items(.render_offset_x)[pass_index];
                    const y = builder.passes.items(.render_offset_y)[pass_index];
                    const width = builder.passes.items(.render_width)[pass_index];
                    const height = builder.passes.items(.render_height)[pass_index];
                    const attachments_input = builder.passes.items(.attachments)[pass_index];

                    const attachments = try self.allocator.alloc(graphics.CommandBuffer.Attachment, attachments_input.len);
                    defer self.allocator.free(attachments);

                    for (attachments_input, attachments) |input, *output| {
                        output.image = &self.images.getPtr(input.image.id).?.image;
                        output.clear = null;
                        output.store = true;
                    }

                    command_buffer.beginRenderPass(
                        x,
                        y,
                        width,
                        height,
                        attachments,
                        null,
                    );
                }
                defer if (pass_tag == .raster) command_buffer.endRenderPass();

                current_pipline = null;
                current_index_buffer = null;

                for (0..command_count) |command_index| {
                    const command_tag = builder.commands.items(.tag)[command_offset + command_index];
                    const command_data_index = builder.commands.items(.index)[command_offset + command_index];

                    switch (command_tag) {
                        .update_buffer => {
                            const update_buffer = builder.update_buffer_commands.items[command_data_index];

                            const buffer = self.buffers.getPtr(update_buffer.buffer.id).?;

                            const staging_contents = try self.allocateStagingBuffer(update_buffer.contents.len);

                            @memcpy(staging_contents.mapped_region[0..staging_contents.size], update_buffer.contents);

                            command_buffer.copyBuffer(
                                staging_contents.buffer.*,
                                staging_contents.offset,
                                staging_contents.size,
                                buffer.*,
                                update_buffer.buffer_offset,
                                update_buffer.contents.len,
                            );
                        },
                        .set_raster_pipeline => {
                            const set_raster_pipeline = builder.set_pipeline_commands.items[command_data_index];

                            const pipeline = self.raster_pipelines.getPtr(set_raster_pipeline.pipeline.id).?;

                            command_buffer.setGraphicsPipeline(pipeline.*);

                            current_pipline = pipeline;
                        },
                        .set_raster_pipeline_resource_buffer => {
                            const command_data = builder.set_raster_pipeline_resource_buffer_commands.items[command_data_index];

                            const buffer = self.buffers.getPtr(command_data.buffer.id).?;

                            current_pipline.?.setDescriptorBuffer(
                                command_data.binding_index,
                                command_data.array_index,
                                buffer.*,
                            );
                        },
                        .set_viewport => {
                            const command_data = builder.set_viewport_commands.items[command_data_index];

                            command_buffer.setViewport(
                                command_data.x,
                                command_data.y,
                                command_data.width,
                                command_data.height,
                                command_data.min_depth,
                                command_data.max_depth,
                            );
                        },
                        .set_scissor => {
                            const command_data = builder.set_scissor_commands.items[command_data_index];

                            command_buffer.setScissor(
                                command_data.x,
                                command_data.y,
                                command_data.width,
                                command_data.height,
                            );
                        },
                        .set_index_buffer => {
                            const command_data = builder.set_index_buffer_commands.items[command_data_index];

                            current_index_buffer = self.buffers.getPtr(command_data.index_buffer.id).?;

                            command_buffer.setIndexBuffer(current_index_buffer.?.*, switch (command_data.type) {
                                .u16 => .u16,
                                .u32 => .u32,
                            });
                        },
                        .set_push_data => {
                            const command_data = builder.set_push_data_commands.items[command_data_index];

                            command_buffer.setPushDataBytes(command_data.contents);
                        },
                        .draw_indexed => {
                            const command_data = builder.draw_indexed_commands.items[command_data_index];

                            command_buffer.drawIndexed(
                                command_data.index_count,
                                command_data.instance_count,
                                command_data.first_index,
                                command_data.vertex_offset,
                                command_data.first_instance,
                            );
                        },
                    }
                }
            }
        }

        return .{
            .graphics_command_buffer = &compile_buffer.graphics_command_buffer.?,
        };
    }

    const Dependency = struct {
        pass_index: u32,
        reference_count: u32 = 0,
        ///Have the commands for this dependency already been compiled
        generated_commands: bool = false,
    };

    fn compilePassDependencies(
        self: *@This(),
        builder: Builder,
        pass_index: u32,
        dependencies: *std.ArrayListUnmanaged(Dependency),
    ) !void {
        const passes = &builder.passes;

        const input_offset = passes.items(.input_offset)[pass_index];
        const input_count = passes.items(.input_count)[pass_index];

        //TODO: use arena scratch buffer
        const pass_dependencies = try self.allocator.alloc(Dependency, input_count);
        defer self.allocator.free(pass_dependencies);

        var dependency_count: u32 = 0;

        for (0..input_count) |input_index| {
            const pass_if_any = builder.pass_inputs.items(.pass_index)[input_offset + input_index];
            const input_reference_count = builder.pass_inputs.items(.reference_count)[input_offset + input_index];

            if (pass_if_any) |pass_dependency_index| {
                if (input_reference_count != 0) {
                    const existing_index = block: for (pass_dependencies, 0..) |pass_dep, dependency_index| {
                        if (pass_dep.pass_index == pass_dependency_index) break :block dependency_index;
                    } else dependency_count;

                    const found_existing = existing_index != dependency_count;

                    if (found_existing) continue;

                    pass_dependencies[dependency_count] = .{
                        .reference_count = 1,
                        .pass_index = pass_dependency_index,
                    };

                    dependency_count += 1;
                }
            }
        }

        for (pass_dependencies[0..dependency_count]) |dep| {
            try self.compilePassDependencies(
                builder,
                dep.pass_index,
                dependencies,
            );
        } else {
            try dependencies.append(self.allocator, .{
                .reference_count = 1,
                .pass_index = pass_index,
            });
        }
    }

    fn preAllocateStagingMemory(self: *@This(), size: usize) void {
        const frame_data = &self.double_buffer[self.buffer_index];

        frame_data.staging_buffer_size += size;
    }

    const StagingBuffer = struct {
        buffer: *const graphics.Buffer,
        mapped_region: [*]u8,
        offset: usize,
        size: usize,
    };

    ///Allocate staging memory immediately to from a pool
    ///Will get returned to the pool when the command buffer is done
    fn allocateStagingBuffer(
        self: *@This(),
        size: usize,
    ) !StagingBuffer {
        const frame_data = &self.double_buffer[self.buffer_index];

        defer frame_data.staging_buffer_offset += size;

        if (frame_data.staging_buffer != null and frame_data.staging_buffer_size <= frame_data.staging_buffer.?.size) {
            return StagingBuffer{
                .buffer = &frame_data.staging_buffer.?,
                .mapped_region = frame_data.staging_buffer_mapping + frame_data.staging_buffer_offset,
                .offset = frame_data.staging_buffer_offset,
                .size = size,
            };
        }

        if (frame_data.staging_buffer != null) {
            frame_data.staging_buffer.?.deinit();
        }

        frame_data.staging_buffer = try graphics.Buffer.init(frame_data.staging_buffer_size, .staging);
        errdefer frame_data.staging_buffer.?.deinit();

        const mapped_region = try frame_data.staging_buffer.?.map(u8);

        frame_data.staging_buffer_mapping = mapped_region.ptr;

        return StagingBuffer{
            .buffer = &frame_data.staging_buffer.?,
            .mapped_region = frame_data.staging_buffer_mapping + frame_data.staging_buffer_offset,
            .offset = frame_data.staging_buffer_offset,
            .size = size,
        };
    }

    pub const CompileResult = struct {
        ///Command buffer to be submitted to graphics queue
        graphics_command_buffer: *const graphics.CommandBuffer,
    };

    const graphics = @import("../graphics.zig");
};

comptime {
    const input: PassInput(Image(.attachment)) = undefined;
    _ = input; // autofix
}

pub fn PassInput(comptime Resource: type) type {
    return struct {
        ///Input index
        index: u32,
        resource: Resource,

        pub const pass_input = Resource;
        pub const ResourceType = Resource;
    };
}

pub fn PassOutput(comptime Resource: type) type {
    return struct {
        ///Input index
        index: u32,
        resource: Resource,

        pub const pass_output = Resource;
        pub const ResourceType = Resource;
    };
}

pub const ResourceType = enum {
    buffer,
    image,
};

///Generic type erased resource handle
pub const ResourceHandle = packed struct(u64) {
    id: u64,
};

///TODO: provide specialisation constants
pub const RasterModule = struct {
    ///Graphics API specific code
    code: []align(4) const u8,
};

pub const RasterPipeline = struct {
    id: u64,
};

pub const ComputePipeline = struct {
    id: u64,
};

pub const Buffer = struct {
    id: u64,

    pub const resource_type = .buffer;
};

pub const ImageUntyped = struct {
    id: u64,

    pub const resource_type = .image;
};

pub const ImageLayout = enum {
    ///Use for attachment inputs and outputs
    attachment,
    ///Use for buffers and shader accessible things
    general,
};

///Strongly typed representation of an image with layout. Contains read/write semantics and layout semantics
pub fn Image(comptime layout: ImageLayout) type {
    _ = layout; // autofix
    return struct {
        id: u64,

        pub const resource_type = .image;
    };
}

pub const ImageFormat = enum(i32) {
    r4g4_unorm_pack8 = 1,
    r4g4b4a4_unorm_pack16 = 2,
    b4g4r4a4_unorm_pack16 = 3,
    r5g6b5_unorm_pack16 = 4,
    b5g6r5_unorm_pack16 = 5,
    r5g5b5a1_unorm_pack16 = 6,
    b5g5r5a1_unorm_pack16 = 7,
    a1r5g5b5_unorm_pack16 = 8,
    r8_unorm = 9,
    r8_snorm = 10,
    r8_uscaled = 11,
    r8_sscaled = 12,
    r8_uint = 13,
    r8_sint = 14,
    r8_srgb = 15,
    r8g8_unorm = 16,
    r8g8_snorm = 17,
    r8g8_uscaled = 18,
    r8g8_sscaled = 19,
    r8g8_uint = 20,
    r8g8_sint = 21,
    r8g8_srgb = 22,
    r8g8b8_unorm = 23,
    r8g8b8_snorm = 24,
    r8g8b8_uscaled = 25,
    r8g8b8_sscaled = 26,
    r8g8b8_uint = 27,
    r8g8b8_sint = 28,
    r8g8b8_srgb = 29,
    b8g8r8_unorm = 30,
    b8g8r8_snorm = 31,
    b8g8r8_uscaled = 32,
    b8g8r8_sscaled = 33,
    b8g8r8_uint = 34,
    b8g8r8_sint = 35,
    b8g8r8_srgb = 36,
    r8g8b8a8_unorm = 37,
    r8g8b8a8_snorm = 38,
    r8g8b8a8_uscaled = 39,
    r8g8b8a8_sscaled = 40,
    r8g8b8a8_uint = 41,
    r8g8b8a8_sint = 42,
    r8g8b8a8_srgb = 43,
    b8g8r8a8_unorm = 44,
    b8g8r8a8_snorm = 45,
    b8g8r8a8_uscaled = 46,
    b8g8r8a8_sscaled = 47,
    b8g8r8a8_uint = 48,
    b8g8r8a8_sint = 49,
    b8g8r8a8_srgb = 50,
};

pub fn imageLayoutCast(comptime layout: ImageLayout, resource: anytype) Image(layout) {
    _ = resource; // autofix
}

pub const Sampler = struct {
    id: u64,
};

test {
    std.testing.refAllDecls(@This());
}

const Graph = @This();
const std = @import("std");
