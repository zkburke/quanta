impl: Impl,

pub inline fn deinit(self: *Window, allocator: std.mem.Allocator) void {
    defer self.* = undefined;
    defer self.impl.deinit(allocator);
}

pub inline fn pollEvents(self: *Window) !void {
    try self.impl.pollEvents();
}

pub inline fn shouldClose(self: *Window) bool {
    return self.impl.shouldClose();
}

///Get the current width of the window
pub inline fn getWidth(self: *Window) u16 {
    return self.impl.getWidth();
}

///Get the current height of the window
pub inline fn getHeight(self: *Window) u16 {
    return self.impl.getHeight();
}

///Returns the action state of a given key
pub inline fn getKey(self: *Window, key: windowing.Key) windowing.Action {
    return self.impl.getKey(key);
}

///Returns the action state of a given mouse button
pub inline fn getMouseButton(self: *Window, key: windowing.MouseButton) windowing.Action {
    return self.impl.getMouseButton(key);
}

///Returns the motion of the mouse device. Returns relative motion, which is independent of the window bounds or cursor position.
///The mouse can move whilst the cursor is stationary.
pub inline fn getMouseMotion(self: *Window) @Vector(2, i16) {
    return self.impl.getMouseMotion();
}

///Returns the position of the cursor within the bounds of the window
pub inline fn getCursorPosition(self: *Window) @Vector(2, i16) {
    return self.impl.getCursorPosition();
}

///Returns the motion of the cursor within the bounds of the window
pub inline fn getCursorMotion() @Vector(2, i16) {
    @compileError("Not Implemented");
}

///Confines the cursor to the bounds of the window and hides it
pub inline fn grabCursor(self: *Window) void {
    return self.impl.grabCursor();
}

///Releases the cursor from window confinement
pub inline fn ungrabCursor(self: *Window) void {
    return self.impl.ungrabCursor();
}

///Implementation structure
pub const Impl = switch (windowing.backend) {
    .wayland => @compileError("Wayland not supported"),
    .xcb => @import("xcb/XcbWindow.zig"),
    .win32 => @compileError("Win32 not supported"),
};

test {
    std.testing.refAllDecls(@This());
}

const Window = @This();
const windowing = @import("../windowing.zig");
const std = @import("std");