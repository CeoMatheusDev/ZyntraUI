const std = @import("std");
const zyntra_ui = @import("zyntra_ui");
const button_mod = @import("zyntra_ui").widgets.button;
const checkbox_mod = @import("zyntra_ui").widgets.checkbox;
const label_mod = @import("zyntra_ui").widgets.label;
const renderer_mod = @import("zyntra_ui").draw.renderer;

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
    const font = zyntra_ui.FontMetrics.withSize(16);
    var checked = false;
    var null_backend = zyntra_ui.NullRenderer{};

    // Frame 1: layout + widgets + label medido + submissão ao backend.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(30, 25) } });

    const content = zyntra_ui.EdgeInsets.all(16).apply(ctx.viewport);
    var placer = zyntra_ui.StackPlacer.init(content, .vertical, 12);
    const btn_rect = placer.next(.{ .w = 200, .h = 40 });
    const chk_rect = placer.next(.{ .w = chk_style.box_size, .h = chk_style.box_size });
    const lbl_rect = placer.next(.{ .w = 300, .h = font.lineHeight() });

    const btn = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m4:btn"), btn_rect, btn_style);
    const chk = try checkbox_mod.checkbox(&ctx, zyntra_ui.Id.fromString("examples/m4:chk"), chk_rect, &checked, chk_style);
    const lbl = try label_mod.label(
        &ctx,
        zyntra_ui.Id.fromString("examples/m4:lbl"),
        lbl_rect,
        "Hello, ZyntraUI!",
        theme.text,
        font,
        false,
    );
    const stats = try null_backend.submit(ctx.drawCommands(), ctx.viewport);
    ctx.endFrame();

    std.debug.print("m4 frame={d} btn{{clicked={}}} chk{{checked={}}} label{{w={d} trunc={}}} backend{{visible={d} culled={d}}}\n", .{
        ctx.frame_index,
        btn.clicked,
        chk.checked,
        lbl.metrics.width,
        lbl.truncated,
        stats.visible,
        stats.culled,
    });

    // Frame 2: comando fora do viewport é cullado pelo backend.
    ctx.beginFrame();
    try ctx.draw.rectFilled(ctx.allocator, zyntra_ui.Rect.init(5000, 5000, 10, 10), theme.accent);
    const s2 = try null_backend.submit(ctx.drawCommands(), ctx.viewport);
    std.debug.assert(s2.culled == 1 and s2.visible == 0);
    ctx.endFrame();
    std.debug.print("m4 frame2 cull ok (frames={d})\n", .{null_backend.frames});
}
