//! ZyntraUI — área de docking interativa (widgets/dock_view).
//!
//! Modelo M76 (Docking, passo 3): liga o modelo puro `dock/layout` à
//! interação. Desenha o fundo opcional da área e torna **cada divisória
//! arrastável** (uma por split), atualizando o ratio correspondente via
//! `dockSetRatio`. Devolve, em pré-ordem, os rects dos painéis para o
//! chamador desenhar o chrome (`widgets/panel`) por cima.
//!
//! M77 (Docking, passo 4) acrescenta o **drop de painéis**: o chamador
//! informa qual painel está arrastando (`DockViewOptions.dragging`) e
//! `dockView` resolve a zona sob o cursor (borda ⇒ redivide, centro ⇒
//! acopla como aba do grupo alvo), desenha o realce e aplica o drop no
//! release
//! (`dockApplyDrop`), devolvendo `dropped` para o chamador limpar o
//! estado de arraste. O gesto de origem (ex.: press no cabeçalho de um
//! `widgets/panel`) é do chamador.
//!
//! Ordem no frame: `dockView` desenha fundo + divisórias e escreve
//! `panes`; o chamador desenha os painéis **depois** — eles cobrem o
//! fundo, deixando só as faixas das divisórias à mostra. Quando um arraste
//! ou o teclado move uma divisória, a geometria é recalculada no mesmo
//! frame (`changed`), sem lag de um frame.
//!
//! - Um `Id` por divisória (`id.child(indice)`) ⇒ foco, teclado e Tab.
//! - Mouse: press na faixa captura (`press_owner`); release encerra.
//! - Teclado com foco: setas movem 8 px, Home/End vão aos extremos.
//! - `DockStyle` + `Theme.dockStyle()` — espessura, cores, fundo/borda,
//!   realce do drop.
//!
//! `id` não-nulo obrigatório; `bounds` finito e positivo. `panes` precisa
//! comportar o número de folhas (`OutOfBuffer` caso contrário).

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const dock_mod = @import("../dock/layout.zig");
const input = @import("input.zig");

pub const DockViewError = context_mod.ContextError || dock_mod.DockError;

/// Opções do frame de `dockView`.
pub const DockViewOptions = struct {
    /// Painel (id de folha) que o chamador está arrastando; `null` ⇒ sem
    /// arraste de painel (as divisórias respondem normalmente). Enquanto
    /// ativo, `dockView` resolve a zona sob o cursor e aplica o drop no
    /// release; só painéis presentes no layout geram zona.
    dragging: ?u16 = null,
    /// Fração de cada lado de um painel que dispara uma zona de borda
    /// (0..0.5; 0.25 ⇒ 25% de cada lado, o resto é o centro).
    edge_frac: f32 = 0.25,
};

/// Zona de acoplamento sob o cursor durante o arraste de um painel.
pub const DockDrop = struct {
    /// Painel arrastado.
    pane: u16,
    /// Painel alvo (folha sob o cursor).
    target: u16,
    zone: dock_mod.DockZone,
    /// Rect do realce (zona do alvo).
    rect: types.Rect,
};

pub const DockViewResult = struct {
    /// Painéis escritos em `panes` (rects em pré-ordem das folhas).
    pane_count: usize = 0,
    /// Divisórias do layout (uma por split).
    split_count: usize = 0,
    /// A geometria mudou neste frame (arraste/teclado/drop).
    changed: bool = false,
    /// Índice (ordem de `dockSplits`) da divisória sob o mouse.
    hovered: ?usize = null,
    /// Índice da divisória sendo arrastada.
    dragging: ?usize = null,
    /// Zona de acoplamento sob o cursor (prévia do drop), se houver.
    drop: ?DockDrop = null,
    /// Drop aplicado neste frame (o chamador limpa o estado de arraste).
    dropped: ?DockDrop = null,
};

/// Tamanho do ajuste por tecla (px), como em `widgets/splitter`.
const key_step: f32 = 8;

/// Dimensão/origem do eixo do split (posição em px do chamador).
fn axisSize(rect: types.Rect, orientation: dock_mod.DockOrientation) f32 {
    return switch (orientation) {
        .horizontal => rect.h,
        .vertical => rect.w,
    };
}

fn axisOrigin(rect: types.Rect, orientation: dock_mod.DockOrientation) f32 {
    return switch (orientation) {
        .horizontal => rect.y,
        .vertical => rect.x,
    };
}

/// Ratio correspondente a uma posição em px no eixo do split (não
/// clampado; `dockSetRatio` clampa). Tamanho degenerado ⇒ 0.5.
fn posToRatio(rect: types.Rect, orientation: dock_mod.DockOrientation, pos: f32) f32 {
    const size = axisSize(rect, orientation);
    if (!std.math.isFinite(size) or size <= 0) return 0.5;
    return (pos - axisOrigin(rect, orientation)) / size;
}

/// Ratio deslocado em `delta_px` no eixo do split. Tamanho degenerado ⇒
/// ratio inalterado.
fn nudgeRatio(rect: types.Rect, orientation: dock_mod.DockOrientation, ratio: f32, delta_px: f32) f32 {
    const size = axisSize(rect, orientation);
    if (!std.math.isFinite(size) or size <= 0) return ratio;
    return ratio + delta_px / size;
}

/// Área de docking interativa sobre `layout`, dentro de `bounds`.
/// Preenche `panes` (rects das folhas) e devolve o resultado do frame.
/// `options.dragging` habilita o drop de painéis (passo 4).
pub fn dockView(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    layout: *dock_mod.DockLayout,
    bounds: types.Rect,
    panes: []types.Rect,
    style: style_mod.DockStyle,
    options: DockViewOptions,
) DockViewError!DockViewResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(options.edge_frac) or options.edge_frac < 0 or options.edge_frac > 0.5) {
        return error.InvalidArgument;
    }
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;

    // O número de splits é sempre `folhas - 1` ⇒ sempre cabe em `max_panes`.
    var splits: [dock_mod.DockLayout.max_panes]dock_mod.DockSplitInfo = undefined;
    var infos: [dock_mod.DockLayout.max_panes]dock_mod.DockPaneInfo = undefined;
    var res = DockViewResult{};

    res.split_count = try dock_mod.dockSplits(layout, bounds, style.divider, &splits);
    res.pane_count = try dock_mod.dockPanes(layout, bounds, style.divider, &infos);
    if (res.pane_count > panes.len) return error.OutOfBuffer;
    for (infos[0..res.pane_count], 0..) |info, k| panes[k] = info.rect;

    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    // Com um painel em arraste o alvo é resolvido por baixo do cursor e as
    // divisórias ficam inertes.
    var drop: ?DockDrop = null;
    if (options.dragging) |dragged| {
        if (dock_mod.dockFindPane(layout, dragged) != null) {
            if (ctx.mouse_pos) |p| {
                for (infos[0..res.pane_count]) |info| {
                    if (info.pane() == dragged) continue;
                    if (!info.rect.contains(p)) continue;
                    const zone = dock_mod.dockDropZone(info.rect, p, options.edge_frac);
                    drop = .{
                        .pane = dragged,
                        .target = info.pane(),
                        .zone = zone,
                        .rect = dock_mod.dockZoneRect(info.rect, zone),
                    };
                    break;
                }
            }
            if (drop) |d| {
                if (fm.released_pos != null and dock_mod.dockApplyDrop(layout, d.pane, d.target, d.zone)) {
                    res.dropped = d;
                    res.changed = true;
                }
            }
        }
    } else {
        var i: usize = 0;
        while (i < res.split_count) : (i += 1) {
            const split = splits[i];
            const divider_id = id.child(@intCast(i));
            try ctx.registerFocusable(divider_id);

            if (fm.pressedInside(split.divider)) ctx.focus_owner = divider_id;
            if (ctx.press_owner == null and fm.pressedInside(split.divider)) {
                ctx.press_owner = divider_id;
            }

            if (ctx.press_owner == divider_id) {
                if (ctx.mouse_down_left) {
                    res.dragging = i;
                    if (ctx.mouse_pos) |p| {
                        const pos = switch (split.orientation) {
                            .horizontal => p.y,
                            .vertical => p.x,
                        };
                        const ratio = posToRatio(split.rect, split.orientation, pos);
                        if (ratio != split.ratio) {
                            dock_mod.dockSetRatio(layout, split.node, ratio);
                            res.changed = true;
                        }
                    }
                }
                if (fm.released_pos != null) ctx.press_owner = null;
            }

            if (!ctx.hasFocus(divider_id)) continue;
            var delta: f32 = 0;
            var jump: ?f32 = null;
            for (ctx.pendingEvents()) |ev| {
                if (ev != .key) continue;
                const k = ev.key;
                if (!k.pressed or k.modifiers.ctrl) continue;
                switch (k.key) {
                    .left, .up => delta -= key_step,
                    .right, .down => delta += key_step,
                    .home => jump = 0,
                    .end => jump = 1,
                    .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                    else => {},
                }
            }
            if (jump) |target| {
                dock_mod.dockSetRatio(layout, split.node, target);
                res.changed = true;
            } else if (delta != 0) {
                dock_mod.dockSetRatio(layout, split.node, nudgeRatio(split.rect, split.orientation, split.ratio, delta));
                res.changed = true;
            }
        }
    }

    // Um arraste/teclado/drop mudou o layout: refaz a geometria (mesmo
    // frame) para que o chamador desenhe os painéis já nas novas posições.
    if (res.changed) {
        res.split_count = try dock_mod.dockSplits(layout, bounds, style.divider, &splits);
        res.pane_count = try dock_mod.dockPanes(layout, bounds, style.divider, &infos);
        if (res.pane_count > panes.len) return error.OutOfBuffer;
        for (infos[0..res.pane_count], 0..) |info, k| panes[k] = info.rect;
    }

    if (style.bg.a > 0) {
        ctx.draw.rectFilled(ctx.allocator, bounds, style.bg) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }
    if (style.border.a > 0 and style.border_width > 0) {
        ctx.draw.rectOutline(ctx.allocator, bounds, style.border, style.border_width) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }

    var i: usize = 0;
    while (i < res.split_count) : (i += 1) {
        const divider = splits[i].divider;
        const hovered = if (options.dragging != null)
            false
        else if (ctx.mouse_pos) |p|
            divider.contains(p)
        else
            false;
        if (hovered) res.hovered = i;
        const dragging = if (res.dragging) |d| d == i else false;
        const color = if (dragging)
            style.divider_drag
        else if (hovered)
            style.divider_hover
        else
            style.divider_idle;
        ctx.draw.rectFilled(ctx.allocator, divider, color) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCommand => return error.InvalidCommand,
        };
    }

    // Realce do drop por cima (some quando o drop é aplicado: a geometria
    // antiga já não vale). `drop` continua disponível em `res.drop`.
    res.drop = drop;
    if (res.dropped == null) {
        if (drop) |d| {
            if (style.drop_preview.a > 0) {
                ctx.draw.rectFilled(ctx.allocator, d.rect, style.drop_preview) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                };
            }
            if (style.drop_border.a > 0) {
                ctx.draw.rectOutline(ctx.allocator, d.rect, style.drop_border, 1) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                };
            }
        }
    }

    return res;
}

test "dockView: geometria, divisória e clique sem arraste" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const theme = style_mod.Theme.darkDefault();
    const style = theme.dockStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    var layout: dock_mod.DockLayout = undefined;
    dock_mod.dockInit(&layout, 0);
    _ = try dock_mod.dockSplit(&layout, 0, .horizontal, 0.5, 1);

    const bounds = types.Rect.init(0, 0, 400, 300);
    var panes: [dock_mod.DockLayout.max_panes]types.Rect = undefined;
    const id = id_mod.Id.fromString("test:dockview");

    ctx.beginFrame();
    const r0 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(usize, 2), r0.pane_count);
    try stdt.testing.expectEqual(@as(usize, 1), r0.split_count);
    try stdt.testing.expect(!r0.changed);
    try stdt.testing.expectEqual(@as(?usize, null), r0.hovered);
    try stdt.testing.expectEqual(@as(?usize, null), r0.dragging);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 147), panes[0]);
    try stdt.testing.expectEqual(types.Rect.init(0, 153, 400, 147), panes[1]);
    // Fundo + divisória desenhados.
    try stdt.testing.expectEqual(@as(usize, 2), ctx.drawCommands().len);
    ctx.endFrame();

    // Hover sobre a faixa (y ∈ [146,154)): cor de hover, sem arraste.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 150) } });
    const r1 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(?usize, 0), r1.hovered);
    try stdt.testing.expect(!r1.changed);
    ctx.endFrame();

    // Erros: id nulo, bounds inválidos e estilo inválido.
    ctx.beginFrame();
    try stdt.testing.expectError(error.InvalidArgument, dockView(&ctx, .null, &layout, bounds, &panes, style, .{}));
    try stdt.testing.expectError(error.InvalidArgument, dockView(&ctx, id, &layout, types.Rect.init(0, 0, 0, 10), &panes, style, .{}));
    try stdt.testing.expectError(error.InvalidArgument, dockView(&ctx, id, &layout, types.Rect.init(std.math.nan(f32), 0, 10, 10), &panes, style, .{}));
    const bad = style_mod.DockStyle{ .divider = -1, .divider_idle = .{}, .divider_hover = .{}, .divider_drag = .{} };
    try stdt.testing.expectError(error.InvalidArgument, dockView(&ctx, id, &layout, bounds, &panes, bad, .{}));
    var tiny: [1]types.Rect = undefined;
    try stdt.testing.expectError(error.OutOfBuffer, dockView(&ctx, id, &layout, bounds, &tiny, style, .{}));
    // `edge_frac` fora de [0,0.5] é inválido; arrastar painel inexistente não
    // produz alvo.
    try stdt.testing.expectError(error.InvalidArgument, dockView(&ctx, id, &layout, bounds, &panes, style, .{ .edge_frac = 0.9 }));
    const unknown = try dockView(&ctx, id, &layout, bounds, &panes, style, .{ .dragging = 77 });
    try stdt.testing.expectEqual(@as(?DockDrop, null), unknown.drop);
    ctx.endFrame();
}

test "dockView: arraste atualiza o ratio e a geometria no mesmo frame" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().dockStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    var layout: dock_mod.DockLayout = undefined;
    dock_mod.dockInit(&layout, 0);
    _ = try dock_mod.dockSplit(&layout, 0, .horizontal, 0.5, 1);

    const bounds = types.Rect.init(0, 0, 400, 300);
    var panes: [dock_mod.DockLayout.max_panes]types.Rect = undefined;
    const id = id_mod.Id.fromString("test:dockview-drag");

    // Press na faixa (y=150) captura; a posição já define o ratio (0.5).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(200, 150) },
    });
    const r0 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(?usize, 0), r0.dragging);
    try stdt.testing.expect(!r0.changed);
    try stdt.testing.expect(ctx.press_owner != null);
    ctx.endFrame();

    // Arrasta para y=210 ⇒ ratio 0.7 e geometria recalculada no frame.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 210) } });
    const r1 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(?usize, 0), r1.dragging);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.7), dock_mod.dockSplitRatio(&layout, 0).?, 0.0001);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 207), panes[0]);
    try stdt.testing.expectEqual(@as(?usize, 0), r1.hovered);
    ctx.endFrame();

    // Solta: encerra a captura, sem mudança de geometria.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(200, 210) },
    });
    const r2 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(?usize, null), r2.dragging);
    try stdt.testing.expect(!r2.changed);
    try stdt.testing.expect(ctx.press_owner == null);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.7), dock_mod.dockSplitRatio(&layout, 0).?, 0.0001);
    ctx.endFrame();
}

test "dockView: teclado (setas/Home/End) e layout aninhado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().dockStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    // Raiz vertical (x=0.5) com o lado direito dividido na horizontal.
    var layout: dock_mod.DockLayout = undefined;
    dock_mod.dockInit(&layout, 0);
    const right = try dock_mod.dockSplit(&layout, 0, .vertical, 0.5, 1);
    _ = try dock_mod.dockSplit(&layout, right, .horizontal, 0.5, 2);

    const bounds = types.Rect.init(0, 0, 400, 300);
    var panes: [dock_mod.DockLayout.max_panes]types.Rect = undefined;
    const id = id_mod.Id.fromString("test:dockview-keys");

    ctx.beginFrame();
    const r0 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(usize, 3), r0.pane_count);
    try stdt.testing.expectEqual(@as(usize, 2), r0.split_count);
    // Pré-ordem: pane0 (esq) e depois as duas metades da direita.
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 197, 300), panes[0]);
    try stdt.testing.expectEqual(types.Rect.init(203, 0, 197, 147), panes[1]);
    try stdt.testing.expectEqual(types.Rect.init(203, 153, 197, 147), panes[2]);
    ctx.endFrame();

    // Foca a divisória interna (índice 1, horizontal em y=147) e move com
    // o teclado: Down soma 8 px na área de 300 px (base 0.5 ⇒ 0.5 + 8/300).
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = true, .pos = types.Vec2.init(300, 150) },
    });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(300, 150) },
    });
    const r1 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expectEqual(@as(?usize, null), r1.dragging);
    try stdt.testing.expect(ctx.hasFocus(id.child(1)));
    try stdt.testing.expect(!ctx.hasFocus(id.child(0)));
    try stdt.testing.expectEqual(@as(?usize, 1), r1.hovered);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    const r2 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expect(r2.changed);
    const ratio = dock_mod.dockSplitRatio(&layout, right).?;
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5 + 8.0 / 300.0), ratio, 0.001);
    // Só o split interno mudou; a raiz permanece em 0.5.
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), dock_mod.dockSplitRatio(&layout, 0).?, 0.0001);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    const r3 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expect(r3.changed);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0), dock_mod.dockSplitRatio(&layout, right).?, 0.0001);
    try stdt.testing.expectEqual(@as(f32, 0), panes[1].h);
    ctx.endFrame();

    // Tab agenda o avanço do foco para o próximo `beginFrame` (a raiz).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{} } });
    _ = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expect(ctx.hasFocus(id.child(1)));
    ctx.endFrame();

    ctx.beginFrame();
    _ = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expect(ctx.hasFocus(id.child(0)));
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r4 = try dockView(&ctx, id, &layout, bounds, &panes, style, .{});
    try stdt.testing.expect(r4.changed);
    try stdt.testing.expectApproxEqAbs(@as(f32, 1), dock_mod.dockSplitRatio(&layout, 0).?, 0.0001);
    ctx.endFrame();
}

test "dockView: drop de painel (borda redivide, centro troca)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = style_mod.Theme.darkDefault().dockStyle();
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();

    // Painel 0 à esquerda; 1 e 2 empilhados à direita.
    var layout: dock_mod.DockLayout = undefined;
    dock_mod.dockInit(&layout, 0);
    const right = try dock_mod.dockSplit(&layout, 0, .vertical, 0.5, 1);
    _ = try dock_mod.dockSplit(&layout, right, .horizontal, 0.5, 2);

    const bounds = types.Rect.init(0, 0, 400, 300);
    var panes: [dock_mod.DockLayout.max_panes]types.Rect = undefined;
    const id = id_mod.Id.fromString("test:dockview-drop");
    const drag = DockViewOptions{ .dragging = 2 };

    // Cursor na borda esquerda do painel 0 (x < 25% de 197) ⇒ zona `.left`
    // com realce; com um painel em arraste as divisórias ficam inertes.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(10, 150) } });
    const r0 = try dockView(&ctx, id, &layout, bounds, &panes, style, drag);
    try stdt.testing.expect(!r0.changed);
    try stdt.testing.expectEqual(@as(?usize, null), r0.dragging);
    try stdt.testing.expectEqual(@as(?usize, null), r0.hovered);
    try stdt.testing.expectEqual(@as(?DockDrop, null), r0.dropped);
    const d0 = r0.drop.?;
    try stdt.testing.expectEqual(@as(u16, 2), d0.pane);
    try stdt.testing.expectEqual(@as(u16, 0), d0.target);
    try stdt.testing.expectEqual(dock_mod.DockZone.left, d0.zone);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 98.5, 300), d0.rect);
    // Fundo + 2 divisórias + realce (preenchimento + borda).
    try stdt.testing.expectEqual(@as(usize, 5), ctx.drawCommands().len);
    ctx.endFrame();

    // Release no mesmo ponto ⇒ aplica o drop: painel 2 vai para a esquerda
    // do painel 0 e a geometria é refeita no frame.
    ctx.beginFrame();
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(10, 150) },
    });
    const r1 = try dockView(&ctx, id, &layout, bounds, &panes, style, drag);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(dock_mod.DockZone.left, r1.dropped.?.zone);
    try stdt.testing.expectEqual(@as(u16, 0), r1.dropped.?.target);
    try stdt.testing.expectEqual(@as(usize, 3), r1.pane_count);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 95.5, 300), panes[0]);
    try stdt.testing.expectEqual(types.Rect.init(101.5, 0, 95.5, 300), panes[1]);
    try stdt.testing.expectEqual(types.Rect.init(203, 0, 197, 300), panes[2]);
    ctx.endFrame();

    // Sobre a faixa da divisória (x=197..203) não há alvo ⇒ release sem
    // efeito (o painel arrastado e a faixa não contam).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 150) } });
    const r2 = try dockView(&ctx, id, &layout, bounds, &panes, style, drag);
    try stdt.testing.expectEqual(@as(?DockDrop, null), r2.drop);
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(200, 150) },
    });
    const r3 = try dockView(&ctx, id, &layout, bounds, &panes, style, drag);
    try stdt.testing.expectEqual(@as(?DockDrop, null), r3.dropped);
    try stdt.testing.expect(!r3.changed);
    try stdt.testing.expectEqual(@as(usize, 3), r3.pane_count);
    ctx.endFrame();

    // Zona `.center` ⇒ acopla como aba do grupo alvo: os dois painéis
    // passam a dividir um grupo (um só rect, com 2 abas).
    var l2: dock_mod.DockLayout = undefined;
    dock_mod.dockInit(&l2, 0);
    _ = try dock_mod.dockSplit(&l2, 0, .horizontal, 0.5, 1);
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(200, 70) } });
    try ctx.pushEvent(.{
        .mouse_button = .{ .button = .left, .pressed = false, .pos = types.Vec2.init(200, 70) },
    });
    const r4 = try dockView(&ctx, id, &l2, bounds, &panes, style, .{ .dragging = 1 });
    try stdt.testing.expectEqual(dock_mod.DockZone.center, r4.dropped.?.zone);
    try stdt.testing.expectEqual(@as(u16, 0), r4.dropped.?.target);
    try stdt.testing.expect(r4.changed);
    try stdt.testing.expectEqual(@as(usize, 1), r4.pane_count);
    try stdt.testing.expectEqual(bounds, panes[0]);
    var infos: [dock_mod.DockLayout.max_panes]dock_mod.DockPaneInfo = undefined;
    try stdt.testing.expectEqual(@as(usize, 1), try dock_mod.dockPanes(&l2, bounds, style.divider, &infos));
    try stdt.testing.expectEqual(@as(u16, 1), infos[0].pane()); // 1 ficou ativo
    try stdt.testing.expectEqualSlices(u16, &.{ 0, 1 }, infos[0].group.tabs());
    try stdt.testing.expectEqual(@as(u8, 2), infos[0].group.count);
    ctx.endFrame();
}
