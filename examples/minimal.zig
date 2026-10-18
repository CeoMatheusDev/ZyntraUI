const std = @import("std");
const zyntra_ui = @import("zyntra_ui");
const button_mod = @import("zyntra_ui").widgets.button;
const checkbox_mod = @import("zyntra_ui").widgets.checkbox;
const label_mod = @import("zyntra_ui").widgets.label;
const slider_mod = @import("zyntra_ui").widgets.slider;
const text_input_mod = @import("zyntra_ui").widgets.text_input;
const scroll_mod = @import("zyntra_ui").widgets.scroll;
const popup_mod = @import("zyntra_ui").widgets.popup;
const progress_mod = @import("zyntra_ui").widgets.progress;
const menu_mod = @import("zyntra_ui").widgets.menu;
const radio_mod = @import("zyntra_ui").widgets.radio;
const tooltip_mod = @import("zyntra_ui").widgets.tooltip;
const modal_mod = @import("zyntra_ui").widgets.modal;
const combo_mod = @import("zyntra_ui").widgets.combo;
const switch_mod = @import("zyntra_ui").widgets.@"switch";
const spinner_mod = @import("zyntra_ui").widgets.spinner;
const textarea_mod = @import("zyntra_ui").widgets.textarea;
const separator_mod = @import("zyntra_ui").widgets.separator;
const toolbar_mod = @import("zyntra_ui").widgets.toolbar;
const statusbar_mod = @import("zyntra_ui").widgets.statusbar;
const groupbox_mod = @import("zyntra_ui").widgets.groupbox;
const panel_mod = @import("zyntra_ui").widgets.panel;
const splitter_mod = @import("zyntra_ui").widgets.splitter;
const dock_view_mod = @import("zyntra_ui").widgets.dock_view;
const tab_bar_mod = @import("zyntra_ui").widgets.tab_bar;

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
    const ti_style = theme.textInputStyle();
    const font = zyntra_ui.FontMetrics.withSize(16);
    var checked = false;
    var volume: f32 = 30;
    var null_backend = zyntra_ui.NullRenderer{};

    const content = zyntra_ui.EdgeInsets.all(16).apply(ctx.viewport);
    var placer = zyntra_ui.StackPlacer.init(content, .vertical, 12);
    const btn_rect = placer.next(.{ .w = 200, .h = 40 });
    const chk_rect = placer.next(.{ .w = chk_style.box_size, .h = chk_style.box_size });
    const sld_rect = placer.next(.{ .w = 240, .h = 30 });
    const ti_rect = placer.next(.{ .w = 240, .h = 30 });
    const lbl_rect = placer.next(.{ .w = 300, .h = font.lineHeight() });
    var name_buf: [32]u8 = undefined;
    var name_len: usize = 0;

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

    // Teclado: botão segue focado desde o click (frame 1); Espaço clica.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .space, .pressed = true, .modifiers = .{} } });
    const btk = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m7:btn"), btn_rect, btn_style);
    ctx.endFrame();
    std.debug.print("m29 kb clicked={}\n", .{btk.clicked});

    // Rasteriza os comandos do frame 2 num framebuffer 800×600 de prova.
    // (Requer reter os comandos: aqui reexecutamos os widgets; draws são
    // determinísticos para os mesmos eventos.)
    var swfb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 800, 600);
    defer swfb.deinit(allocator);
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(30, 25) },
    });
    _ = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m7:btn"), btn_rect, btn_style);
    const swstats = try zyntra_ui.software.raster.render(&swfb, ctx.drawCommands(), ctx.viewport);
    ctx.endFrame();
    var pxsum: u64 = 0;
    for (swfb.pixels) |b| pxsum += b;
    std.debug.print("m14 software drawn={d} culled={d} skipped_text={d} pxsum={d}\n", .{
        swstats.drawn,
        swstats.culled,
        swstats.skipped_text,
        pxsum,
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

    // Teclado no slider (focado no press do frame do drag): Right +5.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    const sldk = try slider_mod.slider(&ctx, zyntra_ui.Id.fromString("examples/m8:sld"), sld_rect, &volume, 0, 100, sld_style);
    ctx.endFrame();
    std.debug.print("m30 slider kb value={d} changed={}\n", .{ volume, sldk.changed });

    // Solta o botão sondando o slider (captura órfã bloqueia outros).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(sld_rect.x + 180, sld_rect.y + 15) } });
    _ = try slider_mod.slider(&ctx, zyntra_ui.Id.fromString("examples/m8:sld"), sld_rect, &volume, 0, 100, sld_style);
    ctx.endFrame();

    // Frame 4: click no input + digita "Oi" + Enter.
    var name_cursor: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(ti_rect.x + 5, ti_rect.y + 5) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'O' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'i' } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    const ti = try text_input_mod.textInput(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, font, ti_style);
    ctx.endFrame();
    std.debug.print("m9 input text={s} submitted={}\n", .{ name_buf[0..name_len], ti.submitted });

    // Frame 5: seta esquerda + "!" insere no meio: "O!i".
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = '!' } });
    _ = try text_input_mod.textInput(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, font, ti_style);
    ctx.endFrame();
    std.debug.print("m10 input text={s} cursor={d}\n", .{ name_buf[0..name_len], name_cursor });

    // Frame 6: segundo campo + Tab circula o foco 1 → 2.
    const ti2_rect = placer.next(.{ .w = 240, .h = 30 });
    var name2_buf: [32]u8 = undefined;
    var name2_len: usize = 0;
    var name2_cursor: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{} } });
    _ = try text_input_mod.textInput(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, font, ti_style);
    _ = try text_input_mod.textInput(&ctx, zyntra_ui.Id.fromString("examples/m12:ti2"), ti2_rect, &name2_buf, &name2_len, &name2_cursor, font, ti_style);
    ctx.endFrame();
    ctx.beginFrame();
    const t1 = try text_input_mod.textInput(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, font, ti_style);
    const t2 = try text_input_mod.textInput(&ctx, zyntra_ui.Id.fromString("examples/m12:ti2"), ti2_rect, &name2_buf, &name2_len, &name2_cursor, font, ti_style);
    ctx.endFrame();
    std.debug.print("m12 tab focus1={} focus2={}\n", .{ t1.focused, t2.focused });

    // Frame 7: volta o foco ao campo 1, seleciona tudo (+highlight).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(ti_rect.x + 5, ti_rect.y + 5) },
    });
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .shift = true } } });
    var sel_anchor: usize = 0;
    name_cursor = name_len; // caret no fim antes de selecionar
    const ts = try text_input_mod.textInputSelected(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, font, ti_style);
    ctx.endFrame();
    std.debug.print("m13 select selected={} draws={d}\n", .{ ts.selected, ctx.drawCommands().len });

    // Frame 8: digitar substitui a faixa ("O!i" → "Z", com histórico).
    var hist = zyntra_ui.TextHistory(8, 32){};
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'Z' } });
    _ = try text_input_mod.textInputHistory(8, 32, &ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, &hist, font, ti_style);
    ctx.endFrame();
    std.debug.print("m13 replace text={s}\n", .{name_buf[0..name_len]});

    // Frame 9: undo (Ctrl+Z) restaura "O!i"; redo (Ctrl+Y) volta "Z".
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const hu = try text_input_mod.textInputHistory(8, 32, &ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, &hist, font, ti_style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .y, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const hr = try text_input_mod.textInputHistory(8, 32, &ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, &hist, font, ti_style);
    ctx.endFrame();
    std.debug.print("m19 undo={} redo={} text={s}\n", .{ hu.undone, hr.redone, name_buf[0..name_len] });

    // Frame 10: seleciona tudo, Ctrl+C, apaga, Ctrl+V restaura.
    var clipmem: [32]u8 = undefined;
    var clip = zyntra_ui.Clipboard{ .buf = &clipmem };
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .shift = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .c, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .v, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try text_input_mod.textInputClipboard(8, 32, &ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, &hist, &clip, font, ti_style);
    ctx.endFrame();
    std.debug.print("m20 clip={s} text={s}\n", .{ clip.buf[0..clip.len], name_buf[0..name_len] });

    // Solta o press do frame m20 (captura retida bloquearia o modal).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(ti_rect.x + 5, ti_rect.y + 5) } });
    _ = try text_input_mod.textInputSelected(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, font, ti_style);
    ctx.endFrame();

    // Ctrl+A seleciona tudo no campo (foco retido).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .a, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const ta = try text_input_mod.textInputSelected(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, font, ti_style);
    ctx.endFrame();
    std.debug.print("m32 select-all selected={}\n", .{ta.selected});

    // Ctrl+Backspace apaga a palavra anterior ("Z foo" → "Z ").
    ctx.beginFrame();
    try ctx.pushEvent(.{ .text = .{ .codepoint = ' ' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'f' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'o' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'o' } });
    try ctx.pushEvent(.{ .key = .{ .key = .backspace, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try text_input_mod.textInputSelected(&ctx, zyntra_ui.Id.fromString("examples/m9:ti"), ti_rect, &name_buf, &name_len, &name_cursor, &sel_anchor, font, ti_style);
    ctx.endFrame();
    std.debug.print("m34 word-kill len={d}\n", .{name_len});

    // Frame 11: scroll com wheel sobre a vista (conteúdo 300px em 100px).
    var scrolled: f32 = 0;
    const sc_style = theme.scrollStyle();
    const sc_bounds = zyntra_ui.Rect.init(300, 400, 200, 100);
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -4, .pos = zyntra_ui.Vec2.init(400, 450) } });
    const sc = try scroll_mod.beginScroll(
        &ctx,
        zyntra_ui.Id.fromString("examples/m16:sc"),
        sc_bounds,
        &scrolled,
        300,
        24,
        sc_style,
    );
    // (filhos viriam aqui, posicionados em sc.content)
    try scroll_mod.endScroll(&ctx, sc_bounds, scrolled, 300, sc_style);
    ctx.endFrame();
    std.debug.print("m16 scroll offset={d} max={d} draws={d}\n", .{ scrolled, sc.max_offset, ctx.drawCommands().len });

    // Frame 12: press no thumb + arrasto (thumb em y≈432..465).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(496, 440) },
    });
    _ = try scroll_mod.beginScroll(
        &ctx,
        zyntra_ui.Id.fromString("examples/m16:sc"),
        sc_bounds,
        &scrolled,
        300,
        24,
        sc_style,
    );
    try scroll_mod.endScroll(&ctx, sc_bounds, scrolled, 300, sc_style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(496, 460) } });
    const scd = try scroll_mod.beginScroll(
        &ctx,
        zyntra_ui.Id.fromString("examples/m16:sc"),
        sc_bounds,
        &scrolled,
        300,
        24,
        sc_style,
    );
    try scroll_mod.endScroll(&ctx, sc_bounds, scrolled, 300, sc_style);
    ctx.endFrame();
    std.debug.print("m17 drag offset={d} dragging={}\n", .{ scrolled, scd.dragging });

    // Solta o scroll (captura retida bloquearia o botão do combo).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(496, 460) } });
    _ = try scroll_mod.beginScroll(
        &ctx,
        zyntra_ui.Id.fromString("examples/m16:sc"),
        sc_bounds,
        &scrolled,
        300,
        24,
        sc_style,
    );
    try scroll_mod.endScroll(&ctx, sc_bounds, scrolled, 300, sc_style);
    ctx.endFrame();

    // Teclado no scroll: press foca + PageDown desce 100 (130→200 clamp).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(400, 450) },
    });
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    const sck = try scroll_mod.beginScroll(
        &ctx,
        zyntra_ui.Id.fromString("examples/m16:sc"),
        sc_bounds,
        &scrolled,
        300,
        24,
        sc_style,
    );
    try scroll_mod.endScroll(&ctx, sc_bounds, scrolled, 300, sc_style);
    ctx.endFrame();
    std.debug.print("m31 scroll kb offset={d} scrolled={}\n", .{ scrolled, sck.scrolled });

    // Frame 13: easing dirige um fade (0→1 em 1s, amostrado).
    const tw = try zyntra_ui.Tween.init(0, 1, 1.0, .quad_out);
    var timer = try zyntra_ui.AnimTimer.init(1.0, false);
    var step: u32 = 0;
    while (step < 4) : (step += 1) {
        timer.tick(0.25);
        std.debug.print("m11 t={d:.2} v={d:.3}\n", .{ timer.progress(), tw.valueAt(timer.elapsed) });
    }

    // Frame 14: popup aberto + press fora dispensa; progresso a 75%.
    var open = true;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(700, 550) },
    });
    if (open) {
        const pop = try popup_mod.beginPopup(
            &ctx,
            zyntra_ui.Id.fromString("examples/m18:pop"),
            zyntra_ui.Rect.init(300, 200, 160, 120),
            theme.popupStyle(),
        );
        if (pop.dismissed) open = false;
        try popup_mod.endPopup(&ctx);
    }
    try progress_mod.progress(&ctx, zyntra_ui.Rect.init(16, 560, 200, 16), 0.75, theme.progressStyle());
    ctx.endFrame();
    std.debug.print("m18 popup open={} draws={d}\n", .{ open, ctx.drawCommands().len });

    // Frame 15: menu com 3 itens, click no item 1 ("Save").
    // Demonstra checkmarks (`checked`) e dicas de atalho (`shortcut`).
    const mitems = [_]zyntra_ui.widgets.menu.MenuItem{
        .{ .label = "Open", .checked = true, .shortcut = "Ctrl+O" },
        .{ .label = "Save", .shortcut = "Ctrl+S" },
        .{ .label = "Quit", .enabled = false, .shortcut = "Ctrl+Q" },
    };
    var mactive: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(400, 230) },
    });
    const mm = try menu_mod.menu(
        &ctx,
        zyntra_ui.Id.fromString("examples/m22:menu"),
        zyntra_ui.Rect.init(350, 200, 160, 100),
        &mitems,
        &mactive,
        font,
        theme.menuStyle(),
    );
    ctx.endFrame();
    std.debug.print("m22 menu chosen={?d} active={d}\n", .{ mm.chosen, mactive });

    // Frame 16: cascata — hover no pai abre submenu; click escolhe nele.
    const pitems = [_]zyntra_ui.widgets.menu.MenuItem{.{ .label = "File" }};
    const sitems = [_]zyntra_ui.widgets.menu.MenuItem{ .{ .label = "New" }, .{ .label = "Open" } };
    var pactive: usize = 0;
    var sactive: usize = 0;
    const pb = zyntra_ui.Rect.init(350, 320, 160, 40);
    const sbih: f32 = 25;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(520, 350) },
    });
    const pm = try menu_mod.menuNested(
        &ctx,
        zyntra_ui.Id.fromString("examples/m23:p"),
        pb,
        &pitems,
        &pactive,
        font,
        theme.menuStyle(),
        .{ .id = zyntra_ui.Id.fromString("examples/m23:s"), .bounds = zyntra_ui.widgets.menu.submenuBounds(pb, 0, sbih, sitems.len, 140) },
    );
    const sb2 = zyntra_ui.widgets.menu.submenuBounds(pb, 0, sbih, sitems.len, 140);
    const sm = try menu_mod.menu(&ctx, zyntra_ui.Id.fromString("examples/m23:s"), sb2, &sitems, &sactive, font, theme.menuStyle());
    ctx.endFrame();
    std.debug.print("m23 cascade parent_dismissed={} sub_chosen={?d}\n", .{ pm.dismissed, sm.chosen });

    // Frame 17: Right foca o submenu; Enter escolhe nele.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(360, 330) },
    });
    _ = try menu_mod.menuNested(
        &ctx,
        zyntra_ui.Id.fromString("examples/m23:p"),
        pb,
        &pitems,
        &pactive,
        font,
        theme.menuStyle(),
        .{ .id = zyntra_ui.Id.fromString("examples/m23:s"), .bounds = sb2 },
    );
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    _ = try menu_mod.menuNested(
        &ctx,
        zyntra_ui.Id.fromString("examples/m23:p"),
        pb,
        &pitems,
        &pactive,
        font,
        theme.menuStyle(),
        .{ .id = zyntra_ui.Id.fromString("examples/m23:s"), .bounds = sb2 },
    );
    _ = try menu_mod.menu(&ctx, zyntra_ui.Id.fromString("examples/m23:s"), sb2, &sitems, &sactive, font, theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    _ = try menu_mod.menuNested(
        &ctx,
        zyntra_ui.Id.fromString("examples/m23:p"),
        pb,
        &pitems,
        &pactive,
        font,
        theme.menuStyle(),
        .{ .id = zyntra_ui.Id.fromString("examples/m23:s"), .bounds = sb2 },
    );
    const smk = try menu_mod.menu(&ctx, zyntra_ui.Id.fromString("examples/m23:s"), sb2, &sitems, &sactive, font, theme.menuStyle());
    ctx.endFrame();
    std.debug.print("m24 kb cross-level chosen={?d}\n", .{smk.chosen});

    // Radio: 3 opções, click na última + seta sobe.
    const ropts = [_][]const u8{ "Red", "Green", "Blue" };
    var rsel: usize = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(20, 655) },
    });
    _ = try radio_mod.radio(&ctx, zyntra_ui.Id.fromString("examples/m25:r"), zyntra_ui.Rect.init(16, 600, 160, 60), &ropts, &rsel, font, theme.radioStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .up, .pressed = true, .modifiers = .{} } });
    const rr = try radio_mod.radio(&ctx, zyntra_ui.Id.fromString("examples/m25:r"), zyntra_ui.Rect.init(16, 600, 160, 60), &ropts, &rsel, font, theme.radioStyle());
    ctx.endFrame();
    std.debug.print("m25 radio selected={d} focused={}\n", .{ rsel, rr.focused });

    // Tooltip: 2 frames com hover e delay 2 → visível no 2º.
    var tip = zyntra_ui.TooltipState{};
    var f: u32 = 0;
    var tvis = false;
    var tdraws: usize = 0;
    while (f < 2) : (f += 1) {
        ctx.beginFrame();
        try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(30, 25) } });
        const tr = try tooltip_mod.tooltip(
            &ctx,
            zyntra_ui.Id.fromString("examples/m26:tip"),
            zyntra_ui.Rect.init(10, 10, 120, 40),
            "Save file",
            font,
            theme.tooltipStyle(),
            2,
            &tip,
        );
        tvis = tr.visible;
        tdraws = ctx.drawCommands().len;
        ctx.endFrame();
    }
    std.debug.print("m26 tooltip visible={} draws={d}\n", .{ tvis, tdraws });

    // Modal: aberto bloqueia o fundo por convenção (botão nem sondado);
    // Escape dispensa.
    var mopen = true;
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .escape, .pressed = true, .modifiers = .{} } });
    if (mopen) {
        const mo = try modal_mod.beginModal(
            &ctx,
            zyntra_ui.Id.fromString("examples/m27:modal"),
            zyntra_ui.Rect.init(250, 150, 300, 200),
            theme.modalStyle(),
        );
        if (mo.dismissed) mopen = false;
        try modal_mod.endModal(&ctx);
    } else {
        _ = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m7:btn"), btn_rect, btn_style);
    }
    ctx.endFrame();
    std.debug.print("m27 modal open={} draws={d}\n", .{ mopen, ctx.drawCommands().len });

    // Combo: abre no campo, escolhe item 1 no menu.
    const copts = [_][]const u8{ "Red", "Green", "Blue" };
    var csel: usize = 0;
    var copen = false;
    const cbounds = zyntra_ui.Rect.init(500, 500, 160, 30);
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(510, 510) },
    });
    _ = try combo_mod.combo(&ctx, zyntra_ui.Id.fromString("examples/m36:c"), cbounds, &copts, &csel, &copen, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(510, 510) },
    });
    _ = try combo_mod.combo(&ctx, zyntra_ui.Id.fromString("examples/m36:c"), cbounds, &copts, &csel, &copen, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(510, 560) },
    });
    const cmb = try combo_mod.combo(&ctx, zyntra_ui.Id.fromString("examples/m36:c"), cbounds, &copts, &csel, &copen, font, theme.buttonStyle(), theme.menuStyle());
    ctx.endFrame();
    std.debug.print("m36 combo selected={d} open={} changed={}\n", .{ csel, copen, cmb.changed });

    // Label multilinha: "aaa bbb\ncc" em largura 20 → 3 textos.
    ctx.beginFrame();
    const lw = try label_mod.labelWrapped(
        &ctx,
        zyntra_ui.Id.fromString("examples/m37:lbl"),
        zyntra_ui.Rect.init(16, 500, 20, 200),
        "aaa bbb\ncc",
        theme.text,
        font,
        false,
    );
    ctx.endFrame();
    std.debug.print("m37 wrapped draws={d} truncated={} lines={d}\n", .{ ctx.drawCommands().len, lw.truncated, lw.metrics.lines });

    // Modal arrastável: press na barra + move preservando o grab.
    var mbounds = zyntra_ui.Rect.init(250, 150, 300, 200);
    var mdrag = zyntra_ui.ModalDragState{};
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(260, 160) },
    });
    _ = try modal_mod.beginModalDraggable(&ctx, zyntra_ui.Id.fromString("examples/m39:modal"), &mbounds, 24, &mdrag, theme.modalStyle());
    try modal_mod.endModal(&ctx);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = zyntra_ui.Vec2.init(300, 300) } });
    const md = try modal_mod.beginModalDraggable(&ctx, zyntra_ui.Id.fromString("examples/m39:modal"), &mbounds, 24, &mdrag, theme.modalStyle());
    try modal_mod.endModal(&ctx);
    ctx.endFrame();
    std.debug.print("m39 drag pos={d},{d} dragging={}\n", .{ mbounds.x, mbounds.y, md.dragging });

    // Switch (M63): press + release dentro alterna; foco + Espaço alterna.
    ctx.clearPressCapture();
    const sw_style = theme.switchStyle();
    const sw_bounds = zyntra_ui.Rect.init(600, 560, 44, 22);
    var sw_on = false;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(605, 571) },
    });
    _ = try switch_mod.beginSwitch(&ctx, zyntra_ui.Id.fromString("examples/m63:sw"), sw_bounds, &sw_on, sw_style);
    ctx.endFrame();
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = zyntra_ui.Vec2.init(605, 571) },
    });
    const swc = try switch_mod.beginSwitch(&ctx, zyntra_ui.Id.fromString("examples/m63:sw"), sw_bounds, &sw_on, sw_style);
    ctx.endFrame();
    std.debug.print("m63 switch toggled={} on={} focused={}\n", .{ swc.toggled, sw_on, swc.focused });

    // Spinner (M64): indicador indeterminado; a cabeça gira com o tempo.
    const sp_style = theme.spinnerStyle();
    ctx.beginFrame();
    try spinner_mod.spinner(&ctx, zyntra_ui.Vec2.init(680, 571), 0.3, sp_style);
    const sp_head = spinner_mod.spinnerHeadIndex(sp_style.dots, 0.3);
    const sp_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print("m64 spinner head={d} draws={d}\n", .{ sp_head, sp_draws });

    // Textarea (M65): multilinha — digita, Enter cria linha, setas navegam.
    const ta_style = theme.textInputStyle();
    const ta_bounds = zyntra_ui.Rect.init(16, 620, 240, 60);
    var ta_buf: [64]u8 = undefined;
    var ta_len: usize = 0;
    var ta_cursor: usize = 0;
    var ta_anchor: usize = 0;
    var ta_scroll: f32 = 0;
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(20, 624) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'h' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'i' } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'Z' } });
    const tares = try textarea_mod.textArea(&ctx, zyntra_ui.Id.fromString("examples/m65:ta"), ta_bounds, &ta_buf, &ta_len, &ta_cursor, &ta_anchor, &ta_scroll, font, ta_style);
    ctx.endFrame();
    std.debug.print("m65 textarea text=\"{s}\" lines={d} focused={}\n", .{ ta_buf[0..ta_len], textarea_mod.textAreaLineCount(&ta_buf, ta_len), tares.focused });

    // Separator (M66): divisor estático (horizontal/vertical + rótulo).
    const sep_style = theme.separatorStyle();
    ctx.beginFrame();
    try separator_mod.separator(&ctx, zyntra_ui.Rect.init(16, 700, 240, 1), .horizontal, sep_style);
    try separator_mod.separatorLabeled(&ctx, zyntra_ui.Rect.init(16, 716, 240, 16), .horizontal, "OU", font, theme.text, sep_style);
    try separator_mod.separator(&ctx, zyntra_ui.Rect.init(290, 700, 1, 32), .vertical, sep_style);
    const sep_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print("m66 separator draws={d}\n", .{sep_draws});

    // Toolbar (M67): chrome + posicionamento determinístico; os itens são
    // desenhados pelos próprios widgets (aqui, buttons).
    const tb_style = theme.toolbarStyle();
    const tb_bounds = zyntra_ui.Rect.init(16, 748, 240, 40);
    ctx.beginFrame();
    var tb = try toolbar_mod.toolbar(&ctx, tb_bounds, tb_style);
    const tb_btn0 = tb.nextItem(64);
    _ = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m67:b0"), tb_btn0, theme.buttonStyle());
    const tb_btn1 = tb.nextItem(64);
    _ = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m67:b1"), tb_btn1, theme.buttonStyle());
    try toolbar_mod.toolbarSeparator(&ctx, &tb, theme.separatorStyle());
    const tb_btn2 = tb.nextItem(48);
    _ = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m67:b2"), tb_btn2, theme.buttonStyle());
    const tb_res = tb.remaining();
    ctx.endFrame();
    std.debug.print("m67 toolbar items=3 remaining={d:.1} overflowed={}\n", .{ tb_res, tb.overflowed });

    // StatusBar (M68): chrome + segmentos à esquerda e à direita.
    const sb_style = theme.statusBarStyle();
    ctx.beginFrame();
    var sb = try statusbar_mod.statusBar(&ctx, zyntra_ui.Rect.init(16, 804, 320, 28), sb_style);
    _ = try statusbar_mod.statusBarText(&ctx, &sb, "pronto", font, theme.text);
    try statusbar_mod.statusBarSeparator(&ctx, &sb, theme.separatorStyle());
    _ = try statusbar_mod.statusBarText(&ctx, &sb, "3 itens", font, theme.text);
    const sb_right = sb.nextRight(72);
    _ = try button_mod.button(&ctx, zyntra_ui.Id.fromString("examples/m68:b"), sb_right, theme.buttonStyle());
    const sb_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print("m68 statusbar draws={d} remaining={d:.1} overflowed={}\n", .{ sb_draws, sb.remaining(), sb.overflowed });

    // GroupBox (M73): caixa com título + filho posicionado no conteúdo.
    ctx.beginFrame();
    const gb_content = try groupbox_mod.groupBox(&ctx, zyntra_ui.Rect.init(360, 700, 200, 100), "Opções", font, theme.groupBoxStyle());
    _ = try checkbox_mod.checkbox(&ctx, zyntra_ui.Id.fromString("examples/m73:chk"), .{
        .x = gb_content.x,
        .y = gb_content.y,
        .w = chk_style.box_size,
        .h = chk_style.box_size,
    }, &checked, chk_style);
    const gb_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print("m73 groupbox draws={d} content_h={d:.1}\n", .{ gb_draws, gb_content.h });

    // Panel + splitter aninhável (M74, base do docking): cabeçalho com
    // título/controles devolve o conteúdo; o splitter divide esse conteúdo
    // em dois painéis (lado a / lado b) — composição para hierarquia.
    var panel_collapsed = false;
    const panel_bounds = zyntra_ui.Rect.init(600, 690, 220, 120);
    const split_style = theme.splitterStyle();
    ctx.beginFrame();
    const pni = try panel_mod.panel(
        &ctx,
        zyntra_ui.Id.fromString("examples/m74:panel"),
        panel_bounds,
        &panel_collapsed,
        .{ .title = "Camadas", .closable = true },
        font,
        theme.panelStyle(),
    );
    var split_pos: f32 = pni.content.x + pni.content.w * 0.5;
    const panes = splitter_mod.splitterPanes(pni.content, .vertical, split_pos, split_style);
    _ = try splitter_mod.beginSplitter(
        &ctx,
        zyntra_ui.Id.fromString("examples/m74:split"),
        pni.content,
        .vertical,
        &split_pos,
        split_style,
    );
    _ = try label_mod.label(&ctx, zyntra_ui.Id.fromString("examples/m74:la"), panes.a, "Esq", theme.text, font, false);
    _ = try label_mod.label(&ctx, zyntra_ui.Id.fromString("examples/m74:lb"), panes.b, "Dir", theme.text, font, false);
    const pn_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print(
        "m74 panel draws={d} content_h={d:.1} left_w={d:.1} right_w={d:.1}\n",
        .{ pn_draws, pni.content.h, panes.a.w, panes.b.w },
    );

    // DockLayout (M75, docking passo 2): a árvore de splits pura produz os
    // rects dos painéis e das divisórias; cada painel é desenhado com o
    // chrome de `panel` (passo 1). Estado/layout ficam no chamador.
    const dock_mod = zyntra_ui.dock.layout;
    var dock: zyntra_ui.DockLayout = undefined;
    dock_mod.dockInit(&dock, 0);
    const dock_b = try dock_mod.dockSplit(&dock, 0, .horizontal, 0.5, 1);
    _ = try dock_mod.dockSplit(&dock, dock_b, .vertical, 0.5, 2);
    var dock_panes: [zyntra_ui.DockLayout.max_panes]zyntra_ui.Rect = undefined;
    var dock_divs: [zyntra_ui.DockLayout.max_panes]zyntra_ui.Rect = undefined;
    const pane_ids = [_][]const u8{ "examples/m75:p0", "examples/m75:p1", "examples/m75:p2" };
    const pane_titles = [_][]const u8{ "Esq", "Dir", "Baixo" };
    var dock_collapsed = false;
    ctx.beginFrame();
    const dp_count = try dock_mod.dockPaneRects(&dock, zyntra_ui.Rect.init(600, 20, 260, 200), 8, &dock_panes);
    const dd_count = try dock_mod.dockDividerRects(&dock, zyntra_ui.Rect.init(600, 20, 260, 200), 8, &dock_divs);
    var di: usize = 0;
    while (di < dd_count) : (di += 1) {
        try ctx.draw.rectFilled(ctx.allocator, dock_divs[di], theme.border);
    }
    var pi: usize = 0;
    while (pi < dp_count and pi < pane_ids.len) : (pi += 1) {
        _ = try panel_mod.panel(
            &ctx,
            zyntra_ui.Id.fromString(pane_ids[pi]),
            dock_panes[pi],
            &dock_collapsed,
            .{ .title = pane_titles[pi], .collapsible = false },
            font,
            theme.panelStyle(),
        );
    }
    const dock_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print(
        "m75 dock panes={d} dividers={d} draws={d} pane0_h={d:.1}\n",
        .{ dp_count, dd_count, dock_draws, dock_panes[0].h },
    );

    // DockView (M76, docking passo 3): divisórias arrastáveis ligadas ao
    // DockLayout. `dockView` desenha fundo + faixas, trata o arraste (um
    // `Id` por divisória) e devolve os grupos (nó + abas + rect); o chrome
    // de `panel` é desenhado por cima, na ordem.
    var dv: zyntra_ui.DockLayout = undefined;
    dock_mod.dockInit(&dv, 0);
    const dv_right = try dock_mod.dockSplit(&dv, 0, .vertical, 0.5, 1);
    _ = try dock_mod.dockSplit(&dv, dv_right, .horizontal, 0.5, 2);
    var dv_panes: [zyntra_ui.DockLayout.max_panes]zyntra_ui.DockPaneInfo = undefined;
    const dv_ids = [_][]const u8{ "examples/m76:p0", "examples/m76:p1", "examples/m76:p2" };
    ctx.beginFrame();
    const dvr = try dock_view_mod.dockView(
        &ctx,
        zyntra_ui.Id.fromString("examples/m76:dock"),
        &dv,
        zyntra_ui.Rect.init(600, 460, 260, 200),
        &dv_panes,
        theme.dockStyle(),
        .{},
    );
    var dvi: usize = 0;
    while (dvi < dvr.pane_count and dvi < pane_ids.len) : (dvi += 1) {
        _ = try panel_mod.panel(
            &ctx,
            zyntra_ui.Id.fromString(dv_ids[dvi]),
            dv_panes[dvi].rect,
            &dock_collapsed,
            .{ .title = pane_titles[dvi], .collapsible = false },
            font,
            theme.panelStyle(),
        );
    }
    const dv_draws = ctx.drawCommands().len;
    ctx.endFrame();
    std.debug.print(
        "m76 dockview panes={d} splits={d} draws={d} changed={} pane0_w={d:.1}\n",
        .{ dvr.pane_count, dvr.split_count, dv_draws, dvr.changed, dv_panes[0].rect.w },
    );

    // DockView drop (M77, docking passo 4): o chamador informa qual painel
    // esta arrastando ('dragging'); 'dockView' resolve a zona sob o cursor
    // (borda redivide, centro acopla como aba), desenha o realce e aplica o
    // drop no release. Aqui o gesto e simulado: cursor na borda esquerda do
    // painel 0 e release no frame seguinte.
    var dv2: zyntra_ui.DockLayout = undefined;
    dock_mod.dockInit(&dv2, 0);
    const dv2_right = try dock_mod.dockSplit(&dv2, 0, .vertical, 0.5, 1);
    _ = try dock_mod.dockSplit(&dv2, dv2_right, .horizontal, 0.5, 2);
    const dv2_bounds = zyntra_ui.Rect.init(600, 690, 260, 120);
    const dv2_cursor = zyntra_ui.Vec2.init(dv2_bounds.x + 4, dv2_bounds.y + 60);
    const dv2_id = zyntra_ui.Id.fromString("examples/m77:dock");
    const dv2_opts = zyntra_ui.DockViewOptions{ .dragging = 2 };
    var dv2_panes: [zyntra_ui.DockLayout.max_panes]zyntra_ui.DockPaneInfo = undefined;

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = dv2_cursor } });
    const dv2r1 = try dock_view_mod.dockView(&ctx, dv2_id, &dv2, dv2_bounds, &dv2_panes, theme.dockStyle(), dv2_opts);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = dv2_cursor } });
    const dv2r2 = try dock_view_mod.dockView(&ctx, dv2_id, &dv2, dv2_bounds, &dv2_panes, theme.dockStyle(), dv2_opts);
    ctx.endFrame();
    std.debug.print(
        "m77 drop preview={} dropped={} panes={d} first_w={d:.1}\n",
        .{ dv2r1.drop != null, dv2r2.dropped != null, dv2r2.pane_count, dv2_panes[0].rect.w },
    );

    // Abas acopladas (M78, docking passo 4a): o drop no centro acopla um
    // painel como aba do grupo alvo; 'dockView' devolve os grupos (abas +
    // ativa) e o chamador desenha uma 'tab_bar' por grupo, trocando a aba
    // ativa com 'dockSetActiveTab'. Aqui: dois paineis viram um grupo de 2
    // abas (drop no centro) e um clique na 1a aba troca o painel visivel.
    var dv3: zyntra_ui.DockLayout = undefined;
    dock_mod.dockInit(&dv3, 0);
    _ = try dock_mod.dockSplit(&dv3, 0, .vertical, 0.5, 1);
    const dv3_bounds = zyntra_ui.Rect.init(600, 830, 260, 120);
    const dv3_id = zyntra_ui.Id.fromString("examples/m78:dock");
    const dv3_titles = [_][]const u8{ "Arquivos", "Busca" };
    var dv3_panes: [zyntra_ui.DockLayout.max_panes]zyntra_ui.DockPaneInfo = undefined;
    var dv3_collapsed = false;

    // Frame 1: painel 1 arrastado para o centro do painel 0 (vira aba).
    const dv3_drop = zyntra_ui.Vec2.init(dv3_bounds.x + 63, dv3_bounds.y + 60);
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = dv3_drop } });
    try ctx.pushEvent(.{ .mouse_button = .{ .button = .left, .pressed = false, .pos = dv3_drop } });
    const dv3r1 = try dock_view_mod.dockView(&ctx, dv3_id, &dv3, dv3_bounds, &dv3_panes, theme.dockStyle(), .{ .dragging = 1 });
    ctx.endFrame();

    // Frame 2: um grupo de 2 abas; a barra de abas do grupo ocupa o topo e
    // um clique na 1a aba (titulo "Arquivos") troca a aba ativa.
    ctx.beginFrame();
    const dv3r2 = try dock_view_mod.dockView(&ctx, dv3_id, &dv3, dv3_bounds, &dv3_panes, theme.dockStyle(), .{});
    const dv3_group = dv3_panes[0].group;
    var dv3_labels: [zyntra_ui.DockGroup.max_tabs][]const u8 = undefined;
    for (dv3_group.tabs(), 0..) |p, k| dv3_labels[k] = dv3_titles[p];
    const dv3_bar = zyntra_ui.Rect.init(dv3_panes[0].rect.x, dv3_panes[0].rect.y, dv3_panes[0].rect.w, 22);
    var dv3_active: usize = dv3_group.active;
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(dv3_bar.x + 2, dv3_bar.y + 2) },
    });
    const dv3_tab = try tab_bar_mod.beginTabBar(
        &ctx,
        zyntra_ui.Id.fromString("examples/m78:tabs"),
        dv3_bar,
        dv3_labels[0..dv3_group.tabs().len],
        &dv3_active,
        theme.tabBarStyle(),
    );
    if (dv3_tab.changed) _ = dock_mod.dockSetActiveTab(&dv3, dv3_panes[0].node, dv3_tab.active);
    const dv3_body = zyntra_ui.Rect.init(
        dv3_panes[0].rect.x,
        dv3_panes[0].rect.y + dv3_bar.h,
        dv3_panes[0].rect.w,
        dv3_panes[0].rect.h - dv3_bar.h,
    );
    _ = try panel_mod.panel(
        &ctx,
        zyntra_ui.Id.fromString("examples/m78:body"),
        dv3_body,
        &dv3_collapsed,
        .{ .title = dv3_titles[dock_mod.dockGroup(&dv3, dv3_panes[0].node).?.activePane()], .collapsible = false },
        font,
        theme.panelStyle(),
    );
    ctx.endFrame();
    std.debug.print(
        "m78 tabs drop={} groups={d} tabs={d} changed={} active={d} title={s}\n",
        .{
            dv3r1.dropped != null,
            dv3r2.pane_count,
            dock_mod.dockGroup(&dv3, dv3_panes[0].node).?.count,
            dv3_tab.changed,
            dock_mod.dockGroup(&dv3, dv3_panes[0].node).?.active,
            dv3_titles[dock_mod.dockGroup(&dv3, dv3_panes[0].node).?.activePane()],
        },
    );

    // Serializacao do layout (M79, docking passo 4c): 'dockSerialize' grava
    // um blob versionado e 'dockDeserialize' restaura tudo-ou-nada. Aqui o
    // layout do m78 (um grupo de 2 abas, ativo 0) vai e volta num layout
    // novo, e a versao do formato e lida sem interpretar o corpo.
    var dv4_buf: [zyntra_ui.dock_serial_max_size]u8 = undefined;
    const dv4_n = try zyntra_ui.dockSerialize(&dv3, &dv4_buf);
    const dv4_ver = try zyntra_ui.dockSerialVersion(dv4_buf[0..dv4_n]);
    var dv4: zyntra_ui.DockLayout = undefined;
    const dv4_used = try zyntra_ui.dockDeserialize(&dv4, dv4_buf[0..dv4_n]);
    const dv4_group = dock_mod.dockGroup(&dv4, 0).?;
    std.debug.print(
        "m79 serial bytes={d} used={d} ver={d} groups={d} tabs={d} active={d}\n",
        .{
            dv4_n,
            dv4_used,
            dv4_ver,
            dock_mod.dockLeafCount(&dv4),
            dv4_group.count,
            dv4_group.active,
        },
    );

    // Texto completo (M88): paridade do textarea — undo/redo (Ctrl+Z/Y) e
    // area de transferencia interna (Ctrl+C/X/V) multilinha. Historico e
    // clipboard sao buffers do CHAMADOR (zero alocacao na lib) e o tipo
    // 'Clipboard' e o MESMO de 'text_input'. Aqui: digita "oi" + Enter +
    // "Z" (uma rajada), copia tudo, colapsa no fim e cola (dobra o texto);
    // Ctrl+Z desfaz apenas a colagem.
    const tc_style = theme.textInputStyle();
    const tc_bounds = zyntra_ui.Rect.init(300, 620, 240, 60);
    var tc_buf: [64]u8 = undefined;
    var tc_len: usize = 0;
    var tc_cursor: usize = 0;
    var tc_anchor: usize = 0;
    var tc_scroll: f32 = 0;
    var tc_hist = textarea_mod.TextHistory(8, 64){};
    var tc_clip_mem: [32]u8 = undefined;
    var tc_clip = textarea_mod.Clipboard{ .buf = &tc_clip_mem };
    const tc_id = zyntra_ui.Id.fromString("examples/m88:ta");

    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(304, 624) },
    });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'o' } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'i' } });
    try ctx.pushEvent(.{ .key = .{ .key = .enter, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .text = .{ .codepoint = 'Z' } });
    const tcr1 = try textarea_mod.textAreaClipboard(8, 64, &ctx, tc_id, tc_bounds, &tc_buf, &tc_len, &tc_cursor, &tc_anchor, &tc_scroll, &tc_hist, &tc_clip, font, tc_style);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .a, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .c, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .v, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const tcr2 = try textarea_mod.textAreaClipboard(8, 64, &ctx, tc_id, tc_bounds, &tc_buf, &tc_len, &tc_cursor, &tc_anchor, &tc_scroll, &tc_hist, &tc_clip, font, tc_style);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .z, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const tcr3 = try textarea_mod.textAreaClipboard(8, 64, &ctx, tc_id, tc_bounds, &tc_buf, &tc_len, &tc_cursor, &tc_anchor, &tc_scroll, &tc_hist, &tc_clip, font, tc_style);
    ctx.endFrame();
    std.debug.print(
        "m88 textarea typed={d} clip={d} pasted={} undone={} len={d} lines={d}\n",
        .{
            tcr1.len,
            tc_clip.len,
            tcr2.changed,
            tcr3.undone,
            tc_len,
            textarea_mod.textAreaLineCount(&tc_buf, tc_len),
        },
    );

    // Texto completo (M89): quebra suave no textarea — linhas longas quebram
    // na largura util (sem rolagem horizontal) e Up/Down navegam por linha
    // VISUAL. Aqui: 4 colunas por linha (largura = 4 * advance), caret no
    // fim e a area mostra ~3 linhas visuais (o resto rola).
    const ws_style = theme.textInputStyle();
    const ws_lh = font.lineHeight();
    const ws_bounds = zyntra_ui.Rect.init(16, 700, 8 + 4 * font.advance, 8 + 3 * ws_lh);
    var ws_buf: [64]u8 = undefined;
    const ws_text = "quebra suave de linhas longas";
    @memcpy(ws_buf[0..ws_text.len], ws_text);
    var ws_len: usize = ws_text.len;
    var ws_cursor: usize = ws_text.len;
    var ws_anchor: usize = ws_text.len;
    var ws_scroll: f32 = 0;
    const ws_id = zyntra_ui.Id.fromString("examples/m89:ta");
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = zyntra_ui.Vec2.init(20, 704) },
    });
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{ .ctrl = true } } });
    _ = try textarea_mod.textAreaWrapped(&ctx, ws_id, ws_bounds, &ws_buf, &ws_len, &ws_cursor, &ws_anchor, &ws_scroll, font, ws_style);
    var ws_rows: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        if (cmd == .text) ws_rows += 1;
    }
    ctx.endFrame();
    std.debug.print(
        "m89 wrap rows={d} scroll={d} len={d} logical={d}\n",
        .{ ws_rows, ws_scroll, ws_len, textarea_mod.textAreaLineCount(&ws_buf, ws_len) },
    );

    // Draw moderno (M90): retângulo de cantos arredondados (SDF + AA) no
    // contrato de desenho. Aqui num framebuffer de prova 12x12: canto
    // cortado (fica preto), miolo cheio e uma aresta parcial (50% = 128).
    var rr_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 12, 12);
    defer rr_fb.deinit(allocator);
    rr_fb.clear(zyntra_ui.Color.rgb(0, 0, 0));
    ctx.beginFrame();
    try ctx.draw.rectRounded(allocator, zyntra_ui.Rect.init(1.5, 0, 9, 12), 4.0, zyntra_ui.Color.rgb(255, 0, 0));
    _ = try zyntra_ui.software.raster.render(&rr_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 12, 12));
    ctx.endFrame();
    const rr_corner = rr_fb.get(0, 0);
    const rr_mid = rr_fb.get(6, 6);
    const rr_edge = rr_fb.get(1, 6);
    std.debug.print(
        "m90 rounded corner_r={d} mid={d},{d},{d} edge_r={d}\n",
        .{ rr_corner[0], rr_mid[0], rr_mid[1], rr_mid[2], rr_edge[0] },
    );

    // Draw moderno (M91): gradiente linear no contrato de desenho. Um
    // framebuffer 4x1 com preto→branco no eixo (0,0)→(4,0): t = 1/8..7/8.
    var gr_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 4, 1);
    defer gr_fb.deinit(allocator);
    gr_fb.clear(zyntra_ui.Color.rgb(0, 0, 0));
    ctx.beginFrame();
    try ctx.draw.rectGradient(
        allocator,
        zyntra_ui.Rect.init(0, 0, 4, 1),
        zyntra_ui.Vec2.init(0, 0),
        zyntra_ui.Vec2.init(4, 0),
        zyntra_ui.Color.rgb(0, 0, 0),
        zyntra_ui.Color.rgb(255, 255, 255),
    );
    _ = try zyntra_ui.software.raster.render(&gr_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 4, 1));
    ctx.endFrame();
    std.debug.print(
        "m91 gradient px0={d} px1={d} px2={d} px3={d}\n",
        .{ gr_fb.get(0, 0)[0], gr_fb.get(1, 0)[0], gr_fb.get(2, 0)[0], gr_fb.get(3, 0)[0] },
    );

    // Draw moderno (M92): sombra projetada (silhueta deslocada + falloff
    // linear). Silhueta 8x8, offset (4,0), blur 4: dentro cheio, borda
    // atenuada (159 ≈ 62%) e fora limpo.
    var sh_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 16, 8);
    defer sh_fb.deinit(allocator);
    sh_fb.clear(zyntra_ui.Color.rgb(0, 0, 0));
    ctx.beginFrame();
    try ctx.draw.rectShadow(
        allocator,
        zyntra_ui.Rect.init(0, 0, 8, 8),
        0,
        zyntra_ui.Vec2.init(4, 0),
        4,
        zyntra_ui.Color.rgb(255, 255, 255),
    );
    _ = try zyntra_ui.software.raster.render(&sh_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 16, 8));
    ctx.endFrame();
    std.debug.print(
        "m92 shadow inside={d} edge={d} out={d}\n",
        .{ sh_fb.get(6, 4)[0], sh_fb.get(11, 4)[0], sh_fb.get(14, 4)[0] },
    );

    // Draw moderno (M93): blur de backdrop (box blur separável). Desenha
    // uma borda dura e desfoca: [0,255,255,0] -> [85,170,170,85]. Ordem
    // importa (o comando só afeta o que já foi desenhado).
    var bl_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 4, 1);
    defer bl_fb.deinit(allocator);
    ctx.beginFrame();
    try ctx.draw.clear(allocator, zyntra_ui.Color.rgb(0, 0, 0));
    try ctx.draw.rectFilled(allocator, zyntra_ui.Rect.init(1, 0, 2, 1), zyntra_ui.Color.rgb(255, 255, 255));
    try ctx.draw.backdropBlur(allocator, zyntra_ui.Rect.init(0, 0, 4, 1), 1);
    _ = try zyntra_ui.software.raster.render(&bl_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 4, 1));
    ctx.endFrame();
    std.debug.print(
        "m93 blur px0={d} px1={d} px2={d} px3={d}\n",
        .{ bl_fb.get(0, 0)[0], bl_fb.get(1, 0)[0], bl_fb.get(2, 0)[0], bl_fb.get(3, 0)[0] },
    );

    // Grafo de nós (M94): grafo interativo sobre `graph/view` (pan/zoom +
    // nós/arestas + hit-test). Aqui um nó 40x32 em (8,8) com faixa de
    // título, 1 entrada e 1 saída, renderizado num framebuffer 96x64 para
    // conferir pixels exatos e a estrutura dos comandos (clip em `bounds`,
    // faixa de título, pino e texto).
    var gv_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 96, 64);
    defer gv_fb.deinit(allocator);
    gv_fb.clear(zyntra_ui.Color.rgb(255, 255, 255));
    const gv_style = zyntra_ui.GraphStyle{
        .bg = zyntra_ui.Color.rgb(20, 20, 20),
        .grid = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .grid_target_px = 16,
        .node_bg = zyntra_ui.Color.rgb(200, 40, 40),
        .node_header = zyntra_ui.Color.rgb(40, 200, 40),
        .node_border = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .node_selected = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .node_radius = 0,
        .header_height = 12,
        .title = zyntra_ui.Color.rgb(255, 255, 255),
        .title_pad = 4,
        .edge = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .edge_width = 1,
        .port = zyntra_ui.Color.rgb(40, 40, 220),
        .port_radius = 3,
    };
    var gv_nodes = [_]zyntra_ui.GraphNode{
        .{
            .pos = .{ .x = 8, .y = 8 },
            .size = .{ .x = 40, .y = 32 },
            .title = "n",
            .inputs = 1,
            .outputs = 1,
        },
        .{
            .pos = .{ .x = 72, .y = 8 },
            .size = .{ .x = 16, .y = 32 },
            .inputs = 1,
        },
    };
    const gv_edges = [_]zyntra_ui.GraphEdge{.{ .from = 0, .to = 1 }};
    var gv_state = zyntra_ui.GraphViewState{};
    ctx.beginFrame();
    _ = try zyntra_ui.widgets.graph_view.graphView(
        &ctx,
        zyntra_ui.Id.fromString("examples/m94:graph"),
        zyntra_ui.Rect.init(0, 0, 96, 64),
        &gv_nodes,
        &gv_edges,
        &gv_state,
        .{},
        gv_style,
        font,
    );
    var gv_cmds: usize = 0;
    var gv_lines: usize = 0;
    var gv_texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        gv_cmds += 1;
        if (cmd == .line) gv_lines += 1;
        if (cmd == .text) gv_texts += 1;
    }
    _ = try zyntra_ui.software.raster.render(&gv_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 96, 64));
    ctx.endFrame();
    // Corpo (28,24), faixa de título (28,14), pino de entrada (8,24) e
    // fundo (90,58); a aresta vira `edge_segments` (12) comandos `.line`.
    std.debug.print(
        "m94 graph body={d} header={d} port={d} bg={d} cmds={d} lines={d} texts={d}\n",
        .{
            gv_fb.get(28, 24)[0],
            gv_fb.get(28, 14)[1],
            gv_fb.get(8, 24)[2],
            gv_fb.get(90, 58)[0],
            gv_cmds,
            gv_lines,
            gv_texts,
        },
    );

    // Timeline (M95): trilhas + chaves + régua + playhead sobre
    // `timeline/view` (scrub/pan/zoom/arraste de chave). Renderizada num
    // framebuffer 200x64 para conferir pixels exatos e a estrutura dos
    // comandos (clip em `bounds`, linhas de grade/marca, chaves em losango
    // e alça do playhead).
    var tl_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 200, 64);
    defer tl_fb.deinit(allocator);
    tl_fb.clear(zyntra_ui.Color.rgb(255, 255, 255));
    const tl_style = zyntra_ui.TimelineStyle{
        .bg = zyntra_ui.Color.rgb(20, 20, 20),
        .ruler_bg = zyntra_ui.Color.rgb(50, 50, 60),
        .ruler_height = 16,
        .tick = zyntra_ui.Color.rgb(120, 125, 140),
        .tick_label = zyntra_ui.Color.rgb(220, 220, 220),
        .min_tick_px = 60,
        .track_bg = zyntra_ui.Color.rgb(35, 35, 45),
        .track_alt = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .name_width = 60,
        .names_bg = zyntra_ui.Color.rgb(28, 28, 34),
        .track_name = zyntra_ui.Color.rgb(230, 230, 230),
        .name_pad = 6,
        .separator = zyntra_ui.Color.rgb(70, 70, 80),
        .row_height = 20,
        .key = zyntra_ui.Color.rgb(255, 190, 70),
        .key_selected = zyntra_ui.Color.rgb(255, 255, 255),
        .key_size = 6,
        .key_line_width = 1.5,
        .playhead = zyntra_ui.Color.rgb(255, 60, 60),
        .playhead_width = 2,
    };
    // Área de tempo: 140 px a 14 px/s ⇒ janela de 10 s = duração; régua em
    // passos de 5 s (t = 0, 5, 10 ⇒ x = 60, 130, 200).
    var tl_keys0 = [_]zyntra_ui.TimelineKeyframe{ .{ .t = 2 }, .{ .t = 3.5 }, .{ .t = 8 } };
    var tl_tracks = [_]zyntra_ui.TimelineTrack{
        .{ .name = "pos", .keys = &tl_keys0 },
        .{ .name = "rot" },
    };
    var tl_state = zyntra_ui.TimelineViewState{
        .duration = 10,
        .playhead = 5,
        .transform = .{ .pps = 14 },
    };
    ctx.beginFrame();
    _ = try zyntra_ui.widgets.timeline_view.timelineView(
        &ctx,
        zyntra_ui.Id.fromString("examples/m95:timeline"),
        zyntra_ui.Rect.init(0, 0, 200, 64),
        &tl_tracks,
        &tl_state,
        .{},
        tl_style,
        font,
    );
    var tl_cmds: usize = 0;
    var tl_lines: usize = 0;
    var tl_texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        tl_cmds += 1;
        if (cmd == .line) tl_lines += 1;
        if (cmd == .text) tl_texts += 1;
    }
    _ = try zyntra_ui.software.raster.render(&tl_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 200, 64));
    ctx.endFrame();
    // Fundo (150,60), régua (90,8), linha de trilha (90,26), coluna de
    // nomes (5,60) e alça do playhead (130,5). Estrutura: 3 grades + 3
    // marcas + 1 separador + 3 chaves × 4 + playhead = 20 `.line`; 2 nomes
    // + 3 rótulos = 5 `.text`.
    std.debug.print(
        "m95 timeline bg={d} ruler={d} row={d} name={d} handle={d} cmds={d} lines={d} texts={d}\n",
        .{
            tl_fb.get(150, 60)[0],
            tl_fb.get(90, 8)[0],
            tl_fb.get(90, 26)[0],
            tl_fb.get(5, 60)[0],
            tl_fb.get(130, 5)[0],
            tl_cmds,
            tl_lines,
            tl_texts,
        },
    );

    // Property inspector (M96): lista nome/valor sobre `inspector/view`,
    // com linha ativa, realce do editor em hover e editores de bool,
    // real e escolha. Framebuffer 200x64 com 3 linhas de 20 px (coluna de
    // nomes 80, recuo do valor 6 ⇒ editor em x = 86) para conferir pixels
    // exatos (fundos, marca do bool e realce do editor) e a estrutura.
    var insp_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 200, 64);
    defer insp_fb.deinit(allocator);
    insp_fb.clear(zyntra_ui.Color.rgb(255, 255, 255));
    const insp_style = zyntra_ui.InspectorStyle{
        .bg = zyntra_ui.Color.rgb(20, 20, 20),
        .row_bg = zyntra_ui.Color.rgb(40, 40, 48),
        .row_alt = zyntra_ui.Color.rgb(30, 30, 36),
        .row_active = zyntra_ui.Color.rgb(60, 84, 120),
        .editor_bg = zyntra_ui.Color.rgb(24, 24, 30),
        .separator = zyntra_ui.Color.rgb(70, 70, 80),
        .name = zyntra_ui.Color.rgb(230, 230, 230),
        .name_width = 80,
        .name_pad = 6,
        .value_pad = 6,
        .row_height = 20,
        .value = zyntra_ui.Color.rgb(255, 255, 255),
        .value_readonly = zyntra_ui.Color.rgb(150, 150, 150),
        .check_size = 12,
        .check_bg = zyntra_ui.Color.rgb(20, 20, 20),
        .check_border = zyntra_ui.Color.rgb(200, 200, 200),
        .check_border_width = 1,
        .check_mark = zyntra_ui.Color.rgb(255, 200, 0),
    };
    var insp_visible = true;
    var insp_scale: f32 = 1.5;
    var insp_mode: u32 = 1;
    const insp_options = [_][]const u8{ "A", "B", "C" };
    const insp_props = [_]zyntra_ui.InspectorProperty{
        .{ .name = "visible", .value = .{ .boolean = &insp_visible } },
        .{ .name = "scale", .value = .{ .real = &insp_scale }, .decimals = 1 },
        .{
            .name = "mode",
            .value = .{
                .choice = .{ .index = &insp_mode, .options = &insp_options },
            },
        },
    };
    var insp_state = zyntra_ui.InspectorViewState{ .active = 2 };
    ctx.beginFrame();
    // Hover na linha 1 (valor) ⇒ realce do editor na coluna de valores.
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = .{ .x = 120, .y = 30 } } });
    _ = try zyntra_ui.widgets.inspector_view.inspectorView(
        &ctx,
        zyntra_ui.Id.fromString("examples/m96:inspector"),
        zyntra_ui.Rect.init(0, 0, 200, 64),
        &insp_props,
        &insp_state,
        .{},
        insp_style,
        font,
    );
    var insp_cmds: usize = 0;
    var insp_lines: usize = 0;
    var insp_texts: usize = 0;
    for (ctx.drawCommands()) |cmd| {
        insp_cmds += 1;
        if (cmd == .line) insp_lines += 1;
        if (cmd == .text) insp_texts += 1;
    }
    _ = try zyntra_ui.software.raster.render(&insp_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 200, 64));
    ctx.endFrame();
    // Fundo (150,60), linha 0 (10,10), linha alt 1 (10,30), linha ativa 2
    // (10,50), marca do bool (92,10) e realce do editor (120,30).
    // Estrutura: 2 clips + 8 `rect_filled` + 1 `rect_outline` + 2
    // separadores `.line` + 5 `.text`.
    std.debug.print(
        "m96 inspector bg={d} row={d} alt={d} active={d} mark={d} editor={d} cmds={d} lines={d} texts={d}\n",
        .{
            insp_fb.get(150, 60)[0],
            insp_fb.get(10, 10)[0],
            insp_fb.get(10, 30)[0],
            insp_fb.get(10, 50)[0],
            insp_fb.get(92, 10)[0],
            insp_fb.get(120, 30)[0],
            insp_cmds,
            insp_lines,
            insp_texts,
        },
    );

    // Arrastar-e-soltar (M97): serviço `dnd` (no `Context`) + fantasma do
    // arraste sobre `widgets/drag_ghost`. Duas zonas de solto (A e B) e um
    // "chip" (fonte). Frame 1 só alimenta o serviço (press + `begin`);
    // frame 2 arrasta (chip realçado, zona B quente e fantasma sob o
    // cursor); frame 3 solta (a zona B recebe `.dropped`). Framebuffer
    // 200x64, zonas 96 de largura com 8 px de vão, chip 40x16 em (8,8) e
    // cursor do arraste em (120,32).
    var dnd_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 200, 64);
    defer dnd_fb.deinit(allocator);
    const dnd_bg = zyntra_ui.Color.rgb(20, 20, 20);
    const dnd_zone_a = zyntra_ui.Rect.init(0, 0, 96, 64);
    const dnd_zone_b = zyntra_ui.Rect.init(104, 0, 96, 64);
    const dnd_chip = zyntra_ui.Rect.init(8, 8, 40, 16);
    const dnd_zone_base = zyntra_ui.Color.rgb(30, 30, 36);
    const dnd_zone_hot = zyntra_ui.Color.rgb(60, 84, 120);
    const dnd_zone_drop = zyntra_ui.Color.rgb(70, 150, 90);
    const dnd_chip_base = zyntra_ui.Color.rgb(90, 90, 100);
    const dnd_chip_drag = zyntra_ui.Color.rgb(140, 140, 160);
    const dnd_ghost_style = zyntra_ui.DragGhostStyle{
        .bg = zyntra_ui.Color.rgb(240, 240, 240),
        .border = zyntra_ui.Color.rgb(20, 20, 20),
        .border_width = 1,
        .radius = 3,
        .shadow = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .text = zyntra_ui.Color.rgb(16, 16, 16),
        .pad = 6,
        .offset = zyntra_ui.Vec2.init(10, 10),
        .min_width = 48,
    };
    const dnd_chip_id = zyntra_ui.Id.fromString("examples/m97:chip");
    const dnd_zone_a_id = zyntra_ui.Id.fromString("examples/m97:zoneA");
    const dnd_zone_b_id = zyntra_ui.Id.fromString("examples/m97:zoneB");

    // Frame 1: press no chip ⇒ a fonte inicia o arraste.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = .{ .x = 20, .y = 16 },
    } });
    try zyntra_ui.dnd.service.begin(&ctx, dnd_chip_id, .{
        .kind = "chip",
        .label = "chip",
    });
    ctx.endFrame();

    // Frame 2 (arraste: move + release no mesmo lote; o arraste segue
    // vivo até o `beginFrame` seguinte) e frame 3 (solto já resolvido,
    // em que a zona B recebe `.dropped`) desenham o mesmo, mudando só a
    // entrada e o verdicto dos alvos.
    var dnd_drag_px = [_]u8{ 0, 0, 0, 0, 0 };
    var dnd_drop_px: u8 = 0;
    var dnd_cmds: usize = 0;
    var dnd_texts: usize = 0;
    var dnd_hover_b = false;
    var dnd_drop_b = false;
    var dnd_frame: usize = 0;
    while (dnd_frame < 2) : (dnd_frame += 1) {
        ctx.beginFrame();
        if (dnd_frame == 0) {
            try ctx.pushEvent(.{ .mouse_move = .{ .pos = .{ .x = 120, .y = 32 } } });
            try ctx.pushEvent(.{ .mouse_button = .{
                .button = .left,
                .pressed = false,
                .pos = .{ .x = 120, .y = 32 },
            } });
        }
        dnd_fb.clear(zyntra_ui.Color.rgb(255, 255, 255));
        try ctx.draw.rectFilled(allocator, zyntra_ui.Rect.init(0, 0, 200, 64), dnd_bg);
        const dnd_va = zyntra_ui.dnd.service.accept(&ctx, dnd_zone_a_id, dnd_zone_a);
        const dnd_vb = zyntra_ui.dnd.service.accept(&ctx, dnd_zone_b_id, dnd_zone_b);
        const dnd_col_a = switch (dnd_va) {
            .none => dnd_zone_base,
            .hover => dnd_zone_hot,
            .dropped => dnd_zone_drop,
        };
        const dnd_col_b = switch (dnd_vb) {
            .none => dnd_zone_base,
            .hover => dnd_zone_hot,
            .dropped => dnd_zone_drop,
        };
        try ctx.draw.rectFilled(allocator, dnd_zone_a, dnd_col_a);
        try ctx.draw.rectFilled(allocator, dnd_zone_b, dnd_col_b);
        const dnd_src = zyntra_ui.dnd.service.dragSource(&ctx);
        const dnd_dragging = dnd_src != null and dnd_src.? == dnd_chip_id;
        try ctx.draw.rectFilled(
            allocator,
            dnd_chip,
            if (dnd_dragging) dnd_chip_drag else dnd_chip_base,
        );
        _ = try zyntra_ui.widgets.drag_ghost.dragGhost(&ctx, dnd_ghost_style, font);
        if (dnd_frame == 0) {
            var cmds: usize = 0;
            var texts: usize = 0;
            for (ctx.drawCommands()) |cmd| {
                cmds += 1;
                if (cmd == .text) texts += 1;
            }
            _ = try zyntra_ui.software.raster.render(&dnd_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 200, 64));
            dnd_cmds = cmds;
            dnd_texts = texts;
            const dnd_hover = zyntra_ui.dnd.service.hoverTarget(&ctx);
            dnd_hover_b = dnd_hover != null and dnd_hover.? == dnd_zone_b_id;
            // Chip arrastando (10,12), zona A base (10,50), zona B quente
            // (110,10), fantasma (135,50) e a vizinha quente à esquerda
            // dele (125,50).
            dnd_drag_px = .{
                dnd_fb.get(10, 12)[0],
                dnd_fb.get(10, 50)[0],
                dnd_fb.get(110, 10)[0],
                dnd_fb.get(135, 50)[0],
                dnd_fb.get(125, 50)[0],
            };
        } else {
            _ = try zyntra_ui.software.raster.render(&dnd_fb, ctx.drawCommands(), zyntra_ui.Rect.init(0, 0, 200, 64));
            const dnd_drop = zyntra_ui.dnd.service.lastDrop(&ctx);
            dnd_drop_b = dnd_drop != null and dnd_drop.?.target != null and
                dnd_drop.?.target.? == dnd_zone_b_id;
            // Zona B entregue e sem fantasma: mesmo pixel (135,50), agora
            // verde de solto.
            dnd_drop_px = dnd_fb.get(135, 50)[0];
        }
        ctx.endFrame();
    }
    // Estrutura do frame de arraste: 5 `rect_filled` (fundo, 2 zonas,
    // chip e caixa do fantasma) + 1 `rect_outline` (borda do fantasma)
    // + 1 `.text` (rótulo).
    std.debug.print(
        "m97 dnd chip={d} zone={d} hot={d} ghost={d} edge={d} drop={d} hover_b={} drop_b={} cmds={d} texts={d}\n",
        .{
            dnd_drag_px[0],
            dnd_drag_px[1],
            dnd_drag_px[2],
            dnd_drag_px[3],
            dnd_drag_px[4],
            dnd_drop_px,
            dnd_hover_b,
            dnd_drop_b,
            dnd_cmds,
            dnd_texts,
        },
    );

    // Dirty rect por frame (M98): `ctx.mark_dirty` acumula a região que
    // mudou e `software.raster.renderRegion` repinta SÓ ela, preservando
    // o resto do framebuffer (que segue com o frame anterior). Framebuffer
    // 120x24 com dois "cards": A em (8,8,40,16) e B em (64,8,40,16).
    // Frame 1 (índice 0): tudo sujo (viewport) ⇒ repintura integral.
    // Frame 2 (índice 1): só A mudou (hover) ⇒ região = rect de A, B fica
    // de fora (cullado) e o vão permanece com o fundo do frame anterior.
    // Frame 3 (índice 2): nada sujo ⇒ nenhuma repintura (pixels intactos).
    var dr_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 120, 24);
    defer dr_fb.deinit(allocator);
    const dr_vp = zyntra_ui.Rect.init(0, 0, 120, 24);
    const dr_bg = zyntra_ui.Color.rgb(24, 24, 28);
    const dr_card_a = zyntra_ui.Rect.init(8, 8, 40, 16);
    const dr_card_b = zyntra_ui.Rect.init(64, 8, 40, 16);
    const dr_card_base = zyntra_ui.Color.rgb(90, 90, 100);
    const dr_card_hot = zyntra_ui.Color.rgb(140, 160, 200);

    var dr_base_a: u8 = 0;
    var dr_base_b: u8 = 0;
    var dr_hot_a: u8 = 0;
    var dr_keep_b: u8 = 0;
    var dr_gutter: u8 = 0;
    var dr_drawn: u32 = 0;
    var dr_culled: u32 = 0;
    var dr_region = zyntra_ui.Rect.init(0, 0, 0, 0);
    var dr_idle_ok = false;
    var dr_frame: usize = 0;
    while (dr_frame < 3) : (dr_frame += 1) {
        ctx.beginFrame();
        try ctx.draw.clear(allocator, dr_bg);
        try ctx.draw.rectFilled(
            allocator,
            dr_card_a,
            if (dr_frame == 1) dr_card_hot else dr_card_base,
        );
        try ctx.draw.rectFilled(allocator, dr_card_b, dr_card_base);
        // Só o frame 2 marca sujeira; o frame 1 repinta o viewport inteiro.
        if (dr_frame == 0) ctx.mark_dirty(dr_vp);
        if (dr_frame == 1) ctx.mark_dirty(dr_card_a);
        const dr_dirty = ctx.dirty_rect;
        if (!dr_dirty.isEmpty()) {
            const dr_stats = try zyntra_ui.software.raster.renderRegion(
                &dr_fb,
                ctx.drawCommands(),
                dr_vp,
                dr_dirty,
            );
            dr_drawn = dr_stats.drawn;
            dr_culled = dr_stats.culled;
        }
        if (dr_frame == 0) {
            dr_base_a = dr_fb.get(10, 12)[0];
            dr_base_b = dr_fb.get(70, 12)[0];
        } else if (dr_frame == 1) {
            dr_region = dr_dirty;
            dr_hot_a = dr_fb.get(10, 12)[0];
            dr_keep_b = dr_fb.get(70, 12)[0]; // preservado (B cullado)
            dr_gutter = dr_fb.get(56, 12)[0]; // fundo do frame anterior
        } else {
            // Frame ocioso: nada sujo, nenhuma repintura e pixels intactos.
            dr_idle_ok = dr_dirty.isEmpty() and
                dr_fb.get(10, 12)[0] == dr_card_hot.r and
                dr_fb.get(70, 12)[0] == dr_card_base.r;
        }
        ctx.endFrame();
    }
    // Frame 2: `clear` parcial + A = 2 executados; B fora da região = 1
    // cullado; região suja == rect de A (8,8,40,16).
    std.debug.print(
        "m98 dirty base_a={d} base_b={d} hot_a={d} keep_b={d} gutter={d} drawn={d} culled={d} region={d:.1},{d:.1} {d:.1}x{d:.1} idle={}\n",
        .{
            dr_base_a,
            dr_base_b,
            dr_hot_a,
            dr_keep_b,
            dr_gutter,
            dr_drawn,
            dr_culled,
            dr_region.x,
            dr_region.y,
            dr_region.w,
            dr_region.h,
            dr_idle_ok,
        },
    );

    // Widgets alimentam o dirty rect sozinhos (M99): `mark_hot` marca os
    // bounds quando o estado de interação (hover/press/valor) pode ter
    // mudado a aparência — inclusive na SAÍDA do estado, via registro
    // quente do frame anterior. Dois botões (A em (8,8,40,20), B em
    // (64,8,40,20)) sobre fundo; a aplicação NÃO marca nada depois do
    // primeiro frame. Frame 1 (índice 0): mouse no vão, tudo frio, região
    // = viewport (primeiro desenho). Frame 2 (índice 1): mouse entra em A
    // ⇒ região = bounds de A, só A repinta em hover. Frame 3 (índice 2):
    // mouse sai ⇒ região = bounds de A de novo, apagando o realce.
    var hot_fb = try zyntra_ui.SoftwareFramebuffer.init(allocator, 120, 40);
    defer hot_fb.deinit(allocator);
    const hot_vp = zyntra_ui.Rect.init(0, 0, 120, 40);
    const hot_bg = zyntra_ui.Color.rgb(24, 24, 28);
    const hot_a_rect = zyntra_ui.Rect.init(8, 8, 40, 20);
    const hot_b_rect = zyntra_ui.Rect.init(64, 8, 40, 20);
    const hot_style = zyntra_ui.ButtonStyle{
        .bg = zyntra_ui.Color.rgb(70, 70, 80),
        .bg_hover = zyntra_ui.Color.rgb(120, 160, 220),
        .bg_pressed = zyntra_ui.Color.rgb(40, 180, 90),
        .border = zyntra_ui.Color.rgb(200, 200, 200),
        .border_width = 1,
        .radius = 0,
    };
    const hot_a_id = zyntra_ui.Id.fromString("examples/m99:a");
    const hot_b_id = zyntra_ui.Id.fromString("examples/m99:b");

    var hot_cold_a: u8 = 0;
    var hot_cold_b: u8 = 0;
    var hot_hover_a: u8 = 0;
    var hot_keep_b: u8 = 0;
    var hot_out_a: u8 = 0;
    var hot_drawn: u32 = 0;
    var hot_culled: u32 = 0;
    var hot_region = zyntra_ui.Rect.init(0, 0, 0, 0);
    var hot_frame: usize = 0;
    while (hot_frame < 3) : (hot_frame += 1) {
        ctx.beginFrame();
        if (hot_frame == 0) {
            try ctx.pushEvent(.{ .mouse_move = .{ .pos = .{ .x = 56, .y = 32 } } });
        } else if (hot_frame == 1) {
            try ctx.pushEvent(.{ .mouse_move = .{ .pos = .{ .x = 20, .y = 18 } } });
        } else {
            try ctx.pushEvent(.{ .mouse_move = .{ .pos = .{ .x = 56, .y = 32 } } });
        }
        try ctx.draw.rectFilled(allocator, hot_vp, hot_bg);
        _ = try button_mod.button(&ctx, hot_a_id, hot_a_rect, hot_style);
        _ = try button_mod.button(&ctx, hot_b_id, hot_b_rect, hot_style);
        if (hot_frame == 0) ctx.mark_dirty(hot_vp); // 1º frame: tudo sujo
        const hot_dirty = ctx.dirty_rect;
        if (!hot_dirty.isEmpty()) {
            const hot_stats = try zyntra_ui.software.raster.renderRegion(
                &hot_fb,
                ctx.drawCommands(),
                hot_vp,
                hot_dirty,
            );
            hot_drawn = hot_stats.drawn;
            hot_culled = hot_stats.culled;
        }
        if (hot_frame == 0) {
            hot_cold_a = hot_fb.get(20, 18)[0];
            hot_cold_b = hot_fb.get(80, 18)[0];
        } else if (hot_frame == 1) {
            hot_hover_a = hot_fb.get(20, 18)[0];
            hot_keep_b = hot_fb.get(80, 18)[0]; // B cullado: preservado
        } else {
            hot_region = hot_dirty; // saída do hover, sem mark_dirty do app
            hot_out_a = hot_fb.get(20, 18)[0];
        }
        ctx.endFrame();
    }
    // Frame 2: 3 comandos desenhados (fundo, fill e borda de A) e 2
    // cullados (fill e borda de B, fora da região); região == bounds de A.
    std.debug.print(
        "m99 hot cold_a={d} cold_b={d} hover_a={d} keep_b={d} out_a={d} drawn={d} culled={d} region={d:.1},{d:.1} {d:.1}x{d:.1}\n",
        .{
            hot_cold_a,
            hot_cold_b,
            hot_hover_a,
            hot_keep_b,
            hot_out_a,
            hot_drawn,
            hot_culled,
            hot_region.x,
            hot_region.y,
            hot_region.w,
            hot_region.h,
        },
    );

    // Multi-janela (M100): o registro puro organiza identidade, geometria
    // no desktop, ordem de empilhamento (z-order) e foco. Sem framebuffer
    // e sem `Context`: as perguntas do host (quem está sob o cursor, quem
    // recebe foco, em que ordem desenhar, coordenadas locais) saem do
    // modelo. A em (10,10,100,80), B em (60,40,100,80) e C em (0,0,30,20)
    // sobrepostas; a última adicionada fica no topo.
    var mw: zyntra_ui.WindowRegistry = .{};
    const mw_a_id = zyntra_ui.Id.fromString("examples/m100:a");
    const mw_b_id = zyntra_ui.Id.fromString("examples/m100:b");
    const mw_c_id = zyntra_ui.Id.fromString("examples/m100:c");
    const mw_a = zyntra_ui.Rect.init(10, 10, 100, 80); // 10..110 x 10..90
    const mw_b = zyntra_ui.Rect.init(60, 40, 100, 80); // 60..160 x 40..120
    try mw.add(mw_a_id, mw_a);
    try mw.add(mw_b_id, mw_b);
    try mw.add(mw_c_id, zyntra_ui.Rect.init(0, 0, 30, 20)); // 0..30 x 0..20
    const mw_count = mw.count();

    // Ponto na sobreposição de A e B: o hit-test devolve a de CIMA (B) e
    // o clique a traz para frente + dá foco; clique no vazio não muda
    // ordem nem foco.
    const mw_hit_b = mw.windowAt(.{ .x = 70, .y = 50 }) == mw_b_id;
    const mw_click_b = mw.activateAt(.{ .x = 70, .y = 50 }) == mw_b_id;
    const mw_b_top = mw.indexOf(mw_b_id).? + 1 == mw.count();
    const mw_click_void = mw.activateAt(.{ .x = 300, .y = 300 }) == null;
    // Desktop → local: A começa em (10,10).
    const mw_local = mw.toLocal(mw_a_id, .{ .x = 20, .y = 15 }).?;

    // Esconder a janela ativa: sai do hit-test mas mantém o foco
    // (visibilidade != foco); o clique passa a atingir A, que sobe.
    _ = mw.setVisible(mw_b_id, false);
    const mw_hidden_keeps_focus = mw.activeId() == mw_b_id;
    const mw_hit_a = mw.windowAt(.{ .x = 70, .y = 50 }) == mw_a_id;
    const mw_click_a = mw.activateAt(.{ .x = 70, .y = 50 }) == mw_a_id;

    // Array fixo: cheio recusa (`TooManyWindows`) e `clear` devolve espaço.
    var mw_cap: zyntra_ui.WindowRegistry = .{};
    var mw_i: u32 = 0;
    while (mw_i < zyntra_ui.WindowRegistry.max_windows) : (mw_i += 1) {
        try mw_cap.add(zyntra_ui.Id.fromU64(mw_i + 1), mw_a);
    }
    const mw_full = mw_cap.isFull();
    var mw_overflow = false;
    mw_cap.add(zyntra_ui.Id.fromU64(1000), mw_a) catch |err| {
        mw_overflow = err == error.TooManyWindows;
    };
    mw_cap.clear();
    const mw_cleared = mw_cap.count();

    // Remover a janela ativa zera o foco; as outras mantêm a ordem.
    const mw_removed = mw.remove(mw_a_id);
    const mw_active_null = mw.activeId() == null;
    const mw_left = mw.count();

    std.debug.print(
        "m100 win count={d} hit_b={} click_b={} b_top={} click_void={} local={d:.1},{d:.1} hidden_keeps_focus={} hit_a={} click_a={} full={} overflow={} cleared={d} removed={} active_null={} left={d}\n",
        .{
            mw_count,
            mw_hit_b,
            mw_click_b,
            mw_b_top,
            mw_click_void,
            mw_local.x,
            mw_local.y,
            mw_hidden_keeps_focus,
            mw_hit_a,
            mw_click_a,
            mw_full,
            mw_overflow,
            mw_cleared,
            mw_removed,
            mw_active_null,
            mw_left,
        },
    );

    // Roteamento multi-janela (M101): cada janela vincula o `Context` que
    // a desenha/processa e o host entrega os eventos no espaço LOCAL da
    // janela certa. A em (0,0,120,60) e B em (80,30,120,60) — B por cima
    // — mais D em (160,0,40,40) SEM contexto (nunca recebe nada).
    var wr_reg: zyntra_ui.WindowRegistry = .{};
    var wr_router: zyntra_ui.WindowRouter = .{};
    var wr_ctx_a = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 120, 60),
    });
    defer wr_ctx_a.deinit();
    var wr_ctx_b = try zyntra_ui.Context.init(allocator, .{
        .viewport = zyntra_ui.Rect.init(0, 0, 120, 60),
    });
    defer wr_ctx_b.deinit();
    const wr_a_id = zyntra_ui.Id.fromString("examples/m101:a");
    const wr_b_id = zyntra_ui.Id.fromString("examples/m101:b");
    const wr_d_id = zyntra_ui.Id.fromString("examples/m101:d");
    try wr_reg.add(wr_a_id, zyntra_ui.Rect.init(0, 0, 120, 60));
    try wr_reg.add(wr_b_id, zyntra_ui.Rect.init(80, 30, 120, 60));
    try wr_reg.add(wr_d_id, zyntra_ui.Rect.init(160, 0, 40, 40));
    _ = wr_reg.bind(wr_a_id, &wr_ctx_a);
    _ = wr_reg.bind(wr_b_id, &wr_ctx_b);

    // Press na sobreposição: o host sobe/foca a janela sob o cursor
    // (`focusAt`) e roteia o press para ela — B recebe já em coordenadas
    // LOCAIS (20,10).
    const wr_focus = zyntra_ui.window.input.focusAt(&wr_reg, .{ .x = 100, .y = 40 });
    const wr_focus_b = wr_focus != null and wr_focus.? == wr_b_id;
    const wr_press = try zyntra_ui.window.input.pushButton(
        &wr_router,
        &wr_reg,
        .left,
        true,
        .{ .x = 100, .y = 40 },
    );
    const wr_cap_b = wr_router.isCapturing() and wr_router.press_window.? == wr_b_id;

    // Arraste para fora de B (região só de A): a captura no nível de
    // janela mantém tudo em B, com coordenadas locais negativas — é o que
    // mantém um arraste de widget vivo ao sair dos bounds.
    _ = try zyntra_ui.window.input.pushMouseMove(&wr_router, &wr_reg, .{ .x = 10, .y = 10 });
    const wr_drag_local = wr_ctx_b.mouse_pos orelse zyntra_ui.Vec2.init(0, 0);
    // Release fora de B: continua indo para a captura, que se encerra.
    const wr_release = try zyntra_ui.window.input.pushButton(
        &wr_router,
        &wr_reg,
        .left,
        false,
        .{ .x = 10, .y = 10 },
    );

    // Sem captura, roda e movimento seguem o CURSOR: sobre A, vão para A.
    const wr_wheel_a = try zyntra_ui.window.input.pushWheel(&wr_reg, 0, 3, .{ .x = 20, .y = 20 });
    const wr_move_a = try zyntra_ui.window.input.pushMouseMove(
        &wr_router,
        &wr_reg,
        .{ .x = 20, .y = 20 },
    );
    const wr_a_space = wr_ctx_a.mouse_pos orelse zyntra_ui.Vec2.init(0, 0);
    // Sobre D (topo, sem contexto) nada é entregue: a janela do topo manda.
    const wr_top_no_ctx = !(try zyntra_ui.window.input.pushMouseMove(
        &wr_router,
        &wr_reg,
        .{ .x = 170, .y = 20 },
    ));

    // Teclado vai para a janela ATIVA (B, focada no press).
    const wr_key_b = try zyntra_ui.window.input.pushKey(&wr_reg, .enter, true, .{});

    std.debug.print(
        "m101 route focus_b={} press={} cap_b={} release={} drag_local={d:.1},{d:.1} a_space={d:.1},{d:.1} wheel_a={} move_a={} top_no_ctx={} key_b={} a_events={d} b_events={d} capture={}\n",
        .{
            wr_focus_b,
            wr_press,
            wr_cap_b,
            wr_release,
            wr_drag_local.x,
            wr_drag_local.y,
            wr_a_space.x,
            wr_a_space.y,
            wr_wheel_a,
            wr_move_a,
            wr_top_no_ctx,
            wr_key_b,
            wr_ctx_a.pendingEvents().len,
            wr_ctx_b.pendingEvents().len,
            wr_router.isCapturing(),
        },
    );
}
