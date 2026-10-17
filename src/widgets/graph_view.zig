//! ZyntraUI — grafo de nós (widgets/graph_view).
//!
//! Modelo M94 (visualização + interação) sobre o modelo puro
//! `graph/view`. O estado (transformação mundo↔tela + seleção) pertence
//! ao chamador e é retido entre frames (`GraphViewState`).
//!
//! - Pan: press no vazio captura (`press_owner`) e arrasta
//!   `transform.pan` por delta incremental (px de tela).
//! - Nó: press sobre um nó seleciona e arrasta por "pega" (ponto-mundo
//!   do clique) — a posição segue o cursor sem deriva acumulada. O
//!   widget ATUALIZA `nodes[i].pos` (memória do chamador) e reporta o
//!   deslocamento do frame em `drag_delta`.
//! - Roda com hover: zoom em torno do cursor. Usa o SINAL de `dy`
//!   (passo fixo `zoom_step`), robusto às magnitudes por plataforma;
//!   clampado em `[min_zoom, max_zoom]`.
//! - Teclado com foco: setas deslocam o canvas (`pan_step`), Page
//!   Up/Down dão zoom no centro de `bounds`, Home reseta (zoom 1 / pan
//!   0), Tab circula o foco.
//! - Desenho: fundo, grade "número redondo", arestas (Bézier cúbica
//!   amostrada em comandos `.line`), nós (realce de seleção + borda por
//!   expansão concêntrica, corpo, faixa de título, título, pinos). Tudo
//!   clipado em `bounds` (comando `.clip`).
//! - O título escala com o zoom (mesmas proporções de `font`) e é
//!   omitido abaixo de ~1 px de tamanho.
//! - Índices fora de faixa em `state` (nós removidos) são descartados;
//!   índices fora de faixa em `edges` são ignorados no desenho.
//! - `id` não-nulo obrigatório.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const graph_mod = @import("../graph/view.zig");
const input = @import("input.zig");

/// Estado do grafo (dono: chamador; retido entre frames).
pub const GraphViewState = struct {
    /// Transformação mundo↔tela.
    transform: graph_mod.Transform = .{},
    /// Nó selecionado (`null` = nenhum).
    selected: ?usize = null,
    /// Nó em arraste (`null` = pan do fundo ou nenhum). Transiente.
    drag_node: ?usize = null,
    /// Vetor-mundo do clique até `nodes[i].pos` no início do arraste.
    drag_grab: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Última posição de tela durante o pan (delta incremental).
    pan_anchor: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Pan em andamento (fundo). Transiente.
    panning: bool = false,
};

/// Opções de interação do grafo.
pub const GraphViewOptions = struct {
    /// Zoom mínimo/máximo (clamp); `0 < min <= max`.
    min_zoom: f32 = 0.25,
    max_zoom: f32 = 4.0,
    /// Fator multiplicativo por entrelinha da roda (> 0).
    zoom_step: f32 = 1.25,
    /// Passo do pan por seta em px de tela (>= 0).
    pan_step: f32 = 24.0,
    /// Segmentos por aresta (Bézier amostrada; `>= 1`).
    edge_segments: u32 = 12,

    pub fn isValid(self: GraphViewOptions) bool {
        if (!std.math.isFinite(self.min_zoom) or !std.math.isFinite(self.max_zoom)) return false;
        if (!(self.min_zoom > 0) or self.max_zoom < self.min_zoom) return false;
        if (!std.math.isFinite(self.zoom_step) or self.zoom_step <= 0) return false;
        if (!std.math.isFinite(self.pan_step) or self.pan_step < 0) return false;
        if (self.edge_segments < 1) return false;
        return true;
    }
};

/// Resultado do frame.
pub const GraphViewResult = struct {
    /// Nó sob o cursor (dentro de `bounds`), se houver.
    hovered: ?usize = null,
    /// Nó selecionado ao fim do frame.
    selected: ?usize = null,
    /// Nó arrastado neste frame.
    dragging: ?usize = null,
    /// Deslocamento aplicado ao nó arrastado neste frame (mundo).
    drag_delta: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Pan aplicado neste frame (px de tela).
    pan_delta: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Zoom mudou neste frame (roda/teclado).
    zoom_changed: bool = false,
    /// A captura ativa neste frame é o pan do fundo.
    panning: bool = false,
    /// Seleção, arraste, pan ou zoom mudou neste frame.
    changed: bool = false,
};

/// Máximo de linhas de grade por eixo (guarda contra loops patológicos
/// em zoom extremo).
pub const grid_max_lines: u32 = 512;

/// Menor tamanho de fonte do título desenhado (px); abaixo disso o
/// título é omitido.
pub const min_title_size: f32 = 1.0;

fn fillShape(
    ctx: *context_mod.Context,
    r: types.Rect,
    radius: f32,
    color: types.Color,
) context_mod.ContextError!void {
    if (radius > 0) {
        try ctx.draw.rectRounded(ctx.allocator, r, radius, color);
    } else {
        try ctx.draw.rectFilled(ctx.allocator, r, color);
    }
}

/// Desenha e interage com um grafo de nós em `bounds`.
/// Ver o cabeçalho do módulo para semântica de pan/zoom/arraste.
pub fn graphView(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    nodes: []graph_mod.GraphNode,
    edges: []const graph_mod.GraphEdge,
    state: *GraphViewState,
    options: GraphViewOptions,
    style: style_mod.GraphStyle,
    font: metrics_mod.FontMetrics,
) context_mod.ContextError!GraphViewResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid() or !options.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!graph_mod.Transform.isValid(state.transform)) return error.InvalidArgument;
    for (nodes) |n| {
        if (!n.isValid()) return error.InvalidArgument;
    }

    // Índices fora de faixa (nós removidos pelo chamador) são descartados.
    if (state.selected) |s| {
        if (s >= nodes.len) state.selected = null;
    }
    if (state.drag_node) |d| {
        if (d >= nodes.len) state.drag_node = null;
    }

    var res = GraphViewResult{ .selected = state.selected };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const hovered_bounds = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    try ctx.registerFocusable(id);

    // Hover: nó sob o cursor (espaço-mundo), só dentro de `bounds`.
    if (hovered_bounds) {
        if (ctx.mouse_pos) |p| {
            res.hovered = graph_mod.hitNode(nodes, state.transform.screenToWorld(p));
        }
    }

    // Press: captura. Sobre nó ⇒ arraste do nó; no vazio ⇒ pan.
    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        if (ctx.mouse_pos) |p| {
            ctx.press_owner = id;
            ctx.focus_owner = id;
            if (res.hovered) |i| {
                state.drag_node = i;
                state.panning = false;
                const wp = state.transform.screenToWorld(p);
                state.drag_grab = .{
                    .x = wp.x - nodes[i].pos.x,
                    .y = wp.y - nodes[i].pos.y,
                };
                if (state.selected != i) {
                    state.selected = i;
                    res.selected = i;
                    res.changed = true;
                }
            } else {
                state.drag_node = null;
                state.panning = true;
                state.pan_anchor = p;
            }
        }
    }

    // Arraste (enquanto dono da captura): nó segue o cursor por "pega";
    // fundo faz pan incremental.
    if (ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            if (ctx.mouse_pos) |p| {
                if (state.drag_node) |i| {
                    if (i < nodes.len) {
                        res.dragging = i;
                        const wp = state.transform.screenToWorld(p);
                        const target = types.Vec2.init(
                            wp.x - state.drag_grab.x,
                            wp.y - state.drag_grab.y,
                        );
                        const d = types.Vec2.init(
                            target.x - nodes[i].pos.x,
                            target.y - nodes[i].pos.y,
                        );
                        if (d.x != 0 or d.y != 0) {
                            nodes[i].pos = target;
                            res.drag_delta = d;
                            res.changed = true;
                        }
                    }
                } else if (state.panning) {
                    const d = types.Vec2.init(p.x - state.pan_anchor.x, p.y - state.pan_anchor.y);
                    if (d.x != 0 or d.y != 0) {
                        state.transform.pan.x += d.x;
                        state.transform.pan.y += d.y;
                        state.pan_anchor = p;
                        res.pan_delta = d;
                        res.changed = true;
                    }
                    res.panning = true;
                }
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            state.drag_node = null;
            state.panning = false;
            res.dragging = null;
        }
    }

    // Roda com hover: zoom em torno do cursor (usa o sinal de `dy`).
    if (hovered_bounds) {
        for (ctx.pendingEvents()) |ev| {
            if (ev != .mouse_wheel) continue;
            const w = ev.mouse_wheel;
            const factor: f32 = if (w.dy > 0)
                options.zoom_step
            else if (w.dy < 0)
                1.0 / options.zoom_step
            else
                1.0;
            if (factor == 1) continue;
            const before = state.transform.zoom;
            state.transform = state.transform.zoomAt(
                w.pos,
                factor,
                options.min_zoom,
                options.max_zoom,
            );
            if (state.transform.zoom != before) {
                res.zoom_changed = true;
                res.changed = true;
            }
        }
    }

    // Teclado com foco (setas/Page Up/Down/Home/Tab).
    if (ctx.hasFocus(id)) {
        const center = types.Vec2.init(bounds.x + bounds.w / 2, bounds.y + bounds.h / 2);
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .left => {
                    state.transform.pan.x -= options.pan_step;
                    res.pan_delta.x -= options.pan_step;
                    res.changed = true;
                },
                .right => {
                    state.transform.pan.x += options.pan_step;
                    res.pan_delta.x += options.pan_step;
                    res.changed = true;
                },
                .up => {
                    state.transform.pan.y -= options.pan_step;
                    res.pan_delta.y -= options.pan_step;
                    res.changed = true;
                },
                .down => {
                    state.transform.pan.y += options.pan_step;
                    res.pan_delta.y += options.pan_step;
                    res.changed = true;
                },
                .page_up, .page_down => {
                    const factor: f32 = if (k.key == .page_up)
                        options.zoom_step
                    else
                        1.0 / options.zoom_step;
                    const before = state.transform.zoom;
                    state.transform = state.transform.zoomAt(
                        center,
                        factor,
                        options.min_zoom,
                        options.max_zoom,
                    );
                    if (state.transform.zoom != before) {
                        res.zoom_changed = true;
                        res.changed = true;
                    }
                },
                .home => {
                    state.transform = .{};
                    res.zoom_changed = true;
                    res.changed = true;
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }

    // --- Desenho (clipado em `bounds`) ---
    const tr = state.transform;
    const zoom = tr.zoom;

    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } });

    if (style.bg.a != 0) try fillShape(ctx, bounds, 0, style.bg);

    // Grade: passo "número redondo" (mundo) derivado do alvo em tela.
    const step = graph_mod.gridStep(zoom, style.grid_target_px);
    if (step > 0 and style.grid.a != 0) {
        const tl = tr.screenToWorld(.{ .x = bounds.x, .y = bounds.y });
        const br = tr.screenToWorld(.{ .x = bounds.x + bounds.w, .y = bounds.y + bounds.h });
        var n: u32 = 0;
        var wx = @ceil(tl.x / step) * step;
        while (wx <= br.x and n < grid_max_lines) : ({
            wx += step;
            n += 1;
        }) {
            const sx = wx * zoom + tr.pan.x;
            try ctx.draw.line(
                ctx.allocator,
                .{ .x = sx, .y = bounds.y },
                .{ .x = sx, .y = bounds.y + bounds.h },
                style.grid,
                1.0,
            );
        }
        n = 0;
        var wy = @ceil(tl.y / step) * step;
        while (wy <= br.y and n < grid_max_lines) : ({
            wy += step;
            n += 1;
        }) {
            const sy = wy * zoom + tr.pan.y;
            try ctx.draw.line(
                ctx.allocator,
                .{ .x = bounds.x, .y = sy },
                .{ .x = bounds.x + bounds.w, .y = sy },
                style.grid,
                1.0,
            );
        }
    }

    // Arestas: Bézier cúbica amostrada (controles em px de tela).
    for (edges) |e| {
        const anchors = graph_mod.edgeAnchors(nodes, e) orelse continue;
        const a = types.Vec2.init(
            anchors[0].x * zoom + tr.pan.x,
            anchors[0].y * zoom + tr.pan.y,
        );
        const b = types.Vec2.init(
            anchors[1].x * zoom + tr.pan.x,
            anchors[1].y * zoom + tr.pan.y,
        );
        const c = graph_mod.bezierControls(a, b);
        const segs: f32 = @floatFromInt(options.edge_segments);
        var prev = a;
        var i: u32 = 1;
        while (i <= options.edge_segments) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / segs;
            const pt = graph_mod.bezierPoint(a, c[0], c[1], b, t);
            try ctx.draw.line(ctx.allocator, prev, pt, style.edge, style.edge_width);
            prev = pt;
        }
    }

    // Nós (na ordem do slice; o último fica no topo, como no hit-test).
    const radius = style.node_radius * zoom;
    for (nodes, 0..) |n, i| {
        const sr = types.Rect{
            .x = n.pos.x * zoom + tr.pan.x,
            .y = n.pos.y * zoom + tr.pan.y,
            .w = n.size.x * zoom,
            .h = n.size.y * zoom,
        };
        if (state.selected != null and state.selected.? == i and
            style.node_selected.a != 0 and style.node_selected_width > 0)
        {
            const d = style.node_selected_width;
            try fillShape(ctx, expand(sr, d), radius + d, style.node_selected);
        }
        if (style.node_border.a != 0 and style.node_border_width > 0) {
            const d = style.node_border_width;
            try fillShape(ctx, expand(sr, d), radius + d, style.node_border);
        }
        try fillShape(ctx, sr, radius, style.node_bg);

        // Faixa de título: cantos superiores arredondados, inferiores retos.
        const band_h = @min(style.header_height * zoom, sr.h);
        if (band_h > 0 and style.node_header.a != 0) {
            const band = types.Rect{ .x = sr.x, .y = sr.y, .w = sr.w, .h = band_h };
            try fillShape(ctx, band, radius, style.node_header);
            if (radius > 0 and band_h > radius) {
                try fillShape(
                    ctx,
                    .{ .x = band.x, .y = band.y + radius, .w = band.w, .h = band.h - radius },
                    0,
                    style.node_header,
                );
            }
            const tsize = font.size * zoom;
            if (n.title.len > 0 and tsize >= min_title_size) {
                const tfont = metrics_mod.FontMetrics.withSize(tsize);
                const ty = band.y + @max(0, (band.h - tfont.lineHeight()) / 2);
                ctx.draw.pushText(
                    ctx.allocator,
                    .{ .x = band.x + style.title_pad * zoom, .y = ty },
                    style.title,
                    tfont,
                    n.title,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidCommand => return error.InvalidCommand,
                    error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
                };
            }
        }

        // Pinos (px de tela: espessura constante).
        if (style.port.a != 0 and style.port_radius > 0) {
            var pi: u32 = 0;
            while (pi < n.inputs) : (pi += 1) {
                const wp = graph_mod.portPos(n, .input, pi);
                try ctx.draw.circleFilled(
                    ctx.allocator,
                    .{ .x = wp.x * zoom + tr.pan.x, .y = wp.y * zoom + tr.pan.y },
                    style.port_radius,
                    style.port,
                );
            }
            pi = 0;
            while (pi < n.outputs) : (pi += 1) {
                const wp = graph_mod.portPos(n, .output, pi);
                try ctx.draw.circleFilled(
                    ctx.allocator,
                    .{ .x = wp.x * zoom + tr.pan.x, .y = wp.y * zoom + tr.pan.y },
                    style.port_radius,
                    style.port,
                );
            }
        }
    }

    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } });

    return res;
}

fn expand(r: types.Rect, d: f32) types.Rect {
    return .{ .x = r.x - d, .y = r.y - d, .w = r.w + 2 * d, .h = r.h + 2 * d };
}

fn testStyle() style_mod.GraphStyle {
    return .{
        .bg = types.Color.rgb(10, 10, 10),
        .grid = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .grid_target_px = 32,
        .node_bg = types.Color.rgb(40, 40, 40),
        .node_header = types.Color.rgb(0, 0, 255),
        .node_border = types.Color.rgb(200, 200, 200),
        .node_selected = types.Color.rgb(255, 200, 0),
        .node_border_width = 1,
        .node_selected_width = 2,
        .node_radius = 4,
        .header_height = 18,
        .title = types.Color.rgb(255, 255, 255),
        .title_pad = 8,
        .edge = types.Color.rgb(150, 150, 150),
        .edge_width = 1.5,
        .port = types.Color.rgb(255, 255, 255),
        .port_radius = 3,
    };
}

test "graphView: hover, seleção e pan no fundo (entre frames)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:graph");
    const bounds = types.Rect.init(0, 0, 200, 120);
    var nodes = [_]graph_mod.GraphNode{
        .{ .pos = .{ .x = 10, .y = 10 }, .size = .{ .x = 40, .y = 30 } },
    };
    var st = GraphViewState{};

    // Frame 1: hover sobre o nó (zoom 1 / pan 0 ⇒ mundo == tela).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(20, 20) } });
    const r0 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.hovered);
    try stdt.testing.expectEqual(@as(?usize, null), r0.selected);
    try stdt.testing.expect(!r0.changed);
    ctx.endFrame();

    // Frame 2: press no vazio ⇒ pan (sem selecionar).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(150, 100),
    } });
    const r1 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r1.hovered);
    try stdt.testing.expect(r1.panning);
    try stdt.testing.expect(ctx.hasFocus(id));
    try stdt.testing.expectEqual(@as(f32, 0), r1.pan_delta.x);
    ctx.endFrame();

    // Frame 3: arraste ⇒ pan_delta e `transform.pan` seguem o cursor.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(160, 110) } });
    const r2 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(r2.panning);
    try stdt.testing.expect(r2.changed);
    try stdt.testing.expectEqual(@as(f32, 10), r2.pan_delta.x);
    try stdt.testing.expectEqual(@as(f32, 10), r2.pan_delta.y);
    try stdt.testing.expectEqual(@as(f32, 10), st.transform.pan.x);
    try stdt.testing.expectEqual(@as(f32, 10), st.transform.pan.y);
    try stdt.testing.expectEqual(@as(f32, 10), nodes[0].pos.x); // nó intacto
    ctx.endFrame();

    // Frame 4: release encerra a captura.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(160, 110),
    } });
    const r3 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(!r3.panning);
    try stdt.testing.expect(ctx.press_owner == null);
    try stdt.testing.expectEqual(@as(?usize, null), r3.dragging);
    ctx.endFrame();
}

test "graphView: seleção e arraste do nó em espaço-mundo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:graph-drag");
    const bounds = types.Rect.init(0, 0, 200, 120);
    var nodes = [_]graph_mod.GraphNode{
        .{ .pos = .{ .x = 10, .y = 10 }, .size = .{ .x = 40, .y = 30 } },
    };
    // zoom 2 / pan (5,0): nó em tela = (25,20)-(105,80).
    var st = GraphViewState{ .transform = .{ .zoom = 2, .pan = .{ .x = 5, .y = 0 } } };

    // Frame 1: press dentro do nó ⇒ seleciona e inicia o arraste sem salto.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(45, 30),
    } });
    const r0 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.selected);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.dragging);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(f32, 10), nodes[0].pos.x);
    try stdt.testing.expectEqual(@as(f32, 10), nodes[0].pos.y);
    ctx.endFrame();

    // Frame 2: +20 px de tela ⇒ +10 no mundo (zoom 2).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(65, 50) } });
    const r1 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 0), r1.dragging);
    try stdt.testing.expectEqual(@as(f32, 10), r1.drag_delta.x);
    try stdt.testing.expectEqual(@as(f32, 10), r1.drag_delta.y);
    try stdt.testing.expectEqual(@as(f32, 20), nodes[0].pos.x);
    try stdt.testing.expectEqual(@as(f32, 20), nodes[0].pos.y);
    ctx.endFrame();

    // Frame 3: release ⇒ sem arraste e captura liberada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(65, 50),
    } });
    const r2 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), r2.dragging);
    try stdt.testing.expect(st.drag_node == null);
    try stdt.testing.expectEqual(@as(?usize, 0), r2.selected);
    ctx.endFrame();

    // Frame 4: press sobre outro ponto vazio não muda a seleção.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(190, 110),
    } });
    const r3 = try graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 0), r3.selected);
    try stdt.testing.expect(st.panning);
    ctx.endFrame();
}

test "graphView: zoom pela roda mantém o cursor e clampa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:graph-zoom");
    const bounds = types.Rect.init(0, 0, 200, 120);
    var st = GraphViewState{};
    const cursor = types.Vec2.init(50, 40);
    const opts = GraphViewOptions{ .min_zoom = 0.5, .max_zoom = 2 };

    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1, .pos = cursor } });
    const r0 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, opts, style, font);
    try stdt.testing.expect(r0.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 1.25), st.transform.zoom);
    // O ponto-mundo sob o cursor não se move.
    const s = st.transform.worldToScreen(cursor);
    try stdt.testing.expectApproxEqAbs(cursor.x, s.x, 1e-3);
    try stdt.testing.expectApproxEqAbs(cursor.y, s.y, 1e-3);
    ctx.endFrame();

    // Muitos passos para baixo ⇒ clampa no mínimo.
    ctx.beginFrame();
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = cursor } });
    }
    const r1 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, opts, style, font);
    try stdt.testing.expect(r1.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 0.5), st.transform.zoom);
    ctx.endFrame();

    // Muitos passos para cima ⇒ clampa no máximo.
    ctx.beginFrame();
    i = 0;
    while (i < 16) : (i += 1) {
        try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 3, .pos = cursor } });
    }
    const r2 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, opts, style, font);
    try stdt.testing.expect(r2.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 2), st.transform.zoom);
    ctx.endFrame();

    // Fora do hover (cursor fora de `bounds`) a roda não afeta o zoom.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = types.Vec2.init(500, 500) } });
    const r3 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, opts, style, font);
    try stdt.testing.expect(!r3.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 2), st.transform.zoom);
    ctx.endFrame();
}

test "graphView: teclado (setas, Page Up/Down, Home, Tab)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:graph-keys");
    const bounds = types.Rect.init(0, 0, 200, 120);
    var st = GraphViewState{};

    // Press + release no vazio focam o widget (a captura já foi liberada).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 60),
    } });
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(100, 60),
    } });
    _ = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(ctx.hasFocus(id));
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Setas: passo de 24 px de tela por pressionamento.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .down, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    // Solta não deve repetir a ação.
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = false, .modifiers = .{} } });
    const r0 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(f32, 24), r0.pan_delta.x); // 2*24 - 24
    try stdt.testing.expectEqual(@as(f32, 24), r0.pan_delta.y);
    try stdt.testing.expectEqual(@as(f32, 24), st.transform.pan.x);
    try stdt.testing.expectEqual(@as(f32, 24), st.transform.pan.y);
    ctx.endFrame();

    // Page Up dá zoom no centro; Page Down inverte.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_up, .pressed = true, .modifiers = .{} } });
    const r1 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(r1.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 1.25), st.transform.zoom);
    // O ponto-mundo sob o centro de `bounds` fica fixo: mundo (76,36) ⇒
    // pan = centro - mundo * 1.25 = (100 - 95, 60 - 45).
    try stdt.testing.expectEqual(@as(f32, 5), st.transform.pan.x);
    try stdt.testing.expectEqual(@as(f32, 15), st.transform.pan.y);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    const r2 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(r2.zoom_changed);
    try stdt.testing.expectApproxEqAbs(@as(f32, 1.0), st.transform.zoom, 1e-6);
    // Volta ao pan anterior (mesma âncora).
    try stdt.testing.expectApproxEqAbs(@as(f32, 24), st.transform.pan.x, 1e-3);
    try stdt.testing.expectApproxEqAbs(@as(f32, 24), st.transform.pan.y, 1e-3);
    ctx.endFrame();

    // Home reseta transformação; Tab agenda o avanço de foco.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{ .shift = true } } });
    const r3 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(r3.changed);
    try stdt.testing.expectEqual(@as(f32, 0), st.transform.pan.x);
    try stdt.testing.expectEqual(@as(f32, 0), st.transform.pan.y);
    try stdt.testing.expectEqual(@as(f32, 1), st.transform.zoom);
    try stdt.testing.expect(ctx.pending_focus_advance != null);
    ctx.endFrame();

    // Ctrl+seta é ignorado (atalhos do host).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{ .ctrl = true } } });
    const r4 = try graphView(&ctx, id, bounds, &.{}, &.{}, &st, .{}, style, font);
    try stdt.testing.expect(!r4.changed);
    try stdt.testing.expectEqual(@as(f32, 0), st.transform.pan.x);
    ctx.endFrame();
}

test "graphView: desenho (clip, grade, aresta, título e pinos)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:graph-draw");
    const bounds = types.Rect.init(0, 0, 100, 100);
    var nodes = [_]graph_mod.GraphNode{
        .{
            .pos = .{ .x = 8, .y = 8 },
            .size = .{ .x = 40, .y = 30 },
            .title = "n",
            .inputs = 1,
            .outputs = 1,
        },
        .{ .pos = .{ .x = 60, .y = 60 }, .size = .{ .x = 30, .y = 30 } },
    };
    const edges = [_]graph_mod.GraphEdge{.{ .from = 0, .to = 1 }};
    var st = GraphViewState{};

    ctx.beginFrame();
    const r = try graphView(&ctx, id, bounds, &nodes, &edges, &st, .{ .edge_segments = 4 }, style, font);
    try stdt.testing.expect(!r.changed);

    const cmds = ctx.drawCommands();
    // Primeiro comando: clip em `bounds`; último: remoção do clip.
    try stdt.testing.expect(cmds[0] == .clip);
    try stdt.testing.expect(!cmds[0].clip.null_rect);
    try stdt.testing.expectEqual(@as(f32, 100), cmds[0].clip.rect.w);
    try stdt.testing.expect(cmds[cmds.len - 1] == .clip);
    try stdt.testing.expect(cmds[cmds.len - 1].clip.null_rect);

    var rounded: usize = 0;
    var texts: usize = 0;
    var lines: usize = 0;
    var ports: usize = 0;
    var fills: usize = 0;
    var text_at: usize = 0;
    for (cmds, 0..) |c, ci| {
        switch (c) {
            .rect_rounded => rounded += 1,
            .rect_filled => fills += 1,
            .text => {
                texts += 1;
                text_at = ci;
            },
            .line => lines += 1,
            .circle_filled => ports += 1,
            else => {},
        }
    }
    // Por nó: borda + corpo + faixa de título (raio 4 ⇒ `rect_rounded`).
    // A quadratura dos cantos da faixa e o fundo são `rect_filled`
    // (raio 0): 2 nós ⇒ 6 arredondados e 1 fundo + 2 quadraturas = 3.
    try stdt.testing.expectEqual(@as(usize, 6), rounded);
    try stdt.testing.expectEqual(@as(usize, 3), fills);
    // 1 aresta × 4 segmentos.
    try stdt.testing.expectEqual(@as(usize, 4), lines);
    // Título só do nó 0 (o nó 1 não tem título).
    try stdt.testing.expectEqual(@as(usize, 1), texts);
    try stdt.testing.expectEqualStrings("n", ctx.draw.textOf(cmds[text_at]));
    // Título recuado de `title_pad` a partir da borda esquerda do nó.
    try stdt.testing.expectEqual(@as(f32, 16), cmds[text_at].text.pos.x);
    // 1 entrada + 1 saída.
    try stdt.testing.expectEqual(@as(usize, 2), ports);
    ctx.endFrame();
}

test "graphView: contratos inválidos e índices fora de faixa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:graph-bad");
    const bounds = types.Rect.init(0, 0, 100, 100);
    var nodes = [_]graph_mod.GraphNode{
        .{ .pos = .{ .x = 0, .y = 0 }, .size = .{ .x = 20, .y = 20 } },
    };
    var st = GraphViewState{};

    ctx.beginFrame();
    // id nulo
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, .null, bounds, &nodes, &.{}, &st, .{}, style, font));
    // bounds inválidos
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, types.Rect.init(0, 0, 0, 10), &nodes, &.{}, &st, .{}, style, font));
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, types.Rect.init(0, 0, 10, std.math.nan(f32)), &nodes, &.{}, &st, .{}, style, font));
    // estilo / fonte / opções
    var bad_style = style;
    bad_style.edge_width = 0;
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, bad_style, font));
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{ .min_zoom = 4, .max_zoom = 1 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{ .edge_segments = 0 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, bounds, &nodes, &.{}, &st, .{}, style, metrics_mod.FontMetrics{ .size = 0 }));
    // nó inválido
    var bad_nodes = [_]graph_mod.GraphNode{.{ .size = .{ .x = 0, .y = 10 } }};
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, bounds, &bad_nodes, &.{}, &st, .{}, style, font));
    // transformação inválida
    var bad_st = GraphViewState{ .transform = .{ .zoom = 0 } };
    try stdt.testing.expectError(error.InvalidArgument, graphView(&ctx, id, bounds, &nodes, &.{}, &bad_st, .{}, style, font));
    // índices fora de faixa são descartados (nós removidos pelo chamador).
    var st2 = GraphViewState{ .selected = 7, .drag_node = 9, .panning = true };
    _ = try graphView(&ctx, id, bounds, &nodes, &.{}, &st2, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, null), st2.selected);
    try stdt.testing.expectEqual(@as(?usize, null), st2.drag_node);
    // Aresta com índice inválido é ignorada (não emite `.line`).
    const bad_edges = [_]graph_mod.GraphEdge{.{ .from = 0, .to = 3 }};
    _ = try graphView(&ctx, id, bounds, &nodes, &bad_edges, &st, .{}, style, font);
    for (ctx.drawCommands()) |c| {
        try stdt.testing.expect(c != .line);
    }
    ctx.endFrame();
}
