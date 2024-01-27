xcb_library: xcb_loader.Library,
connection: *xcb_loader.Connection,

pub fn init() !XcbWindowSystem {
    var self = XcbWindowSystem{
        .xcb_library = try xcb_loader.Library.load(),
        .connection = undefined,
    };

    self.connection = self.xcb_library.connect(null, null).?;
    errdefer self.xcb_library.disconnect(self.connection);

    return self;
}

pub fn deinit(self: *XcbWindowSystem) void {
    self.xcb_library.disconnect(self.connection);
    self.xcb_library.unload();
}

pub fn createWindow(
    self: *XcbWindowSystem,
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    title: []const u8,
) !XcbWindow {
    return XcbWindow.init(allocator, self, width, height, title);
}

const XcbWindowSystem = @This();
const XcbWindow = @import("XcbWindow.zig");
const windowing = @import("../../windowing.zig");
const xcb_loader = @import("xcb_loader.zig");
const std = @import("std");