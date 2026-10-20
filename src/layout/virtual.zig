//! ZyntraUI — helpers de virtualização (layout/virtual).
//!
//! Escopo M154: cálculo PURO do intervalo de itens visíveis de um
//! conteúdo rolável. O estado continua sendo do aplicativo: estes
//! helpers não guardam nada, apenas dizem quais itens construir.
//!
//! - Culling: o backend evita RASTERIZAR o que está fora da área.
//! - Virtualização: o app evita CONSTRUIR e MEDIR o que está fora.
//!
//! Dois casos:
//! - Altura FIXA: cálculo direto (divisão), O(1).
//! - Altura VARIÁVEL: offsets acumulados (prefix sums) + busca
//!   binária, O(log n).

const std = @import("std");

/// Intervalo de itens visíveis: `[start, end)` (end exclusivo).
pub const Range = struct {
    start: usize = 0,
    end: usize = 0,

    pub fn isEmpty(self: Range) bool {
        return self.end <= self.start;
    }

    pub fn len(self: Range) usize {
        return if (self.end > self.start) self.end - self.start else 0;
    }

    pub fn contains(self: Range, index: usize) bool {
        return index >= self.start and index < self.end;
    }
};

/// Intervalo visível para itens de ALTURA FIXA.
///
/// `scroll` é o deslocamento do conteúdo (px, pode ser negativo) e
/// `viewport_h` a altura visível (px). `overscan` é a margem extra de
/// itens construídos antes e depois (0 = só o visível).
pub fn fixedRange(
    count: usize,
    item_height: f32,
    scroll: f32,
    viewport_h: f32,
    overscan: usize,
) Range {
    if (count == 0) return .{};
    if (!std.math.isFinite(item_height) or item_height <= 0) {
        // Altura degenerada: nada é mensurável (devolve o primeiro item
        // para o app não "travar" sem conteúdo).
        return .{ .start = 0, .end = @min(count, 1 + overscan) };
    }
    if (!std.math.isFinite(scroll) or !std.math.isFinite(viewport_h)) {
        return .{ .start = 0, .end = count };
    }
    const view_top = @max(0.0, scroll);
    const view_h = @max(0.0, viewport_h);

    // Primeiro item visível: o cujo topo está dentro (ou no fim) da
    // janela. Último (exclusivo): o primeiro item cujo topo passa do
    // fim da janela.
    const first_visible_f = @floor(view_top / item_height);
    const last_visible_f = @ceil((view_top + view_h) / item_height);
    const first: usize = @intFromFloat(@min(first_visible_f, @as(f64, @floatFromInt(count))));
    const last: usize = @intFromFloat(@min(last_visible_f, @as(f64, @floatFromInt(count))));

    const start = if (first >= overscan) first - overscan else 0;
    const end = @min(count, @max(start, last + overscan));
    if (end <= start) return .{ .start = start, .end = start };
    return .{ .start = start, .end = end };
}

/// Intervalo visível para itens de ALTURA VARIÁVEL.
///
/// `offsets` são os deslocamentos acumulados: `offsets[i]` é o topo do
/// item `i` e `offsets[count]` é a altura total (o slice tem
/// `count + 1` entradas). Busca binária pelo primeiro item cujo fim
/// passa do topo da janela.
pub fn variableRange(
    offsets: []const f32,
    scroll: f32,
    viewport_h: f32,
    overscan: usize,
) Range {
    if (offsets.len < 2) return .{};
    const count = offsets.len - 1;
    if (!std.math.isFinite(scroll) or !std.math.isFinite(viewport_h)) {
        return .{ .start = 0, .end = count };
    }
    const view_top = @max(0.0, scroll);
    const view_bottom = view_top + @max(0.0, viewport_h);

    // Primeiro item com `offsets[i+1] > view_top` (busca binária).
    var lo: usize = 0;
    var hi: usize = count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const bottom = offsets[mid + 1];
        if (std.math.isFinite(bottom) and bottom > view_top) {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }
    const first_visible = @min(lo, count);

    // Último item com `offsets[i] < view_bottom` (busca binária).
    var lo2: usize = 0;
    var hi2: usize = count;
    while (lo2 < hi2) {
        const mid = lo2 + (hi2 - lo2) / 2;
        const top = offsets[mid];
        if (std.math.isFinite(top) and top < view_bottom) {
            lo2 = mid + 1;
        } else {
            hi2 = mid;
        }
    }
    const last_visible = @min(lo2, count);

    const start = if (first_visible >= overscan) first_visible - overscan else 0;
    const end = @min(count, last_visible + overscan);
    if (end <= start) return .{ .start = start, .end = start };
    return .{ .start = start, .end = end };
}

test "fixedRange: altura fixa, scroll e overscan" {
    const stdt = @import("std");

    // 100 itens de 10 px, janela de 50 px ⇒ 5 visíveis.
    const r = fixedRange(100, 10, 0, 50, 0);
    try stdt.testing.expectEqual(@as(usize, 0), r.start);
    try stdt.testing.expectEqual(@as(usize, 5), r.end);
    try stdt.testing.expectEqual(@as(usize, 5), r.len());

    // Scroll de 100 px ⇒ começa no item 10.
    const r2 = fixedRange(100, 10, 100, 50, 0);
    try stdt.testing.expectEqual(@as(usize, 10), r2.start);
    try stdt.testing.expectEqual(@as(usize, 15), r2.end);

    // Overscan de 2 itens antes e depois.
    const r3 = fixedRange(100, 10, 100, 50, 2);
    try stdt.testing.expectEqual(@as(usize, 8), r3.start);
    try stdt.testing.expectEqual(@as(usize, 17), r3.end);

    // Casos-limite: vazio, scroll negativo, scroll além do fim.
    try stdt.testing.expect(fixedRange(0, 10, 0, 50, 0).isEmpty());
    const r4 = fixedRange(100, 10, -20, 50, 0);
    try stdt.testing.expectEqual(@as(usize, 0), r4.start);
    const r5 = fixedRange(100, 10, 10_000, 50, 0);
    try stdt.testing.expect(r5.start <= 100);
    try stdt.testing.expect(r5.end <= 100);
    // Altura degenerada: devolve o primeiro item.
    const r6 = fixedRange(100, 0, 0, 50, 0);
    try stdt.testing.expectEqual(@as(usize, 0), r6.start);
    try stdt.testing.expectEqual(@as(usize, 1), r6.end);
    // Não-finitos: tudo (fallback seguro).
    try stdt.testing.expectEqual(@as(usize, 100), fixedRange(100, 10, std.math.nan(f32), 50, 0).end);
}

test "variableRange: offsets acumulados e busca binária" {
    const stdt = @import("std");

    // 4 itens: alturas 10, 20, 30, 40 (offsets 0, 10, 30, 60, 100).
    const offsets = [_]f32{ 0, 10, 30, 60, 100 };
    const r = variableRange(&offsets, 0, 25, 0);
    try stdt.testing.expectEqual(@as(usize, 0), r.start);
    try stdt.testing.expectEqual(@as(usize, 2), r.end);

    // Scroll 20: o item 1 (10..30) ainda aparece.
    const r2 = variableRange(&offsets, 20, 25, 0);
    try stdt.testing.expectEqual(@as(usize, 1), r2.start);
    try stdt.testing.expectEqual(@as(usize, 3), r2.end);

    // Overscan.
    const r3 = variableRange(&offsets, 20, 25, 1);
    try stdt.testing.expectEqual(@as(usize, 0), r3.start);
    try stdt.testing.expectEqual(@as(usize, 4), r3.end);

    // Casos-limite.
    try stdt.testing.expect(variableRange(&offsets, 0, 25, 0).end <= 4);
    try stdt.testing.expect(variableRange(&[_]f32{0}, 0, 25, 0).isEmpty());
    try stdt.testing.expectEqual(@as(usize, 4), variableRange(&offsets, std.math.nan(f32), 25, 0).end);
    // Scroll além do conteúdo: o intervalo esvazia no fim.
    const r4 = variableRange(&offsets, 10_000, 25, 0);
    try stdt.testing.expect(r4.isEmpty());
}
