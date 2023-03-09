const std = @import("std");
const imgui = @import("cimgui.zig");
const zalgebra = @import("zalgebra");

pub fn begin(title: [:0]const u8) bool
{
    return imgui.igBegin(title.ptr, null, 0);
}

pub fn end() void 
{
    imgui.igEnd();
}

pub fn text(string: []const u8) void 
{
    imgui.igTextUnformatted(string.ptr, string.ptr + string.len);
}

pub fn textFormat(comptime format: []const u8, args: anytype) void 
{
    var format_buf: [4096 * 16]u8 = undefined;

    text(std.fmt.bufPrint(&format_buf, format, args) catch unreachable);
}

pub fn button(label: [:0]const u8) bool
{
    return imgui.igButton(label.ptr, .{ .x = 0, .y = 0 });
}

pub fn checkbox(label: [:0]const u8, value: *bool) bool 
{
    return imgui.igCheckbox(label, value);
}

pub fn treeNodePush(comptime format: []const u8, args: anytype) bool 
{
    var format_buf: [4096 * 8]u8 = undefined;

    const label = std.fmt.bufPrint(&format_buf, format, args) catch unreachable;

    const widget_id = imgui.ImGuiWindow_GetID_Str(imgui.igGetCurrentWindow(), label.ptr, label.ptr + label.len);

    return imgui.igTreeNodeBehavior(widget_id, 0, label.ptr, label.ptr + label.len);
}

pub fn treeNodePop() void 
{
    imgui.igTreePop();
}

pub fn collapsingHeader(comptime format: []const u8, args: anytype) bool 
{
    var format_buf: [4096 * 8]u8 = undefined;

    const label = std.fmt.bufPrintZ(&format_buf, format, args) catch unreachable;

    return imgui.igCollapsingHeader_BoolPtr(label.ptr, null, 0);
}

pub fn dragFloat(label: []const u8, float: *f32) void 
{
    _ = imgui.igDragFloat(label.ptr, float, 0.1, 0, 0, null, 0);
}

pub fn drawBoundingBox(
    view_projection: zalgebra.Mat4,
    transform: zalgebra.Mat4,
    min: @Vector(3, f32),
    max: @Vector(3, f32),    
) void 
{
    const model_view_projection = view_projection.mul(transform);

    const lines = [_][2]@Vector(3, f32) 
    {
        .{ .{ min[0], min[1], min[2] }, .{ max[0], min[1], min[2] } },
        .{ .{ min[0], min[1], min[2] }, .{ min[0], max[1], min[2] } },
        .{ .{ min[0], min[1], min[2] }, .{ min[0], min[1], max[2] } },
        .{ .{ min[0], max[1], min[2] }, .{ max[0], max[1], min[2] } },
        .{ .{ max[0], max[1], min[2] }, .{ max[0], min[1], min[2] } },
        .{ .{ max[0], min[1], min[2] }, .{ max[0], min[1], max[2] } },
        .{ .{ max[0], max[1], min[2] }, .{ max[0], max[1], max[2] } },
        .{ .{ min[0], max[1], min[2] }, .{ min[0], max[1], max[2] } },
        .{ .{ min[0], max[1], max[2] }, .{ max[0], max[1], max[2] } },
        .{ .{ min[0], max[1], max[2] }, .{ min[0], min[1], max[2] } },
        .{ .{ min[0], min[1], max[2] }, .{ max[0], min[1], max[2] } },
        .{ .{ max[0], max[1], max[2] }, .{ max[0], min[1], max[2] } },
    };

    const camera_pos = model_view_projection.mulByVec4(zalgebra.Vec4.zero());

    //Primitive clipping
    if (
        camera_pos.x() < -1 or camera_pos.x() > 1 or
        camera_pos.y() < -1 or camera_pos.y() > 1 or
        camera_pos.z() < -1 or camera_pos.z() > 1
    )
    {
        return;   
    }

    const viewport = imgui.igGetWindowViewport();

    for (lines) |line_pair|
    {
        drawLine(model_view_projection, viewport, line_pair);
    }
}

pub fn drawLine(
    model_view_projection: zalgebra.Mat4,
    viewport: *imgui.ImGuiViewport,
    line: [2]@Vector(3, f32)
) void
{
    var p0 = worldToScreenPos(line[0], model_view_projection, viewport) orelse return;
    var p1 = worldToScreenPos(line[1], model_view_projection, viewport) orelse return;

    const draw_list = imgui.igGetBackgroundDrawList_ViewportPtr(viewport);

    imgui.ImDrawList_AddLine(
        draw_list, 
        .{ .x = p0[0], .y = p0[1] },
        .{ .x = p1[0], .y = p1[1] },
        0xffffffff,
        2
    );   
}

///Returns null if world_pos doesn't map to a position on the screen (and should be clipped)
fn worldToScreenPos(
    world_pos: @Vector(3, f32), 
    matrix: zalgebra.Mat4,
    viewport: *imgui.ImGuiViewport,
) ?@Vector(2, f32)
{
    var screen_ndc = matrix.mulByVec4(.{ .data = .{ world_pos[0], world_pos[1], world_pos[2], 1 } });

    screen_ndc.data /= @splat(4, @as(f32, screen_ndc.w()));

    //TODO: use a general line clipping algorithm
    if (
        screen_ndc.z() < -1 or screen_ndc.z() > 1
    )
    {
        return null;
    }

    screen_ndc.data *= @splat(4, @as(f32, 0.5));
    screen_ndc.data += @splat(4, @as(f32, 0.5));

    var translation: @Vector(2, f32) = .{ screen_ndc.x(), screen_ndc.y() };

    translation[1] = 1 - translation[1];

    const screen_width = viewport.Size.x;
    const screen_height = viewport.Size.y;

    translation[0] *= screen_width;
    translation[1] *= screen_height;

    translation[0] += viewport.Pos.x;
    translation[1] += viewport.Pos.y;

    return translation;
}