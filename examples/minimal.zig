const std = @import("std");
const zyntra_ui = @import("zyntra_ui");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();

    // Frame 1: simula entrada do adaptador + emissão de desenho.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(30, 25) } });
    try ctx.pushEvent(.{
        .mouse_button = .{
            .button = .left,
            .pressed = true,
            .pos = zyntra_ui.Vec2.init(30, 25),
        },
    });

    const click_area = zyntra_ui.Rect.init(10, 10, 120, 40);
    var hovered = false;
    var clicked = false;
    for (ctx.pendingEvents()) |ev| {
        switch (ev) {
            .mouse_move => |m| hovered = click_area.contains(m.pos),
            .mouse_button => |b| {
                if (b.pressed and b.button == .left and click_area.contains(b.pos)) {
                    clicked = true;
                    hovered = true;
                }
            },
            else => {},
        }
    }

    const id = zyntra_ui.Id.fromString("examples/minimal:button-ok");
    _ = id;

    const bg = if (clicked)
        zyntra_ui.Color.rgb(60, 140, 70)
    else if (hovered)
        zyntra_ui.Color.rgb(70, 110, 180)
    else
        zyntra_ui.Color.rgb(50, 50, 55);
    try ctx.draw.rectFilled(ctx.allocator, click_area, bg);
    try ctx.draw.rectOutline(ctx.allocator, click_area, zyntra_ui.Color.rgb(255, 255, 255), 1.0);
    ctx.endFrame();

    std.debug.print("zyntra_ui {d}.{d}.{d} ok (frame={d} events={d} draw={d} hovered={} clicked={})\n", .{
        zyntra_ui.version_major,
        zyntra_ui.version_minor,
        zyntra_ui.version_patch,
        ctx.frame_index,
        ctx.pendingEvents().len,
        ctx.drawCommands().len,
        hovered,
        clicked,
    });

    // Frame 2: comprova limpeza por frame (sem vazamento lógico).
    ctx.beginFrame();
    std.debug.assert(ctx.pendingEvents().len == 0);
    std.debug.assert(ctx.drawCommands().len == 0);
    ctx.endFrame();
}
