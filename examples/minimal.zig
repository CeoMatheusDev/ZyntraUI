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
}
