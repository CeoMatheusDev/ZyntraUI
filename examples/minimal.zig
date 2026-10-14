const std = @import("std");
const zyntra_ui = @import("zyntra_ui");
const button_mod = @import("zyntra_ui").widgets.button;
const checkbox_mod = @import("zyntra_ui").widgets.checkbox;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ctx = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 800, 600),
    });
    defer ctx.deinit();

    const theme = zyntra_ui.Theme.darkDefault();
    const btn_style = theme.buttonStyle();
    const chk_style = theme.checkboxStyle();
    var checked = false;

    // Frame 1: layout vertical + botão com click + checkbox com toggle.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(30, 25) } });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(30, 25) },
    });

    const content = zyntra_ui.EdgeInsets.all(16).apply(ctx.viewport);
    var placer = zyntra_ui.StackPlacer.init(content, .vertical, 12);
    const btn_rect = placer.next(.{ .w = 200, .h = 40 });
    const chk_rect = placer.next(.{ .w = chk_style.box_size, .h = chk_style.box_size });

    const btn = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m3:btn"), btn_rect, btn_style);
    const chk = try checkbox_mod.checkbox(&ctx, zyntra_ui.Id.fromString("examples/m3:chk"), chk_rect, &checked, chk_style);
    ctx.endFrame();

    std.debug.print("m3 frame={d} btn{{hovered={} clicked={}}} chk{{toggled={} checked={}}} draw={d}\n", .{
        ctx.frame_index,
        btn.hovered,
        btn.clicked,
        chk.toggled,
        chk.checked,
        ctx.drawCommands().len,
    });

    // Frame 2: sem eventos — widgets idle, listas limpas e reutilizadas.
    ctx.beginFrame();
    std.debug.assert(ctx.pendingEvents().len == 0);
    const btn2 = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m3:btn"), btn_rect, btn_style);
    std.debug.assert(!btn2.clicked);
    ctx.endFrame();
    std.debug.print("m3 frame2 ok draw={d}\n", .{ctx.drawCommands().len});
}
