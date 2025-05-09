//!Optional debugging code for tracking and introspecting the various parts of a render graph at runtime

///Debug information about the source code that generated a graph
///This type is equal to the empty struct when debugging is disabled
///Functions returning void can be safely relied upon without need for upfront checking on the consuming code side
///Functions returning a value will return null if debug info is disabled
pub const DebugInfo = if (quanta_options.rendering.debug_info_enabled and !quanta_options.code_hot_swap_enable) struct {
    passes: std.AutoArrayHashMapUnmanaged(graph.PassHandle, struct {
        source_location: std.builtin.SourceLocation,
        pass_name: ?[]const u8 = null,
    }) = .{},
    buffers: std.AutoArrayHashMapUnmanaged(graph.BufferHandle, struct {
        source_location: std.builtin.SourceLocation,
        name: ?[]const u8 = null,
    }) = .{},
    images: std.AutoArrayHashMapUnmanaged(graph.ImageHandle, struct {
        source_location: std.builtin.SourceLocation,
        name: ?[]const u8 = null,
    }) = .{},
    file_map: std.StringHashMapUnmanaged(struct {
        source_code: []u8,
    }) = .{},

    pub fn deinit(self: *@This(), builder: Builder) void {
        for (self.buffers.values()) |buffer| {
            if (buffer.name == null) continue;

            builder.gpa.free(buffer.name.?);
        }

        for (self.images.values()) |image| {
            if (image.name == null) continue;

            builder.gpa.free(image.name.?);
        }

        for (self.passes.values()) |pass| {
            if (pass.pass_name == null) continue;

            builder.gpa.free(pass.pass_name.?);
        }

        self.passes.deinit(builder.gpa);
        self.buffers.deinit(builder.gpa);
        self.images.deinit(builder.gpa);

        var file_map_values = self.file_map.valueIterator();

        while (file_map_values.next()) |file_data| {
            builder.gpa.free(file_data.source_code);
        }

        self.file_map.deinit(builder.gpa);

        self.* = undefined;
    }

    pub fn reset(self: *@This(), builder: Builder) void {
        _ = self;
        _ = builder;
    }

    pub fn addPass(
        self: *@This(),
        builder: Builder,
        comptime src: std.builtin.SourceLocation,
        pass: graph.PassHandle,
    ) void {
        _ = self.passes.getOrPutValue(builder.gpa, pass, .{
            .source_location = src,
        }) catch return;
    }

    pub fn addBuffer(
        self: *@This(),
        builder: Builder,
        comptime src: std.builtin.SourceLocation,
        buffer: graph.BufferHandle,
    ) void {
        _ = self.buffers.getOrPutValue(builder.gpa, buffer, .{
            .source_location = src,
        }) catch return;
    }

    pub fn addImage(
        self: *@This(),
        builder: Builder,
        comptime src: std.builtin.SourceLocation,
        image: graph.ImageHandle,
    ) void {
        _ = self.images.getOrPutValue(builder.gpa, image, .{
            .source_location = src,
        }) catch return;
    }

    ///Parses the zig files associated with passes and resources to find their names
    ///Lazily loads and analyzes file data into memory
    pub fn getPassName(self: *@This(), builder: Builder, pass: graph.PassHandle) ?[]const u8 {
        var pass_info = self.passes.getPtr(pass) orelse return null;

        if (pass_info.pass_name == null) {
            const pass_source: std.builtin.SourceLocation = pass_info.source_location;

            const file_data = self.file_map.getOrPut(builder.gpa, pass_source.file) catch return null;

            if (!file_data.found_existing) {
                const file_source = std.fs.cwd().readFileAlloc(builder.gpa, pass_source.file, std.math.maxInt(usize)) catch return {
                    _ = self.file_map.remove(pass_source.file);

                    return null;
                };

                file_data.value_ptr.* = .{
                    .source_code = file_source,
                };
            }

            const file_source: []const u8 = file_data.value_ptr.source_code;

            var pass_line_comment: ?[]const u8 = null;
            var pass_line: []const u8 = "";
            var pass_line_index: u32 = 0;

            {
                var line_index: u32 = 1;

                var source_lines = std.mem.splitScalar(u8, file_source, '\n');

                var previous_line: []const u8 = "";

                while (source_lines.next()) |source_line| : (line_index += 1) {
                    defer previous_line = source_line;

                    if (line_index + 1 == pass_source.line) {
                        const is_comment = std.mem.containsAtLeast(u8, source_line, 1, "//");

                        if (is_comment) {
                            pass_line_comment = source_line;
                        }

                        //If the pass call has it's args split between multiple lines, then
                        //the @src() builtin will have a comma after it.
                        //We have made it in graph.Builder that @src() will ALWAYS be the first argument (after self)
                        const is_multiline = std.mem.endsWith(u8, source_lines.peek().?, ",");

                        if (is_multiline) {
                            pass_line = source_line;
                            break;
                        }
                    }

                    if (line_index == pass_source.line) {
                        pass_line = source_line;
                        break;
                    }
                }

                pass_line_index = line_index - 1;

                source_lines.reset();

                line_index = 0;

                while (source_lines.next()) |source_line| : (line_index += 1) {
                    if (line_index + 1 == pass_line_index) {
                        const is_comment = std.mem.containsAtLeast(u8, source_line, 1, "//");

                        if (is_comment) {
                            const comment_start = std.mem.indexOf(u8, source_line, "//").?;

                            pass_line_comment = source_line[comment_start..];
                            break;
                        }
                    }
                }
            }

            const source_location_string = std.fmt.allocPrint(builder.gpa, "{s}:{}:{}", .{
                pass_source.file,
                pass_source.line,
                pass_source.column,
            }) catch return null;
            defer builder.gpa.free(source_location_string);

            const name = std.mem.concat(builder.gpa, u8, &.{
                std.fs.path.stem(std.fs.path.basename(pass_source.file)),
                ".",
                pass_source.fn_name,
                "(...)",
                ": ",
                pass_line_comment orelse "",
                "; From: ",
                source_location_string,
            }) catch return null;

            pass_info.pass_name = name;
        }

        return pass_info.pass_name orelse null;
    }

    pub fn getBufferName(self: *@This(), builder: Builder, buffer: graph.BufferHandle) ?[]const u8 {
        var buffer_info = self.buffers.getPtr(buffer) orelse return null;

        if (buffer_info.name == null) {
            buffer_info.name = self.getResourceName(builder, buffer_info.source_location);
        }

        return buffer_info.name;
    }

    pub fn getImageName(self: *@This(), builder: Builder, image: graph.ImageHandle) ?[]const u8 {
        var image_info = self.images.getPtr(image) orelse return null;

        if (image_info.name == null) {
            image_info.name = self.getResourceName(builder, image_info.source_location);
        }

        return image_info.name;
    }

    ///Gets the name for a generic resource-like graph call by tokenizing the source
    pub fn getResourceName(self: *@This(), builder: Builder, source_location: std.builtin.SourceLocation) ?[]const u8 {
        const pass_source: std.builtin.SourceLocation = source_location;

        const file_data = self.file_map.getOrPut(builder.gpa, pass_source.file) catch return null;

        if (!file_data.found_existing) {
            const file_source = std.fs.cwd().readFileAlloc(builder.gpa, pass_source.file, std.math.maxInt(usize)) catch return {
                _ = self.file_map.remove(pass_source.file);

                return null;
            };

            file_data.value_ptr.* = .{
                .source_code = file_source,
            };
        }

        const file_source: []const u8 = file_data.value_ptr.source_code;

        var pass_line: []const u8 = "";
        var pass_line_index: u32 = 0;

        {
            var line_index: u32 = 1;

            var source_lines = std.mem.splitScalar(u8, file_source, '\n');

            var previous_line: []const u8 = "";

            while (source_lines.next()) |source_line| : (line_index += 1) {
                defer previous_line = source_line;

                if (line_index + 1 == pass_source.line) {
                    //If the pass call has it's args split between multiple lines, then
                    //the @src() builtin will have a comma after it.
                    //We have made it in graph.Builder that @src() will ALWAYS be the first argument (after self)
                    const is_multiline = std.mem.endsWith(u8, source_lines.peek().?, ",");

                    if (is_multiline) {
                        pass_line = source_line;
                        break;
                    }
                }

                if (line_index == pass_source.line) {
                    pass_line = source_line;
                    break;
                }
            }

            pass_line_index = line_index - 1;

            source_lines.reset();

            line_index = 0;
        }

        var tokenizer_buffer: [1024]u8 = undefined;

        const tokenizer_string = std.fmt.bufPrintZ(&tokenizer_buffer, "{s}", .{pass_line}) catch return null;

        var tokenizer = std.zig.Tokenizer.init(tokenizer_string);

        _ = tokenizer.next();
        const identifier_token = tokenizer.next();

        const name = std.mem.concat(builder.gpa, u8, &.{
            tokenizer_string[identifier_token.loc.start..identifier_token.loc.end],
        }) catch return null;

        return name;
    }
} else struct {
    pub inline fn deinit(_: *@This(), _: Builder) void {}
    pub inline fn reset(_: *@This(), _: Builder) void {}

    pub inline fn addPass(
        _: *@This(),
        _: Builder,
        _: std.builtin.SourceLocation,
        _: graph.PassHandle,
    ) void {}

    pub inline fn addBuffer(
        _: *@This(),
        _: Builder,
        _: std.builtin.SourceLocation,
        _: graph.BufferHandle,
    ) void {}

    pub fn addImage(
        _: *@This(),
        _: Builder,
        comptime _: std.builtin.SourceLocation,
        _: graph.ImageHandle,
    ) void {}

    pub inline fn getPassName(_: *@This(), _: Builder, _: graph.PassHandle) ?[]const u8 {
        return null;
    }

    pub inline fn getBufferName(_: *@This(), _: Builder, _: graph.BufferHandle) ?[]const u8 {
        return null;
    }

    pub inline fn getImageName(_: *@This(), _: Builder, _: graph.ImageHandle) ?[]const u8 {
        return null;
    }
};

test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const graph = @import("graph.zig");
const Builder = graph.Builder;
const quanta_options = @import("../root.zig").quanta_options;
