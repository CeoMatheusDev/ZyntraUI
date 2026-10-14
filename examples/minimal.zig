const std = @import("std");
const zyntra_ui = @import("zyntra_ui");
const button_mod = @import("zyntra_ui").widgets.button;
const checkbox_mod = @import("zyntra_ui").widgets.checkbox;
const label_mod = @import("zyntra_ui").widgets.label;
const slider_mod = @import("zyntra_ui").widgets.slider;

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
    const sld_style = theme.sliderStyle();
    const font = zyntra_ui.FontMetrics.withSize(16);
    var checked = false;
    var volume: f32 = 30;
    var null_backend = zyntra_ui.NullRenderer{};

    const content = zyntra_ui.EdgeInsets.all(16).apply(ctx.viewport);
    var placer = zyntra_ui.StackPlacer.init(content, .vertical, 12);
    const btn_rect = placer.next(.{ .w = 200, .h = 40 });
    const chk_rect = placer.next(.{ .w = chk_style.box_size, .h = chk_style.box_size });
    const sld_rect = placer.next(.{ .w = 240, .h = 30 });
    const lbl_rect = placer.next(.{ .w = 300, .h = font.lineHeight() });

    // Frame 1: move + press no botão (captura, sem click ainda).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(30, 25) } });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(30, 25) },
    });
    const btn1 = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m7:btn"), btn_rect, btn_style);
    std.debug.assert(btn1.pressed and !btn1.clicked);
    ctx.endFrame();

    // Frame 2: release dentro (click) + slider + label + submit.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(30, 25) },
    });
    const btn = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m7:btn"), btn_rect, btn_style);
    const chk = try checkbox_mod.checkbox(&ctx, zyntra_ui.Id.fromString("examples/m7:chk"), chk_rect, &checked, chk_style);
    const lbl = try label_mod.label(
        &ctx,
        zyntra_ui.Id.fromString("examples/m7:lbl"),
        lbl_rect,
        "Hello, ZyntraUI!",
        theme.text,
        font,
        false,
    );
    const stats = try null_backend.submit(ctx.drawCommands(), ctx.viewport);
    ctx.endFrame();

    std.debug.print("m7 frame={d} btn{{clicked={}}} chk{{checked={}}} label{{w={d}}} backend{{visible={d} culled={d}}}\n", .{
        ctx.frame_index,
        btn.clicked,
        chk.checked,
        lbl.metrics.width,
        stats.visible,
        stats.culled,
    });

    // Frame 3: drag no slider (press + move com botão pressionado).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(sld_rect.x + 60, sld_rect.y + 15) },
    });
    _ = try slider_mod.slider(&ctx, zyntra_ui.Id.fromString("examples/m8:sld"), sld_rect, &volume, 0, 100, sld_style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(sld_rect.x + 180, sld_rect.y + 15) } });
    const sld = try slider_mod.slider(&ctx, zyntra_ui.Id.fromString("examples/m8:sld"), sld_rect, &volume, 0, 100, sld_style);
    ctx.endFrame();
    std.debug.print("m8 slider value={d} dragging={}\n", .{ volume, sld.dragging });
}
