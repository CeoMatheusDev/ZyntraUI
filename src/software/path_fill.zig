//! ZyntraUI — rasterização de caminhos vetoriais (software/path_fill).
//!
//! Escopo M159: preenche e traça caminhos vetoriais (ver `draw/path`)
//! com anti-serrilhamento. O módulo é PURO: não conhece o framebuffer —
//! quem pinta é o chamador, via o callback `plot(x, y, cobertura)`.
//! - `fill`: preenche o caminho (regra `nonzero` ou `evenodd`).
//! - `stroke`: traça o caminho (largura, junta e ponta).
//!
//! Anti-serrilhamento: 4 sub-scanlines por linha de pixel (amostra no
//! meio de cada faixa) com cobertura EXATA em X (a fração do pixel
//! coberta pelo vão). O resultado é determinístico.
//!
//! Buffers: o chamador fornece a cobertura por pixel (`cov`) e a lista
//! de cruzamentos (`crossings`) — reaproveitados entre linhas, sem
//! alocação durante o desenho.
//!
//! Limite: um caminho com mais de `max_crossings` cruzamentos numa
//! mesma scanline é desenhado com os cruzamentos que couberem (o
//! desenho fica incompleto em vez de estourar a memória).

const std = @import("std");
const types = @import("../core/types.zig");
const path_mod = @import("../draw/path.zig");

/// Regra de preenchimento (veja `draw.path.FillRule`).
pub const Rule = path_mod.FillRule;

/// Junta do traço (veja `draw.path.StrokeJoin`).
pub const Join = path_mod.StrokeJoin;

/// Ponta do traço (veja `draw.path.StrokeCap`).
pub const Cap = path_mod.StrokeCap;

/// Amostras verticais por linha de pixel.
pub const samples: u32 = 4;

/// Máximo de cruzamentos aceitos numa scanline.
pub const max_crossings: usize = 4096;

/// Cruzamento de uma scanline com uma aresta.
pub const Crossing = struct {
    /// Posição do cruzamento no eixo X.
    x: f32 = 0,
    /// +1 quando a aresta desce, -1 quando sobe.
    dir: i32 = 0,
};

/// Buffers do chamador (reaproveitados entre linhas).
pub const Scratch = struct {
    /// Cobertura por pixel (f32): 1 entrada por pixel da LARGURA do
    /// bbox do caminho (a linha é zerada a cada faixa).
    cov: []f32 = &.{},
    /// Cobertura auxiliar (f32): a mesma largura de `cov`, usada pelo
    /// traço para juntar as peças (união) de uma sub-scanline antes de
    /// somar na linha.
    aux: []f32 = &.{},
    /// Cruzamentos de uma scanline.
    crossings: []Crossing = &.{},
};

/// Como a cobertura de uma peça combina com o que já está no buffer.
const Mode = enum { add, max };

fn vAdd(a: types.Vec2, b: types.Vec2) types.Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

fn vSub(a: types.Vec2, b: types.Vec2) types.Vec2 {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}

fn vScale(a: types.Vec2, s: f32) types.Vec2 {
    return .{ .x = a.x * s, .y = a.y * s };
}

fn vDot(a: types.Vec2, b: types.Vec2) f32 {
    return a.x * b.x + a.y * b.y;
}

fn vLen(a: types.Vec2) f32 {
    return @sqrt(vDot(a, a));
}

fn vNorm(a: types.Vec2) types.Vec2 {
    const l = vLen(a);
    if (l <= 0) return .{ .x = 0, .y = 0 };
    return vScale(a, 1.0 / l);
}

/// Normal à esquerda do segmento (a→b) (não normalizada se degenerado).
fn segNormal(a: types.Vec2, b: types.Vec2) types.Vec2 {
    const d = vNorm(vSub(b, a));
    return .{ .x = -d.y, .y = d.x };
}

/// Ordena os cruzamentos por X (insertion sort: listas pequenas).
fn sortCrossings(crossings: []Crossing) void {
    var i: usize = 1;
    while (i < crossings.len) : (i += 1) {
        const c = crossings[i];
        var j = i;
        while (j > 0 and crossings[j - 1].x > c.x) : (j -= 1) {
            crossings[j] = crossings[j - 1];
        }
        crossings[j] = c;
    }
}

/// Coleta os cruzamentos das arestas de um polígono com a scanline `y`.
fn polygonCrossings(pts: []const types.Vec2, y: f32, crossings: []Crossing) usize {
    var n: usize = 0;
    if (pts.len < 2) return 0;
    var i: usize = 0;
    while (i < pts.len) : (i += 1) {
        const p0 = pts[i];
        const p1 = pts[(i + 1) % pts.len];
        if (p0.y == p1.y) continue; // aresta horizontal: nunca cruza
        const ymin = @min(p0.y, p1.y);
        const ymax = @max(p0.y, p1.y);
        if (y < ymin or y >= ymax) continue;
        if (n >= crossings.len or n >= max_crossings) break;
        const t = (y - p0.y) / (p1.y - p0.y);
        crossings[n] = .{
            .x = p0.x + t * (p1.x - p0.x),
            .dir = if (p1.y > p0.y) 1 else -1,
        };
        n += 1;
    }
    return n;
}

/// Coleta os cruzamentos de TODOS os contornos do caminho (o
/// preenchimento trata cada contorno como fechado).
fn pathCrossings(flat: path_mod.Flat, y: f32, crossings: []Crossing) usize {
    var n: usize = 0;
    for (flat.contours) |c| {
        const pts = flat.points[c.start..][0..c.len];
        const count = polygonCrossings(pts, y, crossings[n..]);
        n += count;
        if (n >= crossings.len) break;
    }
    return n;
}

/// Percorre os cruzamentos ordenados e devolve os vãos "dentro".
/// `spans` recebe pares (x0, x1) — no máximo `spans.len / 2` vãos.
fn insideSpans(crossings: []Crossing, rule: Rule, spans: []f32) usize {
    if (crossings.len == 0) return 0;
    sortCrossings(crossings);
    var count: usize = 0;
    var winding: i32 = 0;
    var inside = false;
    var span_start: f32 = 0;
    var i: usize = 0;
    while (i < crossings.len) {
        // Agrupa os cruzamentos na mesma posição X (vértice compartilhado).
        const x = crossings[i].x;
        var dir_sum: i32 = 0;
        var group: usize = 0;
        while (i < crossings.len and @abs(crossings[i].x - x) <= 1e-6) : (i += 1) {
            dir_sum += crossings[i].dir;
            group += 1;
        }
        const was_inside = inside;
        switch (rule) {
            .nonzero => {
                winding += dir_sum;
                inside = winding != 0;
            },
            .evenodd => {
                inside = if (group % 2 == 1) !was_inside else was_inside;
            },
        }
        if (was_inside and !inside) {
            if (count * 2 + 2 > spans.len) break;
            spans[count * 2] = span_start;
            spans[count * 2 + 1] = x;
            count += 1;
        } else if (!was_inside and inside) {
            span_start = x;
        }
    }
    return count;
}

/// Acumula a cobertura de um vão `[x0, x1)` na linha da sub-scanline.
fn addSpan(cov: []f32, cov_x0: f32, x0: f32, x1: f32, mode: Mode) void {
    if (x1 <= x0) return;
    const first = @floor(x0);
    const last = @floor(x1);
    var px = @as(i64, @intFromFloat(first));
    const end = @as(i64, @intFromFloat(last));
    while (px <= end) : (px += 1) {
        const left = @max(x0, @as(f32, @floatFromInt(px)));
        const right = @min(x1, @as(f32, @floatFromInt(px + 1)));
        if (right <= left) continue;
        const idx = px - @as(i64, @intFromFloat(cov_x0));
        if (idx < 0 or idx >= cov.len) continue;
        const c = right - left;
        const slot = &cov[@intCast(idx)];
        switch (mode) {
            .add => slot.* += c,
            .max => slot.* = @max(slot.*, c),
        }
    }
}

/// Acumula a cobertura de um polígono fechado na sub-scanline `y`.
fn accumulatePolygon(
    cov: []f32,
    cov_x0: f32,
    y: f32,
    pts: []const types.Vec2,
    crossings: []Crossing,
    spans: []f32,
    mode: Mode,
) void {
    if (pts.len < 3) return;
    const n = polygonCrossings(pts, y, crossings);
    if (n == 0) return;
    const count = insideSpans(crossings[0..n], .nonzero, spans);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        addSpan(cov, cov_x0, spans[i * 2], spans[i * 2 + 1], mode);
    }
}

/// Acumula a cobertura do caminho inteiro na sub-scanline `y`.
fn accumulatePath(
    cov: []f32,
    cov_x0: f32,
    y: f32,
    flat: path_mod.Flat,
    crossings: []Crossing,
    spans: []f32,
    rule: Rule,
    mode: Mode,
) void {
    const n = pathCrossings(flat, y, crossings);
    if (n == 0) return;
    const count = insideSpans(crossings[0..n], rule, spans);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        addSpan(cov, cov_x0, spans[i * 2], spans[i * 2 + 1], mode);
    }
}

/// Polígono de um segmento traçado (quadrado com a espessura).
fn segmentQuad(a: types.Vec2, b: types.Vec2, hw: f32, out: *[4]types.Vec2) void {
    const n = segNormal(a, b);
    const off = vScale(n, hw);
    out[0] = vAdd(a, off);
    out[1] = vAdd(b, off);
    out[2] = vSub(b, off);
    out[3] = vSub(a, off);
}

/// Polígono de um disco (aproximado por `sides` lados).
fn discPoly(center: types.Vec2, radius: f32, out: []types.Vec2, sides: usize) usize {
    if (sides > out.len) return 0;
    var i: usize = 0;
    while (i < sides) : (i += 1) {
        const ang = @as(f32, @floatFromInt(i)) * (2.0 * std.math.pi / @as(f32, @floatFromInt(sides)));
        out[i] = .{
            .x = center.x + @cos(ang) * radius,
            .y = center.y + @sin(ang) * radius,
        };
    }
    return sides;
}

/// Junta (bev|round|miter) no vértice `v` entre os segmentos (a→v) e
/// (v→b). Devolve a quantidade de pontos escritos em `out`.
fn joinPoly(
    v: types.Vec2,
    a: types.Vec2,
    b: types.Vec2,
    hw: f32,
    join: Join,
    out: []types.Vec2,
) usize {
    const n1 = segNormal(a, v);
    const n2 = segNormal(v, b);
    switch (join) {
        .round => return discPoly(v, hw, out, 12),
        .bevel => {
            out[0] = v;
            out[1] = vAdd(v, vScale(n1, hw));
            out[2] = vAdd(v, vScale(n2, hw));
            return 3;
        },
        .miter => {
            const bis = vAdd(n1, n2);
            const len = vLen(bis);
            if (len < 1e-6) {
                out[0] = v;
                out[1] = vAdd(v, vScale(n1, hw));
                out[2] = vAdd(v, vScale(n2, hw));
                return 3;
            }
            const dir = vScale(bis, 1.0 / len);
            const cos_half = @abs(vDot(dir, n1));
            // Limite de bisel 4:0 (igual ao das engines 2D comuns).
            if (cos_half < 0.25) {
                out[0] = v;
                out[1] = vAdd(v, vScale(n1, hw));
                out[2] = vAdd(v, vScale(n2, hw));
                return 3;
            }
            const miter_len = hw / cos_half;
            out[0] = v;
            out[1] = vAdd(v, vScale(n1, hw));
            out[2] = vAdd(v, vScale(dir, miter_len));
            out[3] = vAdd(v, vScale(n2, hw));
            return 4;
        },
    }
}

/// Ponta do traço no ponto `p` com a direção `d` (normalizada).
fn capPoly(
    p: types.Vec2,
    d: types.Vec2,
    hw: f32,
    cap: Cap,
    out: []types.Vec2,
) usize {
    switch (cap) {
        .butt => return 0,
        .round => return discPoly(p, hw, out, 12),
        .square => {
            const n = segNormal(p, vAdd(p, d));
            const off = vScale(n, hw);
            const tip = vAdd(p, vScale(d, hw));
            out[0] = vAdd(p, off);
            out[1] = vAdd(tip, off);
            out[2] = vSub(tip, off);
            out[3] = vSub(p, off);
            return 4;
        },
    }
}

/// Preenche o caminho e chama `plot.plot(x, y, cobertura)` por pixel.
///
/// `plot` precisa ter o método `plot(self: *P, x: i32, y: i32, cov: f32) void`.
/// A cobertura vai de 0 (fora) a 1 (coberto).
pub fn fill(
    comptime P: type,
    flat: path_mod.Flat,
    rule: Rule,
    area: types.Rect,
    scratch: *Scratch,
    plot: *P,
) void {
    if (flat.points.len == 0 or flat.contours.len == 0) return;
    const bb = flat.bounds();
    // Um bbox sem área (linha horizontal) ainda é um caminho: só o
    // "nada" (sem pontos) é descartado.
    if (!(bb.w > 0) and !(bb.h > 0)) return;
    // Só a parte do caminho dentro da área desenhável é rasterizada.
    const x0f = @max(@floor(bb.x), @floor(area.x));
    const x1f = @min(@ceil(bb.x + bb.w), @ceil(area.x + area.w));
    if (x1f <= x0f) return;
    const row_w = @as(usize, @intFromFloat(x1f - x0f));
    if (scratch.cov.len < row_w) return;
    const cov = scratch.cov[0..row_w];
    // Vãos: no máximo um por cruzamento/2 (buffer local fixo).
    var spans: [256]f32 = undefined;
    const y0 = @max(@floor(bb.y), @floor(area.y));
    const y1 = @min(@ceil(bb.y + bb.h), @ceil(area.y + area.h));
    if (y1 <= y0) return;
    var y = y0;
    while (y < y1) : (y += 1) {
        @memset(cov, 0);
        var s: u32 = 0;
        while (s < samples) : (s += 1) {
            const sy = y + (@as(f32, @floatFromInt(s)) + 0.5) / @as(f32, @floatFromInt(samples));
            accumulatePath(cov, x0f, sy, flat, scratch.crossings, &spans, rule, .add);
        }
        var i: usize = 0;
        while (i < row_w) : (i += 1) {
            const c = cov[i] / @as(f32, @floatFromInt(samples));
            if (c <= 0) continue;
            plot.plot(@as(i32, @intFromFloat(x0f)) + @as(i32, @intCast(i)), @as(i32, @intFromFloat(y)), c);
        }
    }
}

/// Traça o caminho e chama `plot.plot(x, y, cobertura)` por pixel.
pub fn stroke(
    comptime P: type,
    flat: path_mod.Flat,
    width: f32,
    join: Join,
    cap: Cap,
    area: types.Rect,
    scratch: *Scratch,
    plot: *P,
) void {
    if (flat.points.len == 0 or flat.contours.len == 0) return;
    if (!std.math.isFinite(width) or width <= 0) return;
    const hw = width / 2.0;
    const bb = flat.bounds();
    if (!(bb.w > 0) and !(bb.h > 0)) return;
    const x0f = @max(@floor(bb.x - hw - 1), @floor(area.x));
    const x1f = @min(@ceil(bb.x + bb.w + hw + 1), @ceil(area.x + area.w));
    if (x1f <= x0f) return;
    const row_w = @as(usize, @intFromFloat(x1f - x0f));
    if (scratch.cov.len < row_w) return;
    const cov = scratch.cov[0..row_w];
    if (scratch.aux.len < row_w) return;
    const aux = scratch.aux[0..row_w];
    var spans: [256]f32 = undefined;
    var quad: [4]types.Vec2 = undefined;
    var piece: [16]types.Vec2 = undefined;
    const y0 = @max(@floor(bb.y - hw - 1), @floor(area.y));
    const y1 = @min(@ceil(bb.y + bb.h + hw + 1), @ceil(area.y + area.h));
    if (y1 <= y0) return;
    var y = y0;
    while (y < y1) : (y += 1) {
        @memset(cov, 0);
        var s: u32 = 0;
        while (s < samples) : (s += 1) {
            const sy = y + (@as(f32, @floatFromInt(s)) + 0.5) / @as(f32, @floatFromInt(samples));
            // As peças da sub-scanline são unida (max) em `aux`; `aux` é
            // somado na linha (`cov`) — a soma entre sub-scanlines é o
            // que dá o anti-serrilhamento vertical.
            @memset(aux, 0);
            for (flat.contours) |c| {
                const pts = flat.points[c.start..][0..c.len];
                if (pts.len < 2) continue;
                const seg_count = if (c.closed) pts.len else pts.len - 1;
                var i: usize = 0;
                while (i < seg_count) : (i += 1) {
                    const a = pts[i];
                    const b = pts[(i + 1) % pts.len];
                    segmentQuad(a, b, hw, &quad);
                    accumulatePolygon(aux, x0f, sy, &quad, scratch.crossings, &spans, .max);
                }
                if (c.closed) {
                    // Juntas em todos os vértices.
                    i = 0;
                    while (i < pts.len) : (i += 1) {
                        const prev = pts[(i + pts.len - 1) % pts.len];
                        const cur = pts[i];
                        const next = pts[(i + 1) % pts.len];
                        const n = joinPoly(cur, prev, next, hw, join, &piece);
                        if (n >= 3) accumulatePolygon(aux, x0f, sy, piece[0..n], scratch.crossings, &spans, .max);
                    }
                } else {
                    // Juntas internas + pontas.
                    i = 1;
                    while (i + 1 < pts.len) : (i += 1) {
                        const n = joinPoly(pts[i], pts[i - 1], pts[i + 1], hw, join, &piece);
                        if (n >= 3) accumulatePolygon(aux, x0f, sy, piece[0..n], scratch.crossings, &spans, .max);
                    }
                    const first = pts[0];
                    const last = pts[pts.len - 1];
                    const d0 = vNorm(vSub(pts[1], first));
                    const d1 = vNorm(vSub(last, pts[pts.len - 2]));
                    const n0 = capPoly(first, vScale(d0, -1.0), hw, cap, &piece);
                    if (n0 >= 3) accumulatePolygon(aux, x0f, sy, piece[0..n0], scratch.crossings, &spans, .max);
                    const n1c = capPoly(last, d1, hw, cap, &piece);
                    if (n1c >= 3) accumulatePolygon(aux, x0f, sy, piece[0..n1c], scratch.crossings, &spans, .max);
                }
            }
            // A união das peças (`aux`) entra na linha (`cov`): a soma
            // entre sub-scanlines é o anti-serrilhamento vertical.
            var k: usize = 0;
            while (k < row_w) : (k += 1) {
                cov[k] += aux[k];
            }
        }
        var i: usize = 0;
        while (i < row_w) : (i += 1) {
            const c = cov[i] / @as(f32, @floatFromInt(samples));
            if (c <= 0) continue;
            plot.plot(@as(i32, @intFromFloat(x0f)) + @as(i32, @intCast(i)), @as(i32, @intFromFloat(y)), c);
        }
    }
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

/// Plota em um buffer de cobertura (sem framebuffer).
const TestPlot = struct {
    pixels: []u8, // 1 byte por pixel (cobertura)
    w: usize,
    h: usize,
    offset_x: i32 = 0,
    offset_y: i32 = 0,

    fn plot(self: *@This(), x: i32, y: i32, cov: f32) void {
        if (x < 0 or y < 0) return;
        const ux = @as(usize, @intCast(x - self.offset_x));
        const uy = @as(usize, @intCast(y - self.offset_y));
        if (ux >= self.w or uy >= self.h) return;
        const v: u8 = @intFromFloat(@round(cov * 255));
        const i = uy * self.w + ux;
        self.pixels[i] = @max(self.pixels[i], v);
    }
};

fn flatOf(segs: []const path_mod.Segment, points: []types.Vec2, contours: []path_mod.ContourRange) path_mod.Flat {
    return path_mod.flatten(segs, 0.25, points, contours) catch unreachable;
}

test "path_fill: preenche um retângulo" {
    var segs: [8]path_mod.Segment = undefined;
    var b = path_mod.Builder.init(&segs);
    try b.rect(.{ .x = 2, .y = 2, .w = 4, .h = 4 });
    var points: [32]types.Vec2 = undefined;
    var contours: [4]path_mod.ContourRange = undefined;
    const flat = flatOf(b.segments(), &points, &contours);

    var pixels: [64]u8 = undefined;
    @memset(&pixels, 0);
    var plot = TestPlot{ .pixels = &pixels, .w = 8, .h = 8 };
    var cov_buf: [64]f32 = undefined;
    @memset(&cov_buf, 0);
    var aux_buf: [64]f32 = undefined;
    @memset(&aux_buf, 0);
    var cross_buf: [64]Crossing = undefined;
    @memset(&cross_buf, Crossing{});
    var scratch = Scratch{ .cov = &cov_buf, .aux = &aux_buf, .crossings = &cross_buf };
    fill(TestPlot, flat, .nonzero, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot);

    // O interior está coberto, o exterior não.
    try std.testing.expect(pixels[3 * 8 + 3] > 200);
    try std.testing.expect(pixels[0] == 0);
    try std.testing.expect(pixels[7 * 8 + 7] == 0);
}

test "path_fill: buraco com evenodd e nonzero" {
    // Dois retângulos concêntricos: o de dentro com o sentido oposto.
    var segs: [16]path_mod.Segment = undefined;
    var b = path_mod.Builder.init(&segs);
    try b.rect(.{ .x = 0, .y = 0, .w = 10, .h = 10 });
    // Contorno interno no MESMO sentido do externo (o winding se soma).
    try b.moveTo(.{ .x = 3, .y = 3 });
    try b.lineTo(.{ .x = 7, .y = 3 });
    try b.lineTo(.{ .x = 7, .y = 7 });
    try b.lineTo(.{ .x = 3, .y = 7 });
    try b.close();
    var points: [64]types.Vec2 = undefined;
    var contours: [4]path_mod.ContourRange = undefined;
    const flat = flatOf(b.segments(), &points, &contours);

    var px_nz: [100]u8 = undefined;
    @memset(&px_nz, 0);
    var plot_nz = TestPlot{ .pixels = &px_nz, .w = 10, .h = 10 };
    var cov_buf: [64]f32 = undefined;
    @memset(&cov_buf, 0);
    var aux_buf: [64]f32 = undefined;
    @memset(&aux_buf, 0);
    var cross_buf: [64]Crossing = undefined;
    @memset(&cross_buf, Crossing{});
    var scratch = Scratch{ .cov = &cov_buf, .aux = &aux_buf, .crossings = &cross_buf };
    fill(TestPlot, flat, .nonzero, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot_nz);
    // Nonzero: o interior é preenchido (o winding não zera).
    try std.testing.expect(px_nz[5 * 10 + 5] > 200);

    var px_eo: [100]u8 = undefined;
    @memset(&px_eo, 0);
    var plot_eo = TestPlot{ .pixels = &px_eo, .w = 10, .h = 10 };
    fill(TestPlot, flat, .evenodd, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot_eo);
    // Evenodd: o buraco fica vazio.
    try std.testing.expect(px_eo[5 * 10 + 5] == 0);
    // ... e a parte de fora continua cheia.
    try std.testing.expect(px_eo[1 * 10 + 1] > 200);
}

test "path_fill: o traço de uma linha é estreito e longo" {
    var segs: [8]path_mod.Segment = undefined;
    var b = path_mod.Builder.init(&segs);
    try b.moveTo(.{ .x = 2, .y = 5 });
    try b.lineTo(.{ .x = 20, .y = 5 });
    var points: [32]types.Vec2 = undefined;
    var contours: [4]path_mod.ContourRange = undefined;
    const flat = flatOf(b.segments(), &points, &contours);

    var pixels: [32 * 12]u8 = undefined;
    @memset(&pixels, 0);
    var plot = TestPlot{ .pixels = &pixels, .w = 32, .h = 12 };
    var cov_buf: [64]f32 = undefined;
    @memset(&cov_buf, 0);
    var aux_buf: [64]f32 = undefined;
    @memset(&aux_buf, 0);
    var cross_buf: [64]Crossing = undefined;
    @memset(&cross_buf, Crossing{});
    var scratch = Scratch{ .cov = &cov_buf, .aux = &aux_buf, .crossings = &cross_buf };
    stroke(TestPlot, flat, 2.0, .round, .butt, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot);

    // A linha y=5 (cobertura 2px: y=4 e y=5) está pintada.
    try std.testing.expect(pixels[5 * 32 + 10] > 200);
    // Acima e abaixo, não.
    try std.testing.expect(pixels[2 * 32 + 10] == 0);
    try std.testing.expect(pixels[9 * 32 + 10] == 0);
}

test "path_fill: a ponta do traço depende do cap" {
    var segs: [8]path_mod.Segment = undefined;
    var b = path_mod.Builder.init(&segs);
    try b.moveTo(.{ .x = 2, .y = 5 });
    try b.lineTo(.{ .x = 20, .y = 5 });
    var points: [32]types.Vec2 = undefined;
    var contours: [4]path_mod.ContourRange = undefined;
    const flat = flatOf(b.segments(), &points, &contours);

    var butt: [32 * 12]u8 = undefined;
    @memset(&butt, 0);
    var plot_butt = TestPlot{ .pixels = &butt, .w = 32, .h = 12 };
    var cov_buf: [64]f32 = undefined;
    @memset(&cov_buf, 0);
    var aux_buf: [64]f32 = undefined;
    @memset(&aux_buf, 0);
    var cross_buf: [64]Crossing = undefined;
    @memset(&cross_buf, Crossing{});
    var scratch = Scratch{ .cov = &cov_buf, .aux = &aux_buf, .crossings = &cross_buf };
    stroke(TestPlot, flat, 4.0, .round, .butt, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot_butt);
    // Com butt, o traço começa exatamente em x=2.
    try std.testing.expect(butt[5 * 32 + 1] == 0);

    var square: [32 * 12]u8 = undefined;
    @memset(&square, 0);
    var plot_square = TestPlot{ .pixels = &square, .w = 32, .h = 12 };
    stroke(TestPlot, flat, 4.0, .round, .square, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot_square);
    // Com square, o traço avança 2px (metade da espessura).
    try std.testing.expect(square[5 * 32 + 1] > 0);
}

test "path_fill: círculo preenchido tem o raio certo" {
    var segs: [64]path_mod.Segment = undefined;
    var b = path_mod.Builder.init(&segs);
    try b.circle(.{ .x = 20, .y = 20 }, 10);
    var points: [256]types.Vec2 = undefined;
    var contours: [4]path_mod.ContourRange = undefined;
    const flat = flatOf(b.segments(), &points, &contours);

    var pixels: [40 * 40]u8 = undefined;
    @memset(&pixels, 0);
    var plot = TestPlot{ .pixels = &pixels, .w = 40, .h = 40 };
    var cov_buf: [64]f32 = undefined;
    @memset(&cov_buf, 0);
    var aux_buf: [64]f32 = undefined;
    @memset(&aux_buf, 0);
    var cross_buf: [64]Crossing = undefined;
    @memset(&cross_buf, Crossing{});
    var scratch = Scratch{ .cov = &cov_buf, .aux = &aux_buf, .crossings = &cross_buf };
    fill(TestPlot, flat, .nonzero, .{ .x = 0, .y = 0, .w = 64, .h = 64 }, &scratch, &plot);

    try std.testing.expect(pixels[20 * 40 + 20] > 200);
    try std.testing.expect(pixels[20 * 40 + 12] > 0);
    try std.testing.expect(pixels[20 * 40 + 9] == 0);
    try std.testing.expect(pixels[5 * 40 + 5] == 0);
}

test "path_fill: caminho vazio não desenha nada" {
    const empty = path_mod.Flat{};
    var pixels: [16]u8 = undefined;
    @memset(&pixels, 0);
    var plot = TestPlot{ .pixels = &pixels, .w = 4, .h = 4 };
    var cov_buf: [16]f32 = undefined;
    @memset(&cov_buf, 0);
    var aux_buf: [16]f32 = undefined;
    @memset(&aux_buf, 0);
    var cross_buf: [16]Crossing = undefined;
    @memset(&cross_buf, Crossing{});
    var scratch = Scratch{ .cov = &cov_buf, .aux = &aux_buf, .crossings = &cross_buf };
    fill(TestPlot, empty, .nonzero, .{ .x = 0, .y = 0, .w = 16, .h = 16 }, &scratch, &plot);
    stroke(TestPlot, empty, 2, .round, .butt, .{ .x = 0, .y = 0, .w = 16, .h = 16 }, &scratch, &plot);
    for (pixels) |p| try std.testing.expectEqual(@as(u8, 0), p);
}
