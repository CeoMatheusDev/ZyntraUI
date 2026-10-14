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

    ctx.beginFrame();
    // M2+: construção de widgets e emissão de draw lists aqui.
    const click_area = zyntra_ui.Rect.init(10, 10, 120, 40);
    const mouse = zyntra_ui.Vec2.init(30, 25);
    const hovered: bool = click_area.contains(mouse);
    const id = zyntra_ui.Id.fromString("examples/minimal:button-ok");
    _ = id;
    _ = hovered;
    ctx.endFrame();

    std.debug.print("zyntra_ui {d}.{d}.{d} ok (frame={d})\n", .{
        zyntra_ui.version_major,
        zyntra_ui.version_minor,
        zyntra_ui.version_patch,
        ctx.frame_index,
    });
}
