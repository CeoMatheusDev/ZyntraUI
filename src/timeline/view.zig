//! ZyntraUI — modelo puro de timeline (timeline/view).
//!
//! Sem `Context` e sem alocação: transformação tempo↔tela, passos da
//! régua ("canônicos"), formatação de rótulos, trilhas/chaves e
//! hit-test. O widget `widgets/timeline` consome este módulo.
//!
//! Convenções:
//! - `TimeTransform`: `x_local = (t - start) * pps`, com `pps > 0` px por
//!   segundo; `x_local` é relativo à borda esquerda da ÁREA de tempo (o
//!   widget soma a origem). `start` é o instante nessa borda.
//! - Tempos: `[0, duration]`; negativos clampam em 0.
//! - Passos da régua: lista canônica de segundos (10 ms … 1 h); escolhe
//!   o menor cujo espaçamento em tela seja >= `min_px`.
//! - Rótulos: `m:ss`, `h:mm:ss` (passo >= 1 s) ou `s.d` (passo < 1 s),
//!   formatados com aritmética inteira (determinístico).
//! - Índices fora de faixa são sempre tratados como ausentes.

const std = @import("std");
const types = @import("../core/types.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;

/// Transformação linear tempo↔tela (escala + deslocamento).
pub const TimeTransform = struct {
    /// Instante (s) na borda esquerda da área de tempo.
    start: f32 = 0,
    /// Escala em px de tela por segundo (> 0).
    pps: f32 = 80,

    pub fn isValid(self: TimeTransform) bool {
        return std.math.isFinite(self.start) and
            std.math.isFinite(self.pps) and self.pps > 0;
    }

    /// X local (0 = borda esquerda da área) do instante `t`.
    pub fn timeToX(self: TimeTransform, t: f32) f32 {
        return (t - self.start) * self.pps;
    }

    /// Instante (s) no x local `x`.
    pub fn xToTime(self: TimeTransform, x: f32) f32 {
        return self.start + x / self.pps;
    }

    /// Duração (s) visível numa área de largura `width` (px).
    pub fn visibleSpan(self: TimeTransform, width: f32) f32 {
        return width / self.pps;
    }

    /// Intervalo visível `[t0, t1]` numa área de largura `width`.
    pub fn visibleRange(self: TimeTransform, width: f32) Range {
        const span = self.visibleSpan(width);
        return .{ .t0 = self.start, .t1 = self.start + span };
    }

    /// Escala `pps` por `factor` mantendo o instante sob `anchor_x`
    /// (local) fixo, com clamp em `[lo, hi]`. Devolve `self` se algo for
    /// inválido.
    pub fn zoomAt(self: TimeTransform, anchor_x: f32, factor: f32, lo: f32, hi: f32) TimeTransform {
        if (!self.isValid()) return self;
        if (!std.math.isFinite(anchor_x)) return self;
        if (!std.math.isFinite(factor) or factor <= 0) return self;
        if (!std.math.isFinite(lo) or !std.math.isFinite(hi)) return self;
        const pps = std.math.clamp(self.pps * factor, @min(lo, hi), @max(lo, hi));
        if (!std.math.isFinite(pps) or pps <= 0) return self;
        const t = self.xToTime(anchor_x);
        return .{ .start = t - anchor_x / pps, .pps = pps };
    }

    /// Restringe `start` ao intervalo `[0, duration - span]` (span =
    /// `width / pps`), mantendo o fim da janela dentro de `duration`.
    /// Quando a janela é maior que `duration`, `start` vai a 0.
    pub fn clampStart(self: TimeTransform, width: f32, duration: f32) TimeTransform {
        if (!self.isValid()) return self;
        if (!std.math.isFinite(width) or width <= 0) return self;
        if (!std.math.isFinite(duration) or duration < 0) return self;
        const span = self.visibleSpan(width);
        const max_start = @max(0, duration - span);
        return .{ .start = std.math.clamp(self.start, 0, max_start), .pps = self.pps };
    }
};

/// Intervalo de tempo (s).
pub const Range = struct { t0: f32 = 0, t1: f32 = 0 };

/// Passos canônicos da régua, em segundos (10 ms … 1 h).
pub const tick_steps = [_]f32{
    0.01, 0.02, 0.05, 0.1, 0.2,  0.5,
    1,    2,    5,    10,  15,   30,
    60,   120,  300,  600, 1800, 3600,
};

/// Menor passo canônico (s) cujo espaçamento em tela seja >= `min_px`.
/// Devolve `0` (sem régua) para `pps`/`min_px` não-positivos ou
/// não-finitos; se nenhum passo couber, devolve o maior (1 h).
pub fn tickStep(pps: f32, min_px: f32) f32 {
    if (!std.math.isFinite(pps) or pps <= 0) return 0;
    if (!std.math.isFinite(min_px) or min_px <= 0) return 0;
    for (tick_steps) |s| {
        if (s * pps >= min_px) return s;
    }
    return tick_steps[tick_steps.len - 1];
}

/// Clampa `t` (s) em `[0, duration]`; `duration` inválida ⇒ 0.
pub fn clampTime(t: f32, duration: f32) f32 {
    if (!std.math.isFinite(t)) return 0;
    if (!std.math.isFinite(duration) or duration <= 0) return 0;
    return std.math.clamp(t, 0, duration);
}

/// Ajusta `t` (s) ao múltiplo mais próximo de `step`
/// (passo <= 0 ou inválido ⇒ devolve `t` inalterado).
pub fn snapTime(t: f32, step: f32) f32 {
    if (!std.math.isFinite(t)) return t;
    if (!std.math.isFinite(step) or step <= 0) return t;
    return @round(t / step) * step;
}

/// Formata o instante `t` (s) em `buf` como rótulo compacto:
/// `m:ss` / `h:mm:ss` para `step >= 1`, ou `s.d` (uma casa) para
/// `step < 1`. Devolve os bytes escritos (0 = sem rótulo: entradas
/// não-finitas ou `t` absurdo). `t < 0` clampo em 0.
pub fn formatLabel(buf: []u8, t: f32, step: f32) usize {
    if (!std.math.isFinite(t) or !std.math.isFinite(step)) return 0;
    const tt = if (t < 0) 0 else t;
    if (tt >= 1.0e15) return 0; // guarda: evita estouro na conversão
    if (step >= 1.0) {
        const total: u64 = @intFromFloat(tt);
        const h = total / 3600;
        const m = (total % 3600) / 60;
        const s = total % 60;
        const written = if (h > 0)
            std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}", .{ h, m, s })
        else
            std.fmt.bufPrint(buf, "{d}:{d:0>2}", .{ m, s });
        const out = written catch return 0;
        return out.len;
    }
    var whole: u64 = @intFromFloat(tt);
    var tenth: u32 = @intFromFloat((tt - @as(f32, @floatFromInt(whole))) * 10.0 + 0.5);
    if (tenth >= 10) {
        tenth = 0;
        whole += 1;
    }
    const written = std.fmt.bufPrint(buf, "{d}.{d}", .{ whole, tenth }) catch return 0;
    return written.len;
}

/// Chave (instante + dado opaco do chamador).
pub const Keyframe = struct {
    /// Instante (s); deve ser finito.
    t: f32 = 0,
    /// Dado opaco (ex.: canal/curva). O widget não o interpreta.
    tag: u32 = 0,

    pub fn isValid(self: Keyframe) bool {
        return std.math.isFinite(self.t);
    }
};

/// Trilha: nome exibido na coluna esquerda + chaves.
pub const Track = struct {
    /// Nome exibido (emprestado só durante a chamada; vazio ⇒ sem texto).
    name: []const u8 = "",
    /// Chaves em segundos (ordem livre; o widget não reordena).
    keys: []Keyframe = &.{},
};

/// Referência a uma chave (`track`/`key` em `[]Track`).
pub const KeyRef = struct {
    track: u32 = 0,
    key: u32 = 0,

    pub fn eql(a: KeyRef, b: KeyRef) bool {
        return a.track == b.track and a.key == b.key;
    }

    /// True se a referência aponta para uma chave existente.
    pub fn isAlive(self: KeyRef, tracks: []const Track) bool {
        if (self.track >= tracks.len) return false;
        return self.key < tracks[self.track].keys.len;
    }
};

/// Índice da chave de `track` mais próxima de `t` dentro de `tol` (s) —
/// empate prefere a primeira. `null` se nenhuma (ou `tol` inválido).
pub fn nearestKey(track: Track, t: f32, tol: f32) ?usize {
    if (!std.math.isFinite(t) or !std.math.isFinite(tol) or tol < 0) return null;
    var best: ?usize = null;
    var best_d: f32 = std.math.inf(f32);
    for (track.keys, 0..) |k, i| {
        if (!k.isValid()) continue;
        const d = @abs(k.t - t);
        if (d <= tol and d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

/// Índice da trilha cuja linha contém `y` (px LOCAIS na área de trilhas,
/// 0 = topo da primeira trilha). `null` se fora de `[0, count * row_h)`.
pub fn trackAtY(y: f32, row_h: f32, count: usize) ?usize {
    if (!std.math.isFinite(y) or !std.math.isFinite(row_h) or row_h <= 0) return null;
    if (y < 0) return null;
    const idx = @floor(y / row_h);
    if (!std.math.isFinite(idx) or idx < 0) return null;
    if (idx >= @as(f32, @floatFromInt(count))) return null;
    return @intFromFloat(idx);
}

// --- tests ---

test "TimeTransform: tempo↔tela, zoom ancorado e clamp de janela" {
    const stdt = @import("std");
    const tr = TimeTransform{ .start = 2, .pps = 50 };
    try stdt.testing.expect(tr.isValid());
    try stdt.testing.expectEqual(@as(f32, 0), tr.timeToX(2));
    try stdt.testing.expectEqual(@as(f32, 100), tr.timeToX(4)); // (4-2)*50
    try stdt.testing.expectEqual(@as(f32, 4), tr.xToTime(100));
    try stdt.testing.expectEqual(@as(f32, 4), tr.visibleSpan(200)); // 200/50
    const vr = tr.visibleRange(200);
    try stdt.testing.expectEqual(@as(f32, 2), vr.t0);
    try stdt.testing.expectEqual(@as(f32, 6), vr.t1);

    // zoomAt mantém o instante sob a âncora.
    const t_anchor = tr.xToTime(30); // 2.6 s
    const z = tr.zoomAt(30, 2, 10, 400);
    try stdt.testing.expectEqual(@as(f32, 100), z.pps);
    try stdt.testing.expectApproxEqAbs(@as(f32, 30), z.timeToX(t_anchor), 1e-3);
    // Clamp de pps (bordas em qualquer ordem) e guardas.
    try stdt.testing.expectEqual(@as(f32, 400), tr.zoomAt(0, 1000, 10, 400).pps);
    try stdt.testing.expectEqual(@as(f32, 10), tr.zoomAt(0, 0.0001, 400, 10).pps);
    try stdt.testing.expectEqual(@as(f32, 50), tr.zoomAt(0, std.math.nan(f32), 10, 400).pps);
    try stdt.testing.expect(!(TimeTransform{ .pps = 0 }).isValid());

    // Janela: span 2 s numa área de 200 px com pps 100 ⇒ start ∈ [0, 8].
    const w = TimeTransform{ .start = 99, .pps = 100 };
    try stdt.testing.expectEqual(@as(f32, 8), w.clampStart(200, 10).start);
    const neg = TimeTransform{ .start = -5, .pps = 100 };
    try stdt.testing.expectEqual(@as(f32, 0), neg.clampStart(200, 10).start);
    // Janela maior que a duração ⇒ start 0.
    const big = TimeTransform{ .start = 3, .pps = 10 };
    try stdt.testing.expectEqual(@as(f32, 0), big.clampStart(200, 10).start);
}

test "tickStep: passos canônicos e guardas" {
    const stdt = @import("std");
    // pps 20, alvo 60 px ⇒ precisa de s * 20 >= 60 ⇒ 5 s.
    try stdt.testing.expectEqual(@as(f32, 5), tickStep(20, 60));
    // pps 100, alvo 100 ⇒ 1 s.
    try stdt.testing.expectEqual(@as(f32, 1), tickStep(100, 100));
    // pps 1, alvo 100 ⇒ 120 s (100 não é canônico).
    try stdt.testing.expectEqual(@as(f32, 120), tickStep(1, 100));
    // pps alto ⇒ 10 ms.
    try stdt.testing.expectEqual(@as(f32, 0.01), tickStep(10000, 50));
    // Nada cabe ⇒ maior passo (1 h).
    try stdt.testing.expectEqual(@as(f32, 3600), tickStep(0.5, 100000));
    // Guardas.
    try stdt.testing.expectEqual(@as(f32, 0), tickStep(0, 60));
    try stdt.testing.expectEqual(@as(f32, 0), tickStep(20, 0));
    try stdt.testing.expectEqual(@as(f32, 0), tickStep(std.math.nan(f32), 60));
}

test "formatLabel: m:ss, h:mm:ss, décimos e guardas" {
    const stdt = @import("std");
    var buf: [32]u8 = undefined;
    try stdt.testing.expectEqualStrings("0:00", buf[0..formatLabel(&buf, 0, 1)]);
    try stdt.testing.expectEqualStrings("1:05", buf[0..formatLabel(&buf, 65, 1)]);
    try stdt.testing.expectEqualStrings("1:02:05", buf[0..formatLabel(&buf, 3725, 5)]);
    try stdt.testing.expectEqualStrings("12.3", buf[0..formatLabel(&buf, 12.34, 0.5)]);
    // Arredonda os décimos e propaga o transporte.
    try stdt.testing.expectEqualStrings("1.0", buf[0..formatLabel(&buf, 0.96, 0.1)]);
    try stdt.testing.expectEqualStrings("0.0", buf[0..formatLabel(&buf, -3, 0.1)]);
    // Guardas.
    try stdt.testing.expectEqual(@as(usize, 0), formatLabel(&buf, std.math.inf(f32), 1));
    try stdt.testing.expectEqual(@as(usize, 0), formatLabel(&buf, 1e20, 1));
}

test "snapTime e clampTime" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(f32, 3), snapTime(3.2, 1));
    try stdt.testing.expectEqual(@as(f32, 2.5), snapTime(2.6, 0.5));
    try stdt.testing.expectEqual(@as(f32, 3.2), snapTime(3.2, 0));
    try stdt.testing.expectEqual(@as(f32, 3.2), snapTime(3.2, std.math.nan(f32)));
    try stdt.testing.expectEqual(@as(f32, 0), clampTime(-1, 10));
    try stdt.testing.expectEqual(@as(f32, 10), clampTime(99, 10));
    try stdt.testing.expectEqual(@as(f32, 4), clampTime(4, 10));
    try stdt.testing.expectEqual(@as(f32, 0), clampTime(4, std.math.nan(f32)));
}

test "nearestKey: tolerância, empate e inválidas" {
    const stdt = @import("std");
    var keys = [_]Keyframe{
        .{ .t = 1 },
        .{ .t = 2.5, .tag = 7 },
        .{ .t = std.math.nan(f32) }, // inválida: ignorada
        .{ .t = 5 },
    };
    const track = Track{ .keys = &keys };
    try stdt.testing.expectEqual(@as(?usize, 1), nearestKey(track, 2.4, 0.2));
    try stdt.testing.expectEqual(@as(?usize, null), nearestKey(track, 3.5, 0.2));
    try stdt.testing.expectEqual(@as(?usize, 1), nearestKey(track, 2.5, 0));
    // Empate (1 e 2.5 equidistantes de 1.75) ⇒ primeira.
    try stdt.testing.expectEqual(@as(?usize, 0), nearestKey(track, 1.75, 1));
    // A chave inválida nunca é escolhida.
    try stdt.testing.expectEqual(@as(?usize, 3), nearestKey(track, 5, 0.5));
    try stdt.testing.expectEqual(@as(?usize, null), nearestKey(track, 2.5, std.math.nan(f32)));
    try stdt.testing.expectEqual(@as(?usize, null), nearestKey(track, 2.5, -1));
}

test "trackAtY e KeyRef" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(?usize, 0), trackAtY(0, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, 0), trackAtY(19.9, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, 2), trackAtY(45, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, null), trackAtY(60, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, null), trackAtY(-0.5, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, null), trackAtY(10, 0, 3));
    try stdt.testing.expectEqual(@as(?usize, null), trackAtY(10, 20, 0));
    try stdt.testing.expectEqual(@as(?usize, null), trackAtY(std.math.nan(f32), 20, 3));

    var keys = [_]Keyframe{ .{ .t = 0 }, .{ .t = 1 } };
    const tracks = [_]Track{ .{}, .{ .keys = &keys } };
    const k11 = KeyRef{ .track = 1, .key = 1 };
    const k12 = KeyRef{ .track = 1, .key = 2 };
    const k90 = KeyRef{ .track = 9, .key = 0 };
    const k00 = KeyRef{ .track = 0, .key = 0 };
    try stdt.testing.expect(k11.isAlive(&tracks));
    try stdt.testing.expect(!k12.isAlive(&tracks));
    try stdt.testing.expect(!k90.isAlive(&tracks));
    try stdt.testing.expect(!k00.isAlive(&tracks)); // trilha 0 não tem chaves
    try stdt.testing.expect(k11.eql(.{ .track = 1, .key = 1 }));
    try stdt.testing.expect(!k11.eql(.{ .track = 1, .key = 2 }));
}
