//! ZyntraUI — layout flex (layout/flex).
//!
//! Escopo M128: distribuição de filhos em linha ou coluna com gap,
//! alinhamento nos dois eixos, crescimento (`grow`) e encolhimento
//! (`shrink`) no eixo principal. Geometria pura: sem alocação, sem
//! estado global, sem desenho.
//! - `Item`: tamanho base, frações de grow/shrink e limites no eixo
//!   principal.
//! - `flex`: preenche um slice de rects do chamador com a posição de
//!   cada filho.
//!
//! Semântica (determinística e previsível):
//! - o espaço extra (eixo principal) é distribuído na proporção dos
//!   `grow`; sem `grow`, sobra espaço vira margem de alinhamento;
//! - a falta de espaço é distribuída na proporção dos `shrink`, sem
//!   passar do `min_main` (o excedente que sobra é overflow);
//! - `Align.stretch` no eixo cruzado estica o filho na área inteira.
//!
//! Validação: área finita, `gap >= 0`, frações finitas e não-negativas,
//! `min_main <= max_main` e slice de saída com espaço para todos os
//! filhos.

const std = @import("std");
const types = @import("../core/types.zig");

/// Eixo principal do flex.
pub const Direction = enum {
    /// Filho principal na horizontal (largura).
    row,
    /// Filho principal na vertical (altura).
    column,
};

/// Alinhamento em um eixo.
pub const Align = enum {
    /// Encosta no início do eixo.
    start,
    /// Centraliza no eixo.
    center,
    /// Encosta no fim do eixo.
    end,
    /// Estica no eixo cruzado (ocupa a área inteira).
    stretch,
};

/// Filho do flex.
pub const Item = struct {
    /// Tamanho base (w/h). No eixo principal vale o limite do item.
    size: types.Size = .{},
    /// Fração do espaço EXTRA distribuído no eixo principal.
    grow: f32 = 0,
    /// Fração da falta de espaço removida no eixo principal.
    shrink: f32 = 0,
    /// Tamanho mínimo no eixo principal.
    min_main: f32 = 0,
    /// Tamanho máximo no eixo principal.
    max_main: f32 = std.math.inf(f32),

    pub fn isValid(self: Item) bool {
        return std.math.isFinite(self.size.w) and self.size.w >= 0 and
            std.math.isFinite(self.size.h) and self.size.h >= 0 and
            std.math.isFinite(self.grow) and self.grow >= 0 and
            std.math.isFinite(self.shrink) and self.shrink >= 0 and
            std.math.isFinite(self.min_main) and self.min_main >= 0 and
            self.max_main >= self.min_main and
            (std.math.isInf(self.max_main) or std.math.isFinite(self.max_main));
    }
};

/// Opções do flex.
pub const Options = struct {
    direction: Direction = .column,
    /// Espaço entre filhos (eixo principal).
    gap: f32 = 0,
    /// Alinhamento no eixo principal.
    main_align: Align = .start,
    /// Alinhamento no eixo cruzado.
    cross_align: Align = .start,
};

/// Erros do cálculo de flex.
pub const Error = error{
    /// Área ou item inválido (NaN/Inf, negativo, min > max).
    InvalidArgument,
    /// O slice de saída é menor que a lista de filhos.
    OutputTooSmall,
};

fn mainSize(s: types.Size, dir: Direction) f32 {
    return switch (dir) {
        .row => s.w,
        .column => s.h,
    };
}

fn crossSize(s: types.Size, dir: Direction) f32 {
    return switch (dir) {
        .row => s.h,
        .column => s.w,
    };
}

/// Calcula a posição de cada filho dentro de `area` e escreve em `out`
/// (um rect por filho, na mesma ordem).
pub fn flex(
    area: types.Rect,
    items: []const Item,
    opts: Options,
    out: []types.Rect,
) Error!void {
    if (!std.math.isFinite(area.x) or !std.math.isFinite(area.y) or
        !std.math.isFinite(area.w) or !std.math.isFinite(area.h))
    {
        return error.InvalidArgument;
    }
    if (area.w < 0 or area.h < 0) return error.InvalidArgument;
    if (!std.math.isFinite(opts.gap) or opts.gap < 0) return error.InvalidArgument;
    for (items) |it| {
        if (!it.isValid()) return error.InvalidArgument;
    }
    if (out.len < items.len) return error.OutputTooSmall;

    const dir = opts.direction;
    const main_avail = mainSize(area.size(), dir);
    const cross_avail = crossSize(area.size(), dir);
    const n = items.len;
    if (n == 0) return;

    // Passe 1: tamanho base de cada filho (limitado no eixo principal),
    // guardado no slice de saída como rascunho.
    var total_base: f32 = 0;
    var total_grow: f32 = 0;
    var total_shrink: f32 = 0;
    for (items, 0..) |it, i| {
        const raw = mainSize(it.size, dir);
        const clamped = std.math.clamp(raw, it.min_main, it.max_main);
        switch (dir) {
            .row => out[i].w = clamped,
            .column => out[i].h = clamped,
        }
        total_base += clamped;
        total_grow += it.grow;
        total_shrink += it.shrink;
    }
    const gaps = if (n > 1) opts.gap * @as(f32, @floatFromInt(n - 1)) else 0;
    const used = total_base + gaps;

    // Espaço extra → grow.
    if (used < main_avail and total_grow > 0) {
        const extra = main_avail - used;
        for (items, 0..) |it, i| {
            const share = extra * (it.grow / total_grow);
            const cur = switch (dir) {
                .row => out[i].w,
                .column => out[i].h,
            };
            const next = std.math.clamp(cur + share, it.min_main, it.max_main);
            switch (dir) {
                .row => out[i].w = next,
                .column => out[i].h = next,
            }
        }
    }
    // Falta de espaço → shrink (respeitando min_main).
    if (used > main_avail and total_shrink > 0) {
        const deficit = used - main_avail;
        for (items, 0..) |it, i| {
            const share = deficit * (it.shrink / total_shrink);
            const cur = switch (dir) {
                .row => out[i].w,
                .column => out[i].h,
            };
            const next = @max(it.min_main, cur - share);
            switch (dir) {
                .row => out[i].w = next,
                .column => out[i].h = next,
            }
        }
    }

    // Extensão realmente usada no eixo principal (para o alinhamento).
    var used_main: f32 = 0;
    for (out[0..n]) |r| used_main += mainSize(r.size(), dir);
    used_main += gaps;

    const main_offset = switch (opts.main_align) {
        .start, .stretch => 0,
        .center => (main_avail - used_main) / 2,
        .end => main_avail - used_main,
    };

    var cursor = main_offset;
    for (items, 0..) |it, i| {
        const cross_base = crossSize(it.size, dir);
        const cross = if (opts.cross_align == .stretch) cross_avail else cross_base;
        const cross_pos = switch (opts.cross_align) {
            .start, .stretch => 0,
            .center => (cross_avail - cross) / 2,
            .end => cross_avail - cross,
        };
        out[i] = switch (dir) {
            .row => .{
                .x = area.x + cursor,
                .y = area.y + cross_pos,
                .w = out[i].w,
                .h = cross,
            },
            .column => .{
                .x = area.x + cross_pos,
                .y = area.y + cursor,
                .w = cross,
                .h = out[i].h,
            },
        };
        cursor += mainSize(out[i].size(), dir) + opts.gap;
    }
}

test "flex linha: tamanhos fixos, gap e alinhamento" {
    const stdt = @import("std");
    var out: [3]types.Rect = undefined;
    const items = [_]Item{
        .{ .size = .{ .w = 10, .h = 20 } },
        .{ .size = .{ .w = 30, .h = 10 } },
        .{ .size = .{ .w = 20, .h = 5 } },
    };
    try flex(types.Rect.init(0, 0, 100, 40), &items, .{ .direction = .row, .gap = 5 }, &out);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 10, 20), out[0]);
    try stdt.testing.expectEqual(types.Rect.init(15, 0, 30, 10), out[1]);
    try stdt.testing.expectEqual(types.Rect.init(50, 0, 20, 5), out[2]);

    // Alinhamento no eixo principal: centro.
    try flex(types.Rect.init(0, 0, 100, 40), &items, .{ .direction = .row, .gap = 5, .main_align = .center }, &out);
    const used: f32 = 10 + 30 + 20 + 5 * 2;
    const off = (100 - used) / 2;
    try stdt.testing.expectEqual(@as(f32, off), out[0].x);

    // Alinhamento no eixo cruzado: centro e fim.
    try flex(types.Rect.init(0, 0, 100, 40), &items, .{ .direction = .row, .cross_align = .center }, &out);
    try stdt.testing.expectEqual(@as(f32, 10), out[0].y); // (40-20)/2
    try stdt.testing.expectEqual(@as(f32, 15), out[1].y); // (40-10)/2
    try stdt.testing.expectEqual(@as(f32, 17.5), out[2].y); // (40-5)/2

    // Eixo cruzado esticado ocupa a área inteira.
    try flex(types.Rect.init(0, 0, 100, 40), &items, .{ .direction = .row, .cross_align = .stretch }, &out);
    try stdt.testing.expectEqual(@as(f32, 40), out[0].h);
}

test "flex coluna: empilhamento e grow" {
    const stdt = @import("std");
    var out: [2]types.Rect = undefined;
    const items = [_]Item{
        .{ .size = .{ .w = 50, .h = 20 } },
        .{ .size = .{ .w = 50, .h = 20 }, .grow = 1 },
    };
    // O segundo filho tem grow=1: absorve o espaço extra (60 px).
    try flex(types.Rect.init(0, 0, 100, 100), &items, .{ .direction = .column }, &out);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 50, 20), out[0]);
    try stdt.testing.expectEqual(types.Rect.init(0, 20, 50, 80), out[1]);
    try stdt.testing.expectEqual(@as(f32, 20), out[0].h);
    try stdt.testing.expectEqual(@as(f32, 80), out[1].h);
}

test "flex grow proporcional e shrink limitado por min_main" {
    const stdt = @import("std");
    var out: [2]types.Rect = undefined;

    // Grow 1:2 em 300 px: base 100 (2x50) + 200 extra ⇒ 116.67 / 183.33.
    const grow_items = [_]Item{
        .{ .size = .{ .w = 50, .h = 10 }, .grow = 1 },
        .{ .size = .{ .w = 50, .h = 10 }, .grow = 2 },
    };
    try flex(types.Rect.init(0, 0, 300, 20), &grow_items, .{ .direction = .row }, &out);
    try stdt.testing.expectApproxEqAbs(@as(f32, 116.67), out[0].w, 0.01);
    try stdt.testing.expectApproxEqAbs(@as(f32, 183.33), out[1].w, 0.01);
    try stdt.testing.expectApproxEqAbs(@as(f32, 116.67), out[1].x, 0.01);

    // Shrink: área de 60 para 2 filhos de 50 com shrink 1 ⇒ 30 e 30.
    const shrink_items = [_]Item{
        .{ .size = .{ .w = 50, .h = 10 }, .shrink = 1 },
        .{ .size = .{ .w = 50, .h = 10 }, .shrink = 1 },
    };
    try flex(types.Rect.init(0, 0, 60, 20), &shrink_items, .{ .direction = .row }, &out);
    try stdt.testing.expectEqual(@as(f32, 30), out[0].w);
    try stdt.testing.expectEqual(@as(f32, 30), out[1].w);

    // Com min_main, o encolhimento para no limite.
    const min_items = [_]Item{
        .{ .size = .{ .w = 50, .h = 10 }, .shrink = 1, .min_main = 40 },
        .{ .size = .{ .w = 50, .h = 10 }, .shrink = 1 },
    };
    try flex(types.Rect.init(0, 0, 60, 20), &min_items, .{ .direction = .row }, &out);
    try stdt.testing.expectEqual(@as(f32, 40), out[0].w);
    // O primeiro parou no min_main (40); o segundo absorveu só a sua parte.
    try stdt.testing.expectEqual(@as(f32, 30), out[1].w);
}

test "flex recusa entradas inválidas" {
    const stdt = @import("std");
    var out: [2]types.Rect = undefined;
    const items = [_]Item{.{ .size = .{ .w = 10, .h = 10 } }};

    try stdt.testing.expectError(error.InvalidArgument, flex(
        types.Rect.init(0, 0, std.math.nan(f32), 10),
        &items,
        .{},
        &out,
    ));
    try stdt.testing.expectError(error.InvalidArgument, flex(
        types.Rect.init(0, 0, -1, 10),
        &items,
        .{},
        &out,
    ));
    try stdt.testing.expectError(error.InvalidArgument, flex(
        types.Rect.init(0, 0, 10, 10),
        &items,
        .{ .gap = -1 },
        &out,
    ));
    try stdt.testing.expectError(error.InvalidArgument, flex(
        types.Rect.init(0, 0, 10, 10),
        &[_]Item{.{ .grow = -1 }},
        .{},
        &out,
    ));
    try stdt.testing.expectError(error.InvalidArgument, flex(
        types.Rect.init(0, 0, 10, 10),
        &[_]Item{.{ .min_main = 20, .max_main = 10 }},
        .{},
        &out,
    ));
    const two = [_]Item{ .{ .size = .{ .w = 10, .h = 10 } }, .{ .size = .{ .w = 10, .h = 10 } } };
    try stdt.testing.expectError(error.OutputTooSmall, flex(
        types.Rect.init(0, 0, 10, 10),
        &two,
        .{},
        out[0..1],
    ));
}
