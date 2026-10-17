//! ZyntraUI — timeline (widgets/timeline_view).
//!
//! Modelo M95 (visualização + interação) sobre o modelo puro
//! `timeline/view`. O estado (transformação tempo↔tela, playhead e
//! seleção) pertence ao chamador e é retido entre frames
//! (`TimelineViewState`).
//!
//! Layout: faixa da régua no topo (`ruler_height`) e, abaixo, uma linha
//! por trilha (`row_height`). A coluna de nomes à esquerda
//! (`name_width`) é inerte; a ÁREA DE TEMPO é o resto de `bounds`.
//! Marcações e chaves são clipadas à área de tempo.
//!
//! Interação:
//! - Régua: press/drag scrubbam o playhead (clampado em
//!   `[0, duration]`).
//! - Chave (dentro de `key_hit_px`): press seleciona e arrasta pela
//!   "pega" (`t_mouse - t_chave`) com ajuste opcional ao passo da régua
//!   (`snap_keys`). O widget ATUALIZA `keys[i].t` (memória do chamador)
//!   e reporta `key_delta`.
//! - Vazio (área de tempo): press captura e faz pan horizontal, mantendo
//!   o instante "pego" sob o cursor; a janela fica em
//!   `[0, duration - largura/pps]`.
//! - Roda com hover: zoom em torno do cursor, usando o SINAL de `dy`
//!   (passo fixo `zoom_step`), clampado em `[min_pps, max_pps]`.
//! - Teclado com foco: setas movem o playhead por um passo da régua
//!   (fallback `duration / 10`), Home/End vão a 0/`duration`, Page
//!   Up/Down dão zoom no x do playhead, Tab circula o foco.
//! - Desenho: fundo, linhas de trilha (alternadas por `track_alt`),
//!   coluna de nomes, separadores, régua (grade + marcas + rótulos),
//!   chaves (losango em 4 `.line`) e playhead (linha + alça).
//! - `id` não-nulo obrigatório; índices fora de faixa em `state` são
//!   descartados.

const std = @import("std");
const types = @import("../core/types.zig");
const context_mod = @import("../core/context.zig");
const id_mod = @import("../core/id.zig");
const style_mod = @import("../style/style.zig");
const metrics_mod = @import("../text/metrics.zig");
const timeline_mod = @import("../timeline/view.zig");
const input = @import("input.zig");

/// Estado da timeline (dono: chamador; retido entre frames).
pub const TimelineViewState = struct {
    /// Transformação tempo↔tela (px/s na área de tempo).
    transform: timeline_mod.TimeTransform = .{},
    /// Duração total em segundos (> 0).
    duration: f32 = 10.0,
    /// Playhead em `[0, duration]`.
    playhead: f32 = 0.0,
    /// Chave selecionada (`null` = nenhuma).
    selected: ?timeline_mod.KeyRef = null,
    /// Modo de arraste ativo. Transiente.
    drag: TimelineDragMode = .none,
    /// Chave em arraste (quando `drag == .key`). Transiente.
    drag_key: ?timeline_mod.KeyRef = null,
    /// `t_mouse - t_chave` no início do arraste de chave. Transiente.
    drag_grab: f32 = 0.0,
    /// Instante "pego" no início do pan. Transiente.
    pan_time: f32 = 0.0,
};

/// Modo de arraste ativo.
pub const TimelineDragMode = enum { none, scrub, pan, key };

/// Opções de interação da timeline.
pub const TimelineViewOptions = struct {
    /// Zoom mínimo/máximo em px/s (`0 < min <= max`).
    min_pps: f32 = 4.0,
    max_pps: f32 = 4000.0,
    /// Fator multiplicativo por entrelinha da roda (> 0).
    zoom_step: f32 = 1.25,
    /// Ajusta chaves arrastadas ao passo da régua.
    snap_keys: bool = true,
    /// Tolerância de hit-test de chave em px de tela (>= 0).
    key_hit_px: f32 = 6.0,

    pub fn isValid(self: TimelineViewOptions) bool {
        if (!std.math.isFinite(self.min_pps) or !std.math.isFinite(self.max_pps)) return false;
        if (!(self.min_pps > 0) or self.max_pps < self.min_pps) return false;
        if (!std.math.isFinite(self.zoom_step) or self.zoom_step <= 0) return false;
        if (!std.math.isFinite(self.key_hit_px) or self.key_hit_px < 0) return false;
        return true;
    }
};

/// Resultado do frame.
pub const TimelineViewResult = struct {
    /// Trilha sob o cursor na área de tempo, se houver.
    hovered_track: ?usize = null,
    /// Chave sob o cursor (dentro da tolerância), se houver.
    hovered_key: ?timeline_mod.KeyRef = null,
    /// Chave selecionada ao fim do frame.
    selected: ?timeline_mod.KeyRef = null,
    /// Chave arrastada neste frame.
    dragging_key: ?timeline_mod.KeyRef = null,
    /// Deslocamento aplicado à chave arrastada neste frame (s).
    key_delta: f32 = 0.0,
    /// Playhead ao fim do frame (s).
    playhead: f32 = 0.0,
    /// Scrub do playhead ativo neste frame.
    scrubbing: bool = false,
    /// Pan aplicado neste frame (s).
    pan_delta: f32 = 0.0,
    /// Pan ativo neste frame.
    panning: bool = false,
    /// Zoom mudou neste frame (roda/teclado).
    zoom_changed: bool = false,
    /// Playhead, seleção, arraste, pan ou zoom mudou neste frame.
    changed: bool = false,
};

/// Máximo de marcações de régua por frame (guarda contra loops
/// patológicos em zoom extremo).
pub const max_ticks: u32 = 256;

/// Comprimento da marca de tick na régua (px).
const tick_mark_h: f32 = 4.0;

/// Recuo do rótulo em relação à marca (px).
const label_pad: f32 = 3.0;

/// Largura/altura da alça do playhead (px).
const playhead_handle_w: f32 = 10.0;
const playhead_handle_h: f32 = 10.0;

fn fill(
    ctx: *context_mod.Context,
    r: types.Rect,
    color: types.Color,
) context_mod.ContextError!void {
    try ctx.draw.rectFilled(ctx.allocator, r, color);
}

fn pushLabel(
    ctx: *context_mod.Context,
    pos: types.Vec2,
    color: types.Color,
    font: metrics_mod.FontMetrics,
    text: []const u8,
) context_mod.ContextError!void {
    ctx.draw.pushText(ctx.allocator, pos, color, font, text) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
        error.InvalidMetrics, error.InvalidUtf8 => return error.InvalidArgument,
    };
}

/// Desenha e interage com uma timeline em `bounds`.
/// Ver o cabeçalho do módulo para semântica de scrub/pan/zoom/arraste.
pub fn timelineView(
    ctx: *context_mod.Context,
    id: id_mod.Id,
    bounds: types.Rect,
    tracks: []timeline_mod.Track,
    state: *TimelineViewState,
    options: TimelineViewOptions,
    style: style_mod.TimelineStyle,
    font: metrics_mod.FontMetrics,
) context_mod.ContextError!TimelineViewResult {
    if (id.isNull()) return error.InvalidArgument;
    if (!style.isValid() or !font.isValid() or !options.isValid()) return error.InvalidArgument;
    if (!std.math.isFinite(bounds.x) or !std.math.isFinite(bounds.y) or
        !std.math.isFinite(bounds.w) or !std.math.isFinite(bounds.h))
    {
        return error.InvalidArgument;
    }
    if (bounds.w <= 0 or bounds.h <= 0) return error.InvalidArgument;
    if (!timeline_mod.TimeTransform.isValid(state.transform)) return error.InvalidArgument;
    if (!std.math.isFinite(state.duration) or state.duration <= 0) return error.InvalidArgument;
    if (!std.math.isFinite(state.playhead)) return error.InvalidArgument;
    for (tracks) |tr| {
        for (tr.keys) |k| {
            if (!k.isValid()) return error.InvalidArgument;
        }
    }

    // Coluna de nomes (empurra a origem da área de tempo).
    const names_w = std.math.clamp(style.name_width, 0, bounds.w);
    const area_x = bounds.x + names_w;
    const area_w = bounds.w - names_w;
    if (area_w <= 0) return error.InvalidArgument;

    // Sanidade: playhead na duração; janela dentro de `[0, duration]`.
    state.playhead = timeline_mod.clampTime(state.playhead, state.duration);
    state.transform = state.transform.clampStart(area_w, state.duration);
    if (state.selected) |s| {
        if (!s.isAlive(tracks)) state.selected = null;
    }
    if (state.drag_key) |d| {
        if (!d.isAlive(tracks)) state.drag_key = null;
    }

    const ruler_h = @min(style.ruler_height, bounds.h);
    const rows_top = bounds.y + ruler_h;
    const bottom = bounds.y + bounds.h;
    const row_h = style.row_height;

    const tick = timeline_mod.tickStep(state.transform.pps, style.min_tick_px);
    const tol_s = options.key_hit_px / state.transform.pps;
    const key_slack_s = (style.key_size * 2) / state.transform.pps;

    var res = TimelineViewResult{ .selected = state.selected };
    const fm = input.FrameMouse.scan(ctx.pendingEvents());
    const inside = if (ctx.mouse_pos) |p| bounds.contains(p) else false;
    try ctx.registerFocusable(id);

    // Hover: trilha/chave sob o cursor (só na área de tempo).
    if (inside) {
        if (ctx.mouse_pos) |p| {
            if (p.y >= rows_top and p.x >= area_x) {
                if (timeline_mod.trackAtY(p.y - rows_top, row_h, tracks.len)) |ti| {
                    res.hovered_track = ti;
                    const t = state.transform.xToTime(p.x - area_x);
                    if (timeline_mod.nearestKey(tracks[ti], t, tol_s)) |ki| {
                        res.hovered_key = .{ .track = @intCast(ti), .key = @intCast(ki) };
                    }
                }
            }
        }
    }

    // Press: régua scruba; chave arrasta; vazio dá pan.
    if (ctx.press_owner == null and fm.pressedInside(bounds)) {
        if (ctx.mouse_pos) |p| {
            if (p.y < rows_top) {
                ctx.press_owner = id;
                ctx.focus_owner = id;
                state.drag = .scrub;
                const t = timeline_mod.clampTime(
                    state.transform.xToTime(p.x - area_x),
                    state.duration,
                );
                if (t != state.playhead) {
                    state.playhead = t;
                    res.changed = true;
                }
                res.scrubbing = true;
            } else if (p.x >= area_x) {
                ctx.press_owner = id;
                ctx.focus_owner = id;
                if (res.hovered_key) |kr| {
                    state.drag = .key;
                    state.drag_key = kr;
                    state.drag_grab = state.transform.xToTime(p.x - area_x) -
                        tracks[kr.track].keys[kr.key].t;
                    if (state.selected == null or !state.selected.?.eql(kr)) {
                        state.selected = kr;
                        res.selected = kr;
                        res.changed = true;
                    }
                } else {
                    state.drag = .pan;
                    state.pan_time = state.transform.xToTime(p.x - area_x);
                }
            }
        }
    }

    // Arraste (enquanto dono da captura).
    if (ctx.press_owner == id) {
        if (ctx.mouse_down_left) {
            if (ctx.mouse_pos) |p| {
                switch (state.drag) {
                    .scrub => {
                        const t = timeline_mod.clampTime(
                            state.transform.xToTime(p.x - area_x),
                            state.duration,
                        );
                        if (t != state.playhead) {
                            state.playhead = t;
                            res.changed = true;
                        }
                        res.scrubbing = true;
                    },
                    .pan => {
                        const before = state.transform.start;
                        var tr = state.transform;
                        tr.start = state.pan_time - (p.x - area_x) / tr.pps;
                        tr = tr.clampStart(area_w, state.duration);
                        if (tr.start != before) {
                            state.transform = tr;
                            res.pan_delta = tr.start - before;
                            res.changed = true;
                        }
                        res.panning = true;
                    },
                    .key => {
                        if (state.drag_key) |kr| {
                            if (kr.isAlive(tracks)) {
                                res.dragging_key = kr;
                                var nt = state.transform.xToTime(p.x - area_x) - state.drag_grab;
                                if (options.snap_keys) nt = timeline_mod.snapTime(nt, tick);
                                nt = timeline_mod.clampTime(nt, state.duration);
                                const key = &tracks[kr.track].keys[kr.key];
                                if (nt != key.t) {
                                    res.key_delta = nt - key.t;
                                    key.t = nt;
                                    res.changed = true;
                                }
                            }
                        }
                    },
                    .none => {},
                }
            }
        }
        if (fm.released_pos != null) {
            ctx.press_owner = null;
            state.drag = .none;
            state.drag_key = null;
            res.dragging_key = null;
        }
    }

    // Roda com hover: zoom em torno do cursor (usa o sinal de `dy`).
    if (inside) {
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
            const before = state.transform.pps;
            var tr = state.transform.zoomAt(
                w.pos.x - area_x,
                factor,
                options.min_pps,
                options.max_pps,
            );
            if (tr.pps == before) continue; // já no limite
            tr = tr.clampStart(area_w, state.duration);
            state.transform = tr;
            res.zoom_changed = true;
            res.changed = true;
        }
    }

    // Teclado com foco (setas/Home/End/Page Up/Down/Tab).
    if (ctx.hasFocus(id)) {
        const anchor_x = std.math.clamp(state.transform.timeToX(state.playhead), 0, area_w);
        for (ctx.pendingEvents()) |ev| {
            if (ev != .key) continue;
            const k = ev.key;
            if (!k.pressed or k.modifiers.ctrl) continue;
            switch (k.key) {
                .left, .right => {
                    const step = if (tick > 0) tick else state.duration / 10;
                    const dir: f32 = if (k.key == .left) -1 else 1;
                    const t = timeline_mod.clampTime(state.playhead + dir * step, state.duration);
                    if (t != state.playhead) {
                        state.playhead = t;
                        res.changed = true;
                    }
                },
                .home => {
                    if (state.playhead != 0) {
                        state.playhead = 0;
                        res.changed = true;
                    }
                },
                .end => {
                    if (state.playhead != state.duration) {
                        state.playhead = state.duration;
                        res.changed = true;
                    }
                },
                .page_up, .page_down => {
                    const factor: f32 = if (k.key == .page_up)
                        options.zoom_step
                    else
                        1.0 / options.zoom_step;
                    const before = state.transform.pps;
                    var tr = state.transform.zoomAt(
                        anchor_x,
                        factor,
                        options.min_pps,
                        options.max_pps,
                    );
                    if (tr.pps == before) continue; // já no limite
                    tr = tr.clampStart(area_w, state.duration);
                    state.transform = tr;
                    res.zoom_changed = true;
                    res.changed = true;
                },
                .tab => ctx.requestFocusAdvance(if (k.modifiers.shift) .prev else .next),
                else => {},
            }
        }
    }
    res.playhead = state.playhead;

    // --- Desenho (clipado em `bounds`) ---
    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = bounds, .null_rect = false } });

    if (style.bg.a != 0) try fill(ctx, bounds, style.bg);

    // Linhas de trilha (fundo alternado).
    var ri: usize = 0;
    while (ri < tracks.len) : (ri += 1) {
        const ry = rows_top + @as(f32, @floatFromInt(ri)) * row_h;
        if (ry >= bottom) break;
        const h = @min(row_h, bottom - ry);
        if (h <= 0) break;
        const alt = style.track_alt.a != 0 and (ri % 2 == 1);
        const bgc = if (alt) style.track_alt else style.track_bg;
        if (bgc.a != 0) {
            try fill(ctx, .{ .x = bounds.x, .y = ry, .w = bounds.w, .h = h }, bgc);
        }
    }

    // Coluna de nomes (sobre as trilhas).
    if (names_w > 0 and style.names_bg.a != 0 and rows_top < bottom) {
        try fill(
            ctx,
            .{ .x = bounds.x, .y = rows_top, .w = names_w, .h = bottom - rows_top },
            style.names_bg,
        );
    }

    // Separadores entre trilhas.
    if (style.separator.a != 0) {
        ri = 1;
        while (ri < tracks.len) : (ri += 1) {
            const ry = rows_top + @as(f32, @floatFromInt(ri)) * row_h;
            if (ry >= bottom) break;
            try ctx.draw.line(
                ctx.allocator,
                .{ .x = bounds.x, .y = ry },
                .{ .x = bounds.x + bounds.w, .y = ry },
                style.separator,
                1.0,
            );
        }
    }

    // Faixa da régua.
    if (ruler_h > 0 and style.ruler_bg.a != 0) {
        try fill(ctx, .{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = ruler_h }, style.ruler_bg);
    }

    // Nomes das trilhas (na coluna).
    if (names_w > 0 and style.track_name.a != 0) {
        ri = 0;
        while (ri < tracks.len) : (ri += 1) {
            const ry = rows_top + @as(f32, @floatFromInt(ri)) * row_h;
            if (ry >= bottom) break;
            const name = tracks[ri].name;
            if (name.len == 0) continue;
            const h = @min(row_h, bottom - ry);
            const ty = ry + @max(0, (h - font.lineHeight()) / 2);
            try pushLabel(
                ctx,
                .{ .x = bounds.x + style.name_pad, .y = ty },
                style.track_name,
                font,
                name,
            );
        }
    }

    // --- Área de tempo (régua + trilhas + chaves + playhead) ---
    const tr = state.transform;
    const vr = tr.visibleRange(area_w);
    try ctx.draw.push(ctx.allocator, .{ .clip = .{
        .rect = .{ .x = area_x, .y = bounds.y, .w = area_w, .h = bounds.h },
        .null_rect = false,
    } });

    if (tick > 0) {
        const rows_h = bottom - rows_top;
        const mark_h = @min(tick_mark_h, ruler_h);
        const label_y = bounds.y + @max(0, (ruler_h - font.lineHeight()) / 2);
        var tk = @ceil(vr.t0 / tick) * tick;
        var n: u32 = 0;
        while (tk <= vr.t1 + tick * 0.5 and n < max_ticks) : ({
            tk += tick;
            n += 1;
        }) {
            const x = area_x + tr.timeToX(tk);
            if (style.tick.a != 0) {
                if (rows_h > 0) {
                    try ctx.draw.line(
                        ctx.allocator,
                        .{ .x = x, .y = rows_top },
                        .{ .x = x, .y = bottom },
                        style.tick,
                        1.0,
                    );
                }
                if (mark_h > 0) {
                    try ctx.draw.line(
                        ctx.allocator,
                        .{ .x = x, .y = bounds.y + ruler_h - mark_h },
                        .{ .x = x, .y = bounds.y + ruler_h },
                        style.tick,
                        1.0,
                    );
                }
            }
            if (style.tick_label.a != 0) {
                var buf: [32]u8 = undefined;
                const len = timeline_mod.formatLabel(&buf, tk, tick);
                if (len > 0) {
                    try pushLabel(
                        ctx,
                        .{ .x = x + label_pad, .y = label_y },
                        style.tick_label,
                        font,
                        buf[0..len],
                    );
                }
            }
        }
    }

    // Chaves (losango em 4 segmentos; a última é desenhada por cima).
    const half = style.key_size;
    if (half > 0 and (style.key.a != 0 or style.key_selected.a != 0)) {
        var ti: usize = 0;
        while (ti < tracks.len) : (ti += 1) {
            const ry = rows_top + @as(f32, @floatFromInt(ti)) * row_h;
            if (ry >= bottom) break;
            const cy = ry + @min(row_h, bottom - ry) / 2;
            for (tracks[ti].keys, 0..) |kf, ki| {
                if (!kf.isValid()) continue;
                if (kf.t < vr.t0 - key_slack_s or kf.t > vr.t1 + key_slack_s) continue;
                const cx = area_x + tr.timeToX(kf.t);
                if (cx < area_x - half or cx > area_x + area_w + half) continue;
                const sel = if (state.selected) |s| s.track == ti and s.key == ki else false;
                const color = if (sel) style.key_selected else style.key;
                if (color.a == 0) continue;
                const top = types.Vec2.init(cx, cy - half);
                const right = types.Vec2.init(cx + half, cy);
                const bot = types.Vec2.init(cx, cy + half);
                const left = types.Vec2.init(cx - half, cy);
                try ctx.draw.line(ctx.allocator, top, right, color, style.key_line_width);
                try ctx.draw.line(ctx.allocator, right, bot, color, style.key_line_width);
                try ctx.draw.line(ctx.allocator, bot, left, color, style.key_line_width);
                try ctx.draw.line(ctx.allocator, left, top, color, style.key_line_width);
            }
        }
    }

    // Playhead (linha + alça).
    if (style.playhead.a != 0) {
        const px = area_x + tr.timeToX(state.playhead);
        if (px >= area_x - 1 and px <= area_x + area_w + 1) {
            try ctx.draw.line(
                ctx.allocator,
                .{ .x = px, .y = bounds.y },
                .{ .x = px, .y = bottom },
                style.playhead,
                style.playhead_width,
            );
            const hh = @min(playhead_handle_h, ruler_h);
            const hw = @min(playhead_handle_w, area_w);
            if (hh > 0 and hw > 0) {
                try fill(
                    ctx,
                    .{ .x = px - hw / 2, .y = bounds.y, .w = hw, .h = hh },
                    style.playhead,
                );
            }
        }
    }

    try ctx.draw.push(ctx.allocator, .{ .clip = .{ .rect = .{}, .null_rect = true } });

    return res;
}

fn testStyle() style_mod.TimelineStyle {
    return .{
        .bg = types.Color.rgb(10, 10, 10),
        .ruler_bg = types.Color.rgb(30, 30, 40),
        .ruler_height = 20,
        .tick = types.Color.rgb(120, 120, 130),
        .tick_label = types.Color.rgb(255, 255, 255),
        .min_tick_px = 20,
        .track_bg = types.Color.rgb(40, 40, 50),
        .track_alt = types.Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .name_width = 0,
        .names_bg = types.Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .track_name = types.Color.rgb(230, 230, 230),
        .name_pad = 6,
        .separator = types.Color.rgb(70, 70, 80),
        .row_height = 20,
        .key = types.Color.rgb(255, 190, 70),
        .key_selected = types.Color.rgb(255, 255, 255),
        .key_size = 6,
        .key_line_width = 1.5,
        .playhead = types.Color.rgb(230, 80, 80),
        .playhead_width = 1.5,
    };
}

/// Chaves do teste (trilha 0): t = 2 e t = 5.
fn testTracks(keys: *[2]timeline_mod.Keyframe) [1]timeline_mod.Track {
    keys[0] = .{ .t = 2 };
    keys[1] = .{ .t = 5 };
    return .{.{ .keys = keys }};
}

test "timeline: hover, scrub na régua e seleção de chave" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-scrub");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys: [2]timeline_mod.Keyframe = undefined;
    var tracks = testTracks(&keys);
    // pps 20 ⇒ t=2 em x=40, t=5 em x=100.
    var st = TimelineViewState{ .duration = 10, .transform = .{ .pps = 20 } };

    // Frame 1: hover sobre a chave t=2 (linha 0: y 20..40).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(40, 30) } });
    const r0 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?usize, 0), r0.hovered_track);
    try stdt.testing.expectEqual(@as(?timeline_mod.KeyRef, .{ .track = 0, .key = 0 }), r0.hovered_key);
    try stdt.testing.expect(!r0.changed);
    ctx.endFrame();

    // Frame 2: press na régua (y 0..20) ⇒ scrub para t = 3.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(60, 10),
    } });
    const r1 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(r1.scrubbing);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(f32, 3), r1.playhead);
    try stdt.testing.expectEqual(@as(f32, 3), st.playhead);
    try stdt.testing.expect(ctx.hasFocus(id));
    ctx.endFrame();

    // Frame 3: arraste na régua para além da duração ⇒ clampa em 10.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(400, 10) } });
    const r2 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(r2.scrubbing);
    try stdt.testing.expectEqual(@as(f32, 10), st.playhead);
    ctx.endFrame();

    // Frame 4: release encerra o scrub.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(400, 10),
    } });
    const r3 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(!r3.scrubbing);
    try stdt.testing.expect(ctx.press_owner == null);
    try stdt.testing.expectEqual(TimelineDragMode.none, st.drag);
    ctx.endFrame();

    // Frame 5: press na chave t=5 ⇒ seleciona (sem mover ainda).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(100, 30),
    } });
    const r4 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(r4.changed);
    try stdt.testing.expectEqual(@as(?timeline_mod.KeyRef, .{ .track = 0, .key = 1 }), st.selected);
    try stdt.testing.expectEqual(@as(?timeline_mod.KeyRef, .{ .track = 0, .key = 1 }), r4.dragging_key);
    try stdt.testing.expectEqual(@as(f32, 0), r4.key_delta);
    try stdt.testing.expectEqual(@as(f32, 5), keys[1].t);
    try stdt.testing.expectEqual(TimelineDragMode.key, st.drag);
    ctx.endFrame();
}

test "timeline: arraste de chave com snap ao passo e clamp" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-keydrag");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys: [2]timeline_mod.Keyframe = undefined;
    var tracks = testTracks(&keys);
    var st = TimelineViewState{ .duration = 10, .transform = .{ .pps = 20 } };

    // Press exatamente na chave t=2 (x=40, linha 0).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(40, 30),
    } });
    _ = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    ctx.endFrame();

    // +10 px ⇒ t = 2.5 ⇒ snap (passo 1) ⇒ 3.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(50, 30) } });
    const r0 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 1), r0.key_delta);
    try stdt.testing.expectEqual(@as(f32, 3), keys[0].t);
    try stdt.testing.expect(r0.changed);
    ctx.endFrame();

    // Além do fim ⇒ clampa em `duration`.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(500, 30) } });
    const r1 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 10), keys[0].t);
    try stdt.testing.expectEqual(@as(f32, 7), r1.key_delta);
    ctx.endFrame();

    // Antes do início ⇒ clampa em 0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(-100, 30) } });
    const r2 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 0), keys[0].t);
    try stdt.testing.expectEqual(@as(f32, -10), r2.key_delta);
    ctx.endFrame();

    // Sem snap: a posição segue o cursor (t = 1.25).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(25, 30) } });
    const r3 = try timelineView(&ctx, id, bounds, &tracks, &st, .{ .snap_keys = false }, style, font);
    try stdt.testing.expectEqual(@as(f32, 1.25), keys[0].t);
    try stdt.testing.expectEqual(@as(f32, 1.25), r3.key_delta);
    ctx.endFrame();

    // Release libera a captura; a chave arrastada sai do resultado.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(25, 30),
    } });
    const r4 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(?timeline_mod.KeyRef, null), r4.dragging_key);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();
}

test "timeline: pan mantém o instante pego e respeita a janela" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-pan");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys: [2]timeline_mod.Keyframe = undefined;
    var tracks = testTracks(&keys);
    // pps 20, largura 200 ⇒ janela de 10 s numa duração de 20 s.
    var st = TimelineViewState{ .duration = 20, .transform = .{ .pps = 20 } };

    // Press no vazio (x=150, linha 0) ⇒ pan; pega t = 7.5.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(150, 30),
    } });
    const r0 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(r0.panning);
    try stdt.testing.expectEqual(TimelineDragMode.pan, st.drag);
    try stdt.testing.expectEqual(@as(f32, 7.5), st.pan_time);
    try stdt.testing.expectEqual(@as(f32, 0), r0.pan_delta);
    ctx.endFrame();

    // Solta o cursor para x=100: o instante 7.5 fica sob o cursor ⇒ start = 2.5.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(100, 30) } });
    const r1 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 2.5), st.transform.start);
    try stdt.testing.expectEqual(@as(f32, 2.5), r1.pan_delta);
    try stdt.testing.expectEqual(@as(f32, 100), st.transform.timeToX(7.5));
    try stdt.testing.expect(r1.changed);
    ctx.endFrame();

    // Além do fim: a janela clampa em `duration - span` = 10 s.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(-400, 30) } });
    const r2 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 10), st.transform.start);
    try stdt.testing.expectEqual(@as(f32, 7.5), r2.pan_delta);
    ctx.endFrame();

    // Antes do início: clampa em 0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_move = .{ .pos = types.Vec2.init(400, 30) } });
    _ = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expectEqual(@as(f32, 0), st.transform.start);
    ctx.endFrame();

    // Release.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(400, 30),
    } });
    const r3 = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(!r3.panning);
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();
}

test "timeline: zoom pela roda mantém o cursor e clampa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-zoom");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys: [2]timeline_mod.Keyframe = undefined;
    var tracks = testTracks(&keys);
    var st = TimelineViewState{ .duration = 10, .playhead = 2.5, .transform = .{ .pps = 20 } };
    const cursor = types.Vec2.init(50, 30);
    const opts = TimelineViewOptions{ .min_pps = 10, .max_pps = 40 };

    // Roda "para cima": pps 20 ⇒ 25; o instante 2.5 fica em x = 50.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1, .pos = cursor } });
    const r0 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r0.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 25), st.transform.pps);
    try stdt.testing.expectApproxEqAbs(@as(f32, 50), st.transform.timeToX(2.5), 1e-3);
    ctx.endFrame();

    // Muitos passos para cima ⇒ clampa no máximo (40).
    ctx.beginFrame();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1, .pos = cursor } });
    }
    const r1 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r1.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 40), st.transform.pps);
    try stdt.testing.expectApproxEqAbs(@as(f32, 50), st.transform.timeToX(2.5), 1e-3);
    ctx.endFrame();

    // Já no máximo: nenhuma mudança.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1, .pos = cursor } });
    const r2 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(!r2.zoom_changed);
    try stdt.testing.expect(!r2.changed);
    ctx.endFrame();

    // Muitos passos para baixo ⇒ clampa no mínimo (10); span 20 > 10 ⇒ start 0.
    ctx.beginFrame();
    i = 0;
    while (i < 12) : (i += 1) {
        try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = -1, .pos = cursor } });
    }
    const r3 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r3.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 10), st.transform.pps);
    try stdt.testing.expectEqual(@as(f32, 0), st.transform.start);
    ctx.endFrame();

    // Fora do hover a roda é ignorada.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_wheel = .{ .dx = 0, .dy = 1, .pos = types.Vec2.init(500, 500) } });
    const r4 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(!r4.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 10), st.transform.pps);
    ctx.endFrame();
}

test "timeline: teclado (setas, Home/End, Page Up/Down, Tab)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-keys");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys: [2]timeline_mod.Keyframe = undefined;
    var tracks = testTracks(&keys);
    var st = TimelineViewState{ .duration = 10, .transform = .{ .pps = 20 } };
    const opts = TimelineViewOptions{ .min_pps = 10, .max_pps = 40 };

    // Press+release no vazio (x=150 é longe das chaves) focam o widget.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = true,
        .pos = types.Vec2.init(150, 60),
    } });
    try ctx.pushEvent(.{ .mouse_button = .{
        .button = .left,
        .pressed = false,
        .pos = types.Vec2.init(150, 60),
    } });
    _ = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(ctx.hasFocus(id));
    try stdt.testing.expect(ctx.press_owner == null);
    ctx.endFrame();

    // Setas: passo da régua (pps 20 / alvo 20 px ⇒ 1 s).
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{} } });
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    // Solta não deve repetir a ação.
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = false, .modifiers = .{} } });
    const r0 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r0.changed);
    try stdt.testing.expectEqual(@as(f32, 1), r0.playhead);
    try stdt.testing.expectEqual(@as(f32, 1), st.playhead);
    ctx.endFrame();

    // Não desce abaixo de 0.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .left, .pressed = true, .modifiers = .{} } });
    const r1 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r1.changed);
    try stdt.testing.expectEqual(@as(f32, 0), st.playhead);
    ctx.endFrame();

    // End/Home vão aos extremos.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .end, .pressed = true, .modifiers = .{} } });
    const r2 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(f32, 10), st.playhead);
    try stdt.testing.expect(r2.changed);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .home, .pressed = true, .modifiers = .{} } });
    const r3 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expectEqual(@as(f32, 0), st.playhead);
    try stdt.testing.expect(r3.changed);
    ctx.endFrame();

    // Page Up dá zoom ancorado no playhead (x = 0 ⇒ start 0); Page Down volta.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_up, .pressed = true, .modifiers = .{} } });
    const r4 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r4.zoom_changed);
    try stdt.testing.expectEqual(@as(f32, 25), st.transform.pps);
    try stdt.testing.expectEqual(@as(f32, 0), st.transform.start);
    ctx.endFrame();

    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .page_down, .pressed = true, .modifiers = .{} } });
    const r5 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(r5.zoom_changed);
    try stdt.testing.expectApproxEqAbs(@as(f32, 20), st.transform.pps, 1e-3);
    ctx.endFrame();

    // Ctrl+seta é ignorado (atalho do host); Tab agenda o avanço de foco.
    ctx.beginFrame();
    try ctx.pushEvent(.{ .key = .{ .key = .right, .pressed = true, .modifiers = .{ .ctrl = true } } });
    try ctx.pushEvent(.{ .key = .{ .key = .tab, .pressed = true, .modifiers = .{ .shift = true } } });
    const r6 = try timelineView(&ctx, id, bounds, &tracks, &st, opts, style, font);
    try stdt.testing.expect(!r6.changed);
    try stdt.testing.expectEqual(@as(f32, 0), st.playhead);
    try stdt.testing.expect(ctx.pending_focus_advance != null);
    ctx.endFrame();
}

test "timeline: desenho (clip, régua, trilhas, chaves e playhead)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var style = testStyle();
    style.name_width = 60;
    style.names_bg = types.Color.rgb(20, 20, 20);
    style.min_tick_px = 50;
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-draw");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys0 = [_]timeline_mod.Keyframe{ .{ .t = 2 }, .{ .t = 8 } };
    var tracks = [_]timeline_mod.Track{
        .{ .name = "a", .keys = &keys0 },
        .{ .name = "b" },
    };
    // Área de tempo: 140 px; pps 14 ⇒ janela 10 s = duração.
    var st = TimelineViewState{ .duration = 10, .playhead = 5, .transform = .{ .pps = 14 } };

    ctx.beginFrame();
    const r = try timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, font);
    try stdt.testing.expect(!r.changed);
    try stdt.testing.expectEqual(@as(f32, 5), r.playhead);

    const cmds = ctx.drawCommands();
    // Primeiro comando: clip em `bounds`; último: remoção do clip.
    try stdt.testing.expect(cmds[0] == .clip);
    try stdt.testing.expect(!cmds[0].clip.null_rect);
    try stdt.testing.expectEqual(@as(f32, 200), cmds[0].clip.rect.w);
    try stdt.testing.expect(cmds[cmds.len - 1] == .clip);
    try stdt.testing.expect(cmds[cmds.len - 1].clip.null_rect);

    var fills: usize = 0;
    var texts: usize = 0;
    var lines: usize = 0;
    var clips: usize = 0;
    var text_slices: [8][]const u8 = undefined;
    var text_count: usize = 0;
    var last_text_at: usize = 0;
    for (cmds, 0..) |c, ci| {
        switch (c) {
            .rect_filled => fills += 1,
            .text => {
                if (text_count < text_slices.len) {
                    text_slices[text_count] = ctx.draw.textOf(c);
                    text_count += 1;
                }
                texts += 1;
                last_text_at = ci;
            },
            .line => lines += 1,
            .clip => {
                // A 2ª clipa a área de tempo (x=60, largura 140).
                if (clips == 1) {
                    try stdt.testing.expect(!c.clip.null_rect);
                    try stdt.testing.expectEqual(@as(f32, 60), c.clip.rect.x);
                    try stdt.testing.expectEqual(@as(f32, 140), c.clip.rect.w);
                }
                clips += 1;
            },
            else => {},
        }
    }
    // 3 clips (bounds + área de tempo + remoção) e nenhum outro comando.
    try stdt.testing.expectEqual(@as(usize, 3), clips);
    try stdt.testing.expectEqual(@as(usize, 30), cmds.len);
    // Preenchimentos: fundo + 2 linhas de trilha + coluna de nomes + régua + alça.
    try stdt.testing.expectEqual(@as(usize, 6), fills);
    // Textos: 2 nomes + 3 rótulos (t = 0, 5, 10).
    try stdt.testing.expectEqual(@as(usize, 5), texts);
    try stdt.testing.expectEqualStrings("a", text_slices[0]);
    try stdt.testing.expectEqualStrings("b", text_slices[1]);
    try stdt.testing.expectEqualStrings("0:00", text_slices[2]);
    try stdt.testing.expectEqualStrings("0:05", text_slices[3]);
    try stdt.testing.expectEqualStrings("0:10", text_slices[4]);
    // O rótulo de t = 10 fica na borda direita da área de tempo (x=200).
    try stdt.testing.expectEqual(@as(f32, 203), cmds[last_text_at].text.pos.x);
    // Linhas: 3 grades + 3 marcas de régua + 1 separador + 2 chaves × 4 + playhead.
    try stdt.testing.expectEqual(@as(usize, 16), lines);
    ctx.endFrame();
}

test "timeline: contratos inválidos e índices fora de faixa" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const style = testStyle();
    const font = metrics_mod.FontMetrics.withSize(10);
    var ctx = try context_mod.Context.init(gpa, .{});
    defer ctx.deinit();
    const id = id_mod.Id.fromString("test:timeline-bad");
    const bounds = types.Rect.init(0, 0, 200, 100);
    var keys: [2]timeline_mod.Keyframe = undefined;
    var tracks = testTracks(&keys);
    var st = TimelineViewState{ .duration = 10, .transform = .{ .pps = 20 } };

    ctx.beginFrame();
    // id nulo
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, .null, bounds, &tracks, &st, .{}, style, font));
    // bounds inválidos
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, types.Rect.init(0, 0, 0, 10), &tracks, &st, .{}, style, font));
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, types.Rect.init(0, 0, 10, std.math.nan(f32)), &tracks, &st, .{}, style, font));
    // estilo / fonte / opções
    var bad_style = style;
    bad_style.row_height = 0;
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &st, .{}, bad_style, font));
    var bad_style2 = style;
    bad_style2.key_line_width = 0;
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &st, .{}, bad_style2, font));
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &st, .{ .min_pps = 40, .max_pps = 10 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &st, .{ .key_hit_px = -1 }, style, font));
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &st, .{}, style, metrics_mod.FontMetrics{ .size = 0 }));
    // duração / transformação inválidas
    var bad_dur = TimelineViewState{ .duration = 0 };
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &bad_dur, .{}, style, font));
    var bad_pps = TimelineViewState{ .transform = .{ .pps = 0 } };
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &bad_pps, .{}, style, font));
    // chave inválida
    var bad_keys = [_]timeline_mod.Keyframe{.{ .t = std.math.nan(f32) }};
    const bad_tracks = [_]timeline_mod.Track{.{ .keys = &bad_keys }};
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, @constCast(&bad_tracks), &st, .{}, style, font));
    // coluna de nomes consome toda a largura
    var wide = style;
    wide.name_width = 200;
    try stdt.testing.expectError(error.InvalidArgument, timelineView(&ctx, id, bounds, &tracks, &st, .{}, wide, font));

    // Índices fora de faixa são descartados (dono removeu a chave).
    var st2 = TimelineViewState{
        .duration = 10,
        .playhead = 99,
        .selected = .{ .track = 0, .key = 9 },
        .drag = .key,
        .drag_key = .{ .track = 4, .key = 0 },
    };
    _ = try timelineView(&ctx, id, bounds, &tracks, &st2, .{}, style, font);
    try stdt.testing.expectEqual(@as(?timeline_mod.KeyRef, null), st2.selected);
    try stdt.testing.expectEqual(@as(?timeline_mod.KeyRef, null), st2.drag_key);
    // O playhead é clampado na duração.
    try stdt.testing.expectEqual(@as(f32, 10), st2.playhead);
    ctx.endFrame();
}
