//! ZyntraUI — modelo de layout de docking (dock/layout).
//!
//! Modelo M75 (Docking, passo 2): a *estrutura* de um conjunto de painéis
//! acoplados — uma árvore binária de splits (horizontal/vertical) com
//! folhas identificadas por id de painel. Puro, sem alocação: a árvore
//! vive num array fixo dentro de `DockLayout` (o chamador é dono) e todas
//! as funções são determinísticas.
//!
//! - `dockInit(&layout, pane)` — layout de um único painel.
//! - `dockSplit(&layout, leaf, orientation, ratio, pane)` — transforma a
//!   folha em split e devolve o índice da nova folha (item 6, aninhável).
//! - `dockSetRatio` / `dockNodePane` / `dockLeafCount`.
//! - `dockRemovePane` — remove o painel e dissolve o split pai (o irmão
//!   ocupa o lugar), recomprimindo a árvore.
//! - `dockPaneRects` / `dockDividerRects` — geometria pura (rects dos
//!   painéis em pré-ordem e das divisórias), com `divider` px entre lados.
//!
//! Não desenha nem trata eventos: combine com `widgets/panel` (chrome) e
//! `widgets/splitter` (arraste) para interação. O descarte do layout
//! (persistência/versão) fica para um passo seguinte.

const std = @import("std");
const types = @import("../core/types.zig");

pub const DockOrientation = enum { horizontal, vertical };

pub const DockError = error{ InvalidIndex, NoSpace, OutOfBuffer };

pub const DockLayout = struct {
    /// Nós totais da árvore binária (N folhas ⇒ 2N-1 nós ⇒ 16 painéis).
    pub const max_nodes: usize = 32;
    /// Painéis simultâneos máximos (folhas).
    pub const max_panes: usize = (max_nodes + 1) / 2;

    const Split = struct {
        orientation: DockOrientation,
        ratio: f32,
        first: u8,
        second: u8,
    };

    const Node = union(enum) {
        leaf: u16,
        split: Split,
    };

    nodes: [max_nodes]Node = undefined,
    /// Nós alocados (os índices válidos são `0..len`).
    len: usize = 0,
    /// Índice do nó raiz. É `0` até uma remoção; `dockRemovePane`
    /// recompõe a árvore e o novo nó raiz pode cair em outro índice.
    root: u8 = 0,
};

fn clampRatio(ratio: f32) f32 {
    if (!std.math.isFinite(ratio)) return 0.5;
    return std.math.clamp(ratio, 0, 1);
}

/// Inicializa com um único painel (folha na raiz).
pub fn dockInit(layout: *DockLayout, pane: u16) void {
    layout.nodes[0] = .{ .leaf = pane };
    layout.len = 1;
    layout.root = 0;
}

/// Nós alocados (igual a `2*folhas - 1` num layout íntegro).
pub fn dockNodeCount(layout: *const DockLayout) usize {
    return layout.len;
}

/// Número de folhas alcançáveis a partir da raiz.
pub fn dockLeafCount(layout: *const DockLayout) usize {
    return countLeaves(layout, layout.root);
}

fn countLeaves(layout: *const DockLayout, node: u8) usize {
    return switch (layout.nodes[node]) {
        .leaf => 1,
        .split => |s| countLeaves(layout, s.first) + countLeaves(layout, s.second),
    };
}

/// Painel da folha `leaf_index`, ou `null` se o nó não for folha/índice.
pub fn dockNodePane(layout: *const DockLayout, leaf_index: usize) ?u16 {
    if (leaf_index >= layout.len) return null;
    return switch (layout.nodes[leaf_index]) {
        .leaf => |p| p,
        .split => null,
    };
}

/// Achata o split `leaf_index` (precisa ser folha) em dois lados; o painel
/// original fica no lado `first` e `pane` no lado `second`. Devolve o
/// índice do nó da nova folha. `ratio` é clampado a `[0,1]`.
///
/// A folha original é realocada para um nó livre (o split ocupa o índice
/// antigo, preservando a referência do pai quando `leaf_index` é filho).
pub fn dockSplit(
    layout: *DockLayout,
    leaf_index: usize,
    orientation: DockOrientation,
    ratio: f32,
    pane: u16,
) DockError!usize {
    if (leaf_index >= layout.len) return error.InvalidIndex;
    const original = switch (layout.nodes[leaf_index]) {
        .leaf => |p| p,
        .split => return error.InvalidIndex,
    };
    if (layout.len + 2 > DockLayout.max_nodes) return error.NoSpace;
    const keep: u8 = @intCast(layout.len);
    const fresh: u8 = @intCast(layout.len + 1);
    layout.nodes[keep] = .{ .leaf = original };
    layout.nodes[fresh] = .{ .leaf = pane };
    layout.nodes[leaf_index] = .{ .split = .{
        .orientation = orientation,
        .ratio = clampRatio(ratio),
        .first = keep,
        .second = fresh,
    } };
    layout.len += 2;
    return fresh;
}

/// Ajusta a proporção do split `split_index` (clampada). No-op se não for
/// split.
pub fn dockSetRatio(layout: *DockLayout, split_index: usize, ratio: f32) void {
    if (split_index >= layout.len) return;
    switch (layout.nodes[split_index]) {
        .leaf => {},
        .split => |*s| s.ratio = clampRatio(ratio),
    }
}

pub fn dockSplitRatio(layout: *const DockLayout, split_index: usize) ?f32 {
    if (split_index >= layout.len) return null;
    return switch (layout.nodes[split_index]) {
        .leaf => null,
        .split => |s| s.ratio,
    };
}

/// Remove o painel `pane` e dissolve o split pai: o irmão sobe para o
/// lugar do pai. Recompressa a árvore (sem órfãos). Falha (e devolve
/// `false`) se o painel não existir ou for o único.
pub fn dockRemovePane(layout: *DockLayout, pane: u16) bool {
    if (!hasPane(layout, pane)) return false;
    if (dockLeafCount(layout) <= 1) return false;
    var tmp: [DockLayout.max_nodes]DockLayout.Node = undefined;
    var out_len: usize = 0;
    const new_root = rebuildSkipping(layout, layout.root, pane, &tmp, &out_len) orelse return false;
    @memcpy(layout.nodes[0..out_len], tmp[0..out_len]);
    layout.len = out_len;
    layout.root = new_root;
    return true;
}

/// `true` se `pane` é uma folha da árvore (índices `0..len` são sempre
/// alcançáveis — remoções recompõem).
fn hasPane(layout: *const DockLayout, pane: u16) bool {
    var i: usize = 0;
    while (i < layout.len) : (i += 1) {
        switch (layout.nodes[i]) {
            .leaf => |p| if (p == pane) return true,
            .split => {},
        }
    }
    return false;
}

/// Reconstrói a subárvore `node` em `out`, ignorando a folha `skip`.
/// Pré-ordem: o índice devolvido é o do nó reconstruído. `null` se a
/// subárvore inteira foi ignorada.
fn rebuildSkipping(
    layout: *const DockLayout,
    node: u8,
    skip: u16,
    out: *[DockLayout.max_nodes]DockLayout.Node,
    out_len: *usize,
) ?u8 {
    switch (layout.nodes[node]) {
        .leaf => |p| {
            if (p == skip) return null;
            const here: u8 = @intCast(out_len.*);
            out[out_len.*] = .{ .leaf = p };
            out_len.* += 1;
            return here;
        },
        .split => |s| {
            const first_root = rebuildSkipping(layout, s.first, skip, out, out_len);
            const second_root = rebuildSkipping(layout, s.second, skip, out, out_len);
            if (first_root == null) return second_root;
            if (second_root == null) return first_root;
            const here: u8 = @intCast(out_len.*);
            out[out_len.*] = .{ .split = .{
                .orientation = s.orientation,
                .ratio = s.ratio,
                .first = first_root.?,
                .second = second_root.?,
            } };
            out_len.* += 1;
            return here;
        },
    }
}

/// Rects dos painéis (pré-ordem das folhas) dentro de `bounds`, com
/// `divider` px reservados entre os lados. Devolve o número de painéis
/// escritos (1..`DockLayout.max_panes`). `OutOfBuffer` se `out` for menor.
pub fn dockPaneRects(
    layout: *const DockLayout,
    bounds: types.Rect,
    divider: f32,
    out: []types.Rect,
) DockError!usize {
    var n: usize = 0;
    try paneRectsRec(layout, layout.root, bounds, sanitizeDivider(divider), out, &n);
    return n;
}

fn sanitizeDivider(divider: f32) f32 {
    if (!std.math.isFinite(divider) or divider < 0) return 0;
    return divider;
}

fn paneRectsRec(
    layout: *const DockLayout,
    node: u8,
    r: types.Rect,
    divider: f32,
    out: []types.Rect,
    n: *usize,
) DockError!void {
    switch (layout.nodes[node]) {
        .leaf => {
            if (n.* >= out.len) return error.OutOfBuffer;
            out[n.*] = r;
            n.* += 1;
        },
        .split => |s| {
            const sides = splitSides(r, s.orientation, s.ratio, divider);
            try paneRectsRec(layout, s.first, sides.first, divider, out, n);
            try paneRectsRec(layout, s.second, sides.second, divider, out, n);
        },
    }
}

/// Rects das divisórias (pré-ordem dos splits). `OutOfBuffer` se `out`
/// for menor que o número de splits.
pub fn dockDividerRects(
    layout: *const DockLayout,
    bounds: types.Rect,
    divider: f32,
    out: []types.Rect,
) DockError!usize {
    var n: usize = 0;
    try dividerRectsRec(layout, layout.root, bounds, sanitizeDivider(divider), out, &n);
    return n;
}

fn dividerRectsRec(
    layout: *const DockLayout,
    node: u8,
    r: types.Rect,
    divider: f32,
    out: []types.Rect,
    n: *usize,
) DockError!void {
    switch (layout.nodes[node]) {
        .leaf => {},
        .split => |s| {
            const sides = splitSides(r, s.orientation, s.ratio, divider);
            if (n.* >= out.len) return error.OutOfBuffer;
            out[n.*] = sides.divider;
            n.* += 1;
            try dividerRectsRec(layout, s.first, sides.first, divider, out, n);
            try dividerRectsRec(layout, s.second, sides.second, divider, out, n);
        },
    }
}

const Sides = struct { first: types.Rect, second: types.Rect, divider: types.Rect };

/// Divide `r`: `first` (proporção), `divider` (`divider` px centrados) e
/// `second`. A divisória é clampada dentro de `r`.
fn splitSides(r: types.Rect, orientation: DockOrientation, ratio: f32, divider: f32) Sides {
    const half = divider / 2;
    switch (orientation) {
        .horizontal => {
            const pos = r.y + r.h * ratio;
            const d0 = std.math.clamp(pos - half, r.y, @max(r.y, r.y + r.h - divider));
            return .{
                .first = .{ .x = r.x, .y = r.y, .w = r.w, .h = @max(0, pos - half - r.y) },
                .divider = .{ .x = r.x, .y = d0, .w = r.w, .h = @min(divider, r.h) },
                .second = .{ .x = r.x, .y = pos + half, .w = r.w, .h = @max(0, r.y + r.h - (pos + half)) },
            };
        },
        .vertical => {
            const pos = r.x + r.w * ratio;
            const d0 = std.math.clamp(pos - half, r.x, @max(r.x, r.x + r.w - divider));
            return .{
                .first = .{ .x = r.x, .y = r.y, .w = @max(0, pos - half - r.x), .h = r.h },
                .divider = .{ .x = d0, .y = r.y, .w = @min(divider, r.w), .h = r.h },
                .second = .{ .x = pos + half, .y = r.y, .w = @max(0, r.x + r.w - (pos + half)), .h = r.h },
            };
        },
    }
}

test "dock: init, split, proporção e rects (horizontal/vertical)" {
    const stdt = @import("std");
    const bounds = types.Rect.init(0, 0, 400, 300);
    var layout: DockLayout = undefined;

    dockInit(&layout, 7);
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&layout));
    try stdt.testing.expectEqual(@as(?u16, 7), dockNodePane(&layout, 0));

    // Split horizontal (divide na vertical): painel 7 em cima, 9 embaixo.
    const leaf_b = try dockSplit(&layout, 0, .horizontal, 0.5, 9);
    try stdt.testing.expectEqual(@as(usize, 2), leaf_b);
    try stdt.testing.expectEqual(@as(usize, 2), dockLeafCount(&layout));
    try stdt.testing.expectEqual(@as(usize, 3), dockNodeCount(&layout));
    try stdt.testing.expectEqual(@as(?u16, 9), dockNodePane(&layout, leaf_b));

    var panes: [DockLayout.max_panes]types.Rect = undefined;
    const np = try dockPaneRects(&layout, bounds, 8, &panes);
    try stdt.testing.expectEqual(@as(usize, 2), np);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 146), panes[0]);
    try stdt.testing.expectEqual(types.Rect.init(0, 154, 400, 146), panes[1]);

    var divs: [DockLayout.max_panes]types.Rect = undefined;
    const nd = try dockDividerRects(&layout, bounds, 8, &divs);
    try stdt.testing.expectEqual(@as(usize, 1), nd);
    try stdt.testing.expectEqual(types.Rect.init(0, 146, 400, 8), divs[0]);

    // Split vertical na segunda folha (9): 9 à esquerda, 11 à direita.
    const leaf_c = try dockSplit(&layout, leaf_b, .vertical, 0.5, 11);
    try stdt.testing.expectEqual(@as(usize, 3), dockLeafCount(&layout));
    const np2 = try dockPaneRects(&layout, bounds, 8, &panes);
    try stdt.testing.expectEqual(@as(usize, 3), np2);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 146), panes[0]);
    try stdt.testing.expectEqual(types.Rect.init(0, 154, 196, 146), panes[1]);
    try stdt.testing.expectEqual(types.Rect.init(204, 154, 196, 146), panes[2]);
    const nd2 = try dockDividerRects(&layout, bounds, 8, &divs);
    try stdt.testing.expectEqual(@as(usize, 2), nd2);
    // Pré-ordem dos splits: raiz (y=146) e depois o filho (x=196).
    try stdt.testing.expectEqual(types.Rect.init(0, 146, 400, 8), divs[0]);
    try stdt.testing.expectEqual(types.Rect.init(196, 154, 8, 146), divs[1]);

    // Proporção ajustável; não-split/clamp.
    dockSetRatio(&layout, 0, 0.25);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.25), dockSplitRatio(&layout, 0).?, 0.0001);
    dockSetRatio(&layout, 0, 2.0); // clampa
    try stdt.testing.expectApproxEqAbs(@as(f32, 1.0), dockSplitRatio(&layout, 0).?, 0.0001);
    dockSetRatio(&layout, 0, std.math.nan(f32)); // não-finito ⇒ 0.5
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), dockSplitRatio(&layout, 0).?, 0.0001);
    try stdt.testing.expectEqual(@as(?f32, null), dockSplitRatio(&layout, leaf_c)); // é folha
    dockSetRatio(&layout, 999, 0.5); // fora ⇒ no-op, sem crash
}

test "dock: remover painel dissolve o split e recompõe" {
    const stdt = @import("std");
    var layout: DockLayout = undefined;
    dockInit(&layout, 0);
    const b = try dockSplit(&layout, 0, .horizontal, 0.5, 1);
    _ = try dockSplit(&layout, b, .vertical, 0.5, 2);
    try stdt.testing.expectEqual(@as(usize, 3), dockLeafCount(&layout));
    try stdt.testing.expectEqual(@as(usize, 5), dockNodeCount(&layout));

    // Remove o painel 1 (nó do meio): o split vertical dissolve e o
    // painel 2 sobe para o lado inferior (fica com o irmão... na verdade
    // o irmão de 1 é 2, então 2 ocupa o lugar do split).
    try stdt.testing.expect(dockRemovePane(&layout, 1));
    try stdt.testing.expectEqual(@as(usize, 2), dockLeafCount(&layout));
    try stdt.testing.expectEqual(@as(usize, 3), dockNodeCount(&layout));
    try stdt.testing.expectEqual(@as(?u16, 0), dockNodePane(&layout, 0));
    try stdt.testing.expectEqual(@as(?u16, 2), dockNodePane(&layout, 1));

    var panes: [DockLayout.max_panes]types.Rect = undefined;
    const np = try dockPaneRects(&layout, types.Rect.init(0, 0, 400, 300), 8, &panes);
    try stdt.testing.expectEqual(@as(usize, 2), np);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 146), panes[0]);
    try stdt.testing.expectEqual(types.Rect.init(0, 154, 400, 146), panes[1]);

    // Remover o último restante é recusado (não deixa layout vazio).
    try stdt.testing.expect(dockRemovePane(&layout, 2));
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&layout));
    try stdt.testing.expect(!dockRemovePane(&layout, 0));
    try stdt.testing.expect(!dockRemovePane(&layout, 42)); // inexistente
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&layout));
}

test "dock: limites, erros e buffer pequeno" {
    const stdt = @import("std");
    var layout: DockLayout = undefined;
    dockInit(&layout, 0);

    // Split em nó que não é folha ⇒ InvalidIndex; índice fora ⇒ idem.
    _ = try dockSplit(&layout, 0, .horizontal, 0.5, 1);
    try stdt.testing.expectError(error.InvalidIndex, dockSplit(&layout, 0, .vertical, 0.5, 2));
    try stdt.testing.expectError(error.InvalidIndex, dockSplit(&layout, 99, .vertical, 0.5, 2));

    // Esgota a capacidade: cada split adiciona uma folha.
    var next: u16 = 2;
    var idx: usize = 1;
    while (true) {
        const before = layout.len;
        _ = dockSplit(&layout, idx, .horizontal, 0.5, next) catch break;
        try stdt.testing.expect(layout.len > before);
        idx = layout.len - 1;
        next += 1;
    }
    try stdt.testing.expectEqual(DockLayout.max_panes, dockLeafCount(&layout));

    // Buffer pequeno ⇒ OutOfBuffer (sem escrever além).
    var tiny: [1]types.Rect = undefined;
    try stdt.testing.expectError(error.OutOfBuffer, dockPaneRects(&layout, types.Rect.init(0, 0, 100, 100), 4, &tiny));
    try stdt.testing.expectError(error.OutOfBuffer, dockDividerRects(&layout, types.Rect.init(0, 0, 100, 100), 4, &tiny));

    // Proporções degeneradas: lados nunca negativos e divisória dentro
    // dos limites.
    var l2: DockLayout = undefined;
    dockInit(&l2, 0);
    _ = try dockSplit(&l2, 0, .vertical, 0, 1);
    var two: [2]types.Rect = undefined;
    try stdt.testing.expectEqual(@as(usize, 2), try dockPaneRects(&l2, types.Rect.init(0, 0, 100, 50), 8, &two));
    try stdt.testing.expectEqual(@as(f32, 0), two[0].w);
    try stdt.testing.expectEqual(@as(f32, 96), two[1].w);
    var div_one: [1]types.Rect = undefined;
    try stdt.testing.expectEqual(@as(usize, 1), try dockDividerRects(&l2, types.Rect.init(0, 0, 100, 50), 8, &div_one));
    try stdt.testing.expect(div_one[0].x >= 0 and div_one[0].x + div_one[0].w <= 100);
}
