pub const rendering = @import("rendering.zig");
pub const windowing = @import("windowing.zig");
pub const asset = @import("asset.zig");
pub const ecs = @import("ecs.zig");
pub const graphics = @import("graphics.zig");
pub const gpu_program = @import("gpu_progam.zig");
pub const init = @import("init.zig");
pub const renderer_3d = @import("renderer_3d.zig");
pub const math = @import("math.zig");
pub const input = @import("input.zig");
pub const log = @import("log.zig").log;
pub const reflect = @import("reflect/reflect.zig");
pub const physics = @import("physics.zig");
pub const systems = @import("systems.zig");
pub const components = @import("components.zig");
pub const gui = @import("gui.zig");

///Sets global project level options at compile time that can be overriden in project root
///Analogous to std.Options
pub const Options = struct {
    ///Set to true if any form of code hot swapping is used
    ///Important as some parts of the engine will need to be aware of this
    code_hot_swap_enable: bool = false,

    graphics: graphics.Options = .{},
    windowing: windowing.Options = .{},
    rendering: rendering.Options = .{},
};

///The options set by the root file
pub const quanta_options: Options = if (@hasDecl(root, "quanta_options")) root.quanta_options else .{};

const root = @import("root");

test {
    const std = @import("std");

    std.testing.refAllDecls(@This());
}
