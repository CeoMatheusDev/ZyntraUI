//! ZyntraUI — modelo de layout de docking (dock/layout).
//!
//! Modelo M75 (Docking, passo 2): a *estrutura* de um conjunto de painéis
//! acoplados — uma árvore binária de splits (horizontal/vertical) cujas
//! folhas são *grupos* de painéis acoplados como abas (`DockGroup`). Puro,
//! sem alocação: a árvore vive num array fixo dentro de `DockLayout` (o
//! chamador é dono) e todas as funções são determinísticas.
//!
//! - `dockInit(&layout, pane)` — layout de um único painel.
//! - `dockSplit(&layout, leaf, orientation, ratio, pane)` — transforma a
//!   folha (grupo) em split e devolve o índice da nova folha (item 6,
//!   aninhável). O grupo original fica num lado e `pane` no outro.
//! - `dockSetRatio` / `dockNodePane` (painel ativo) / `dockLeafCount`.
//! - Abas (passo 4a): `dockGroup`/`dockGroupMut` leem o grupo (abas +
//!   ativo), `dockAddTab`/`dockRemoveTab` anexam/removem abas e
//!   `dockSetActiveTab` troca a aba visível. Um grupo vazio é dissolvido.
//! - `dockRemovePane` — remove o painel (aba ou grupo inteiro); se era a
//!   última aba do grupo, dissolve o split pai (o irmão ocupa o lugar),
//!   recomprimindo a árvore.
//! - `dockPaneRects` / `dockDividerRects` — geometria pura (rects dos
//!   grupos em pré-ordem e das divisórias), com `divider` px entre lados.
//! - `dockSplits` — pré-ordem dos splits com nó/orientação/ratio/área e
//!   faixa da divisória (base de `widgets/dock_view`, passo 3).
//! - `dockPanes` — pré-ordem dos grupos com nó + abas/ativo + rect (base
//!   do hit-test e das barras de abas).
//! - Re-acoplagem (passo 4): `dockDropZone`/`dockZoneRect` resolvem a zona
//!   sob o cursor e o realce; `dockMovePane` redivide um grupo alvo numa
//!   borda, `dockMergeTab` acopla o painel como aba do grupo alvo,
//!   `dockSwapPanes` troca dois painéis entre grupos e `dockApplyDrop`
//!   despacha (borda ⇒ redivide; centro ⇒ vira aba).
//!
//! Não desenha nem trata eventos: combine com `widgets/panel` (chrome), e
//! `widgets/dock_view` (divisórias arrastáveis + drop) para interação. O
//! descarte do layout (persistência/versão) fica para um passo seguinte.

const std = @import("std");
const types = @import("../core/types.zig");

pub const DockOrientation = enum { horizontal, vertical };

pub const DockError = error{ InvalidIndex, NoSpace, OutOfBuffer };

/// Grupo de painéis acoplados como abas (M78, passo 4a): até `max_tabs`
/// painéis, um deles ativo. Vive na folha da árvore (as abas viajam com
/// ela em splits/remoções). Invariante: `count >= 1` enquanto o grupo
/// existe na árvore (grupo vazio é dissolvido).
pub const DockGroup = struct {
    /// Abas simultâneas por grupo.
    pub const max_tabs: usize = 4;

    panes: [max_tabs]u16 = undefined,
    count: u8 = 0,
    /// Índice da aba ativa (`0..count`).
    active: u8 = 0,

    /// Grupo de um único painel.
    pub fn single(pane: u16) DockGroup {
        var g = DockGroup{};
        g.panes[0] = pane;
        g.count = 1;
        g.active = 0;
        return g;
    }

    /// Abas em ordem (`panes[0..count]`).
    pub fn tabs(self: *const DockGroup) []const u16 {
        return self.panes[0..self.count];
    }

    /// Painel ativo (o que o chamador desenha no corpo do grupo).
    pub fn activePane(self: *const DockGroup) u16 {
        if (self.count == 0) return 0; // grupo vazio não persiste na árvore
        return self.panes[self.active];
    }

    pub fn isFull(self: *const DockGroup) bool {
        return self.count >= max_tabs;
    }

    /// Posição da aba `pane`, ou `null`.
    pub fn indexOf(self: *const DockGroup, pane: u16) ?usize {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.panes[i] == pane) return i;
        }
        return null;
    }

    /// Anexa `pane` como última aba e a torna ativa. `false` se o grupo
    /// estiver cheio ou já contiver o painel.
    pub fn add(self: *DockGroup, pane: u16) bool {
        if (self.isFull() or self.indexOf(pane) != null) return false;
        self.panes[self.count] = pane;
        self.count += 1;
        self.active = self.count - 1;
        return true;
    }

    /// Remove a aba na posição `i` (deslocando as seguintes) e ajusta o
    /// índice ativo. `false` se `i` estiver fora da faixa.
    pub fn removeAt(self: *DockGroup, i: usize) bool {
        if (i >= self.count) return false;
        var k = i;
        while (k + 1 < self.count) : (k += 1) self.panes[k] = self.panes[k + 1];
        self.count -= 1;
        if (self.count == 0) {
            self.active = 0;
        } else if (self.active >= self.count) {
            self.active = self.count - 1;
        } else if (i < self.active) {
            self.active -= 1;
        }
        return true;
    }

    /// Remove a aba `pane`. `false` se não estiver no grupo.
    pub fn remove(self: *DockGroup, pane: u16) bool {
        const i = self.indexOf(pane) orelse return false;
        return self.removeAt(i);
    }
};

pub const DockLayout = struct {
    /// Nós totais da árvore binária (N grupos ⇒ 2N-1 nós).
    pub const max_nodes: usize = 32;
    /// Grupos (folhas) simultâneos máximos. Com abas, o total de painéis
    /// pode chegar a `max_panes * DockGroup.max_tabs`.
    pub const max_panes: usize = (max_nodes + 1) / 2;

    const Split = struct {
        orientation: DockOrientation,
        ratio: f32,
        first: u8,
        second: u8,
    };

    const Node = union(enum) {
        leaf: DockGroup,
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

/// Inicializa com um grupo de um único painel (folha na raiz).
pub fn dockInit(layout: *DockLayout, pane: u16) void {
    layout.nodes[0] = .{ .leaf = DockGroup.single(pane) };
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

/// Painel ativo do grupo da folha `leaf_index`, ou `null` se o nó não for
/// folha/índice. (Um grupo pode ter várias abas: veja `dockGroup`.)
pub fn dockNodePane(layout: *const DockLayout, leaf_index: usize) ?u16 {
    if (leaf_index >= layout.len) return null;
    return switch (layout.nodes[leaf_index]) {
        .leaf => |g| g.activePane(),
        .split => null,
    };
}

/// Cópia do grupo da folha `leaf_index` (abas + ativo), ou `null` se o nó
/// não for folha/índice.
pub fn dockGroup(layout: *const DockLayout, leaf_index: usize) ?DockGroup {
    if (leaf_index >= layout.len) return null;
    return switch (layout.nodes[leaf_index]) {
        .leaf => |g| g,
        .split => null,
    };
}

/// Painel ativo da folha `leaf_index` como `*DockGroup` mutável (para o
/// chamador trocar a aba ativa ou mexer nas abas via `DockGroup`), ou
/// `null` se o nó não for folha/índice.
pub fn dockGroupMut(layout: *DockLayout, leaf_index: usize) ?*DockGroup {
    if (leaf_index >= layout.len) return null;
    return switch (layout.nodes[leaf_index]) {
        .leaf => |*g| g,
        .split => null,
    };
}

/// Ativa a aba `tab` da folha `leaf_index`. `false` se o nó não for folha
/// ou `tab` estiver fora da faixa.
pub fn dockSetActiveTab(layout: *DockLayout, leaf_index: usize, tab: usize) bool {
    const g = dockGroupMut(layout, leaf_index) orelse return false;
    if (tab >= g.count) return false;
    g.active = @intCast(tab);
    return true;
}

/// Anexa `pane` como última aba do grupo da folha `leaf_index` (e a
/// ativa). `false` se o nó não for folha, o grupo estiver cheio
/// (`DockGroup.max_tabs`) ou já contiver o painel.
pub fn dockAddTab(layout: *DockLayout, leaf_index: usize, pane: u16) bool {
    const g = dockGroupMut(layout, leaf_index) orelse return false;
    return g.add(pane);
}

/// Remove a aba `pane` do grupo da folha `leaf_index`. Se era a última
/// aba do grupo, dissolve a folha (o irmão sobe, como
/// `dockRemovePane`). `false` se não houver mudança.
pub fn dockRemoveTab(layout: *DockLayout, leaf_index: usize, pane: u16) bool {
    const g = dockGroupMut(layout, leaf_index) orelse return false;
    if (g.count <= 1) return dockRemovePane(layout, pane);
    return g.remove(pane);
}

/// Achata o split `leaf_index` (precisa ser folha) em dois lados; o grupo
/// original fica no lado `first` e um grupo novo com `pane` no lado
/// `second`. Devolve o índice do nó da nova folha. `ratio` é clampado a
/// `[0,1]`.
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
    return dockSplitOrdered(layout, leaf_index, orientation, ratio, pane, false);
}

/// Como `dockSplit`, mas `pane_first` decide em qual lado o grupo novo
/// fica (`true` ⇒ lado inicial). Devolve o índice da folha de `pane`
/// (`dockMovePane` precisa dele para posicionar o painel movido).
pub fn dockSplitOrdered(
    layout: *DockLayout,
    leaf_index: usize,
    orientation: DockOrientation,
    ratio: f32,
    pane: u16,
    pane_first: bool,
) DockError!usize {
    if (leaf_index >= layout.len) return error.InvalidIndex;
    const original = switch (layout.nodes[leaf_index]) {
        .leaf => |g| g,
        .split => return error.InvalidIndex,
    };
    if (layout.len + 2 > DockLayout.max_nodes) return error.NoSpace;
    const keep: u8 = @intCast(layout.len);
    const fresh: u8 = @intCast(layout.len + 1);
    layout.nodes[keep] = .{ .leaf = original };
    layout.nodes[fresh] = .{ .leaf = DockGroup.single(pane) };
    layout.nodes[leaf_index] = .{ .split = .{
        .orientation = orientation,
        .ratio = clampRatio(ratio),
        .first = if (pane_first) fresh else keep,
        .second = if (pane_first) keep else fresh,
    } };
    layout.len += 2;
    return if (pane_first) keep else fresh;
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

/// Remove o painel `pane`: tira a aba do grupo e, se era a última aba,
/// dissolve a folha (o irmão sobe para o lugar do pai) recompactando a
/// árvore. Falha (e devolve `false`) se o painel não existir ou for o
/// único de um layout de um grupo só.
pub fn dockRemovePane(layout: *DockLayout, pane: u16) bool {
    const node = dockFindPane(layout, pane) orelse return false;
    const group = dockGroupMut(layout, node) orelse return false;
    if (group.count > 1) return group.remove(pane);
    if (dockLeafCount(layout) <= 1) return false;
    var tmp: [DockLayout.max_nodes]DockLayout.Node = undefined;
    var out_len: usize = 0;
    const new_root = rebuildSkipping(layout, layout.root, pane, &tmp, &out_len) orelse return false;
    @memcpy(layout.nodes[0..out_len], tmp[0..out_len]);
    layout.len = out_len;
    layout.root = new_root;
    return true;
}

/// Índice do nó da folha cujo grupo contém `pane`, ou `null` se não
/// existir (índices `0..len` são sempre alcançáveis — remoções recompõem).
pub fn dockFindPane(layout: *const DockLayout, pane: u16) ?usize {
    var i: usize = 0;
    while (i < layout.len) : (i += 1) {
        switch (layout.nodes[i]) {
            .leaf => |g| if (g.indexOf(pane) != null) return i,
            .split => {},
        }
    }
    return null;
}

/// Reconstrói a subárvore `node` em `out`, removendo a aba `skip`. Se um
/// grupo ficar vazio ele é ignorado. Pré-ordem: o índice devolvido é o do
/// nó reconstruído. `null` se a subárvore inteira foi ignorada.
fn rebuildSkipping(
    layout: *const DockLayout,
    node: u8,
    skip: u16,
    out: *[DockLayout.max_nodes]DockLayout.Node,
    out_len: *usize,
) ?u8 {
    switch (layout.nodes[node]) {
        .leaf => |group| {
            var g = group;
            _ = g.remove(skip); // no-op se o grupo não tem a aba
            if (g.count == 0) return null;
            const here: u8 = @intCast(out_len.*);
            out[out_len.*] = .{ .leaf = g };
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

/// Grupo numa pré-ordem das folhas: nó + grupo (abas/ativo) + rect.
pub const DockPaneInfo = struct {
    /// Índice do nó da folha (aceito por `dockGroup`/`dockSetActiveTab`).
    node: u8,
    /// Grupo (abas + aba ativa) da folha.
    group: DockGroup,
    rect: types.Rect,

    /// Painel ativo do grupo (o que o corpo deve desenhar).
    pub fn pane(self: *const DockPaneInfo) u16 {
        return self.group.activePane();
    }
};

/// Grupos (abas + rect) em pré-ordem das folhas, dentro de `bounds`, com
/// `divider` px reservados entre os lados. Devolve o número de grupos
/// escritos (1..`DockLayout.max_panes`). `OutOfBuffer` se `out` for menor.
pub fn dockPanes(
    layout: *const DockLayout,
    bounds: types.Rect,
    divider: f32,
    out: []DockPaneInfo,
) DockError!usize {
    var n: usize = 0;
    try panesRec(layout, layout.root, bounds, sanitizeDivider(divider), out, &n);
    return n;
}

fn sanitizeDivider(divider: f32) f32 {
    if (!std.math.isFinite(divider) or divider < 0) return 0;
    return divider;
}

fn panesRec(
    layout: *const DockLayout,
    node: u8,
    r: types.Rect,
    divider: f32,
    out: []DockPaneInfo,
    n: *usize,
) DockError!void {
    switch (layout.nodes[node]) {
        .leaf => |g| {
            if (n.* >= out.len) return error.OutOfBuffer;
            out[n.*] = .{ .node = node, .group = g, .rect = r };
            n.* += 1;
        },
        .split => |s| {
            const sides = splitSides(r, s.orientation, s.ratio, divider);
            try panesRec(layout, s.first, sides.first, divider, out, n);
            try panesRec(layout, s.second, sides.second, divider, out, n);
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
    var tmp: [DockLayout.max_panes]DockPaneInfo = undefined;
    const n = try dockPanes(layout, bounds, divider, &tmp);
    if (n > out.len) return error.OutOfBuffer;
    for (tmp[0..n], 0..) |info, i| out[i] = info.rect;
    return n;
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

/// Informação de um split para interação/desenho (M76): o índice do nó
/// (aceito por `dockSetRatio`), a orientação, o ratio atual, a área total
/// do split (base do clamp do arraste) e a faixa da divisória.
pub const DockSplitInfo = struct {
    node: u8,
    orientation: DockOrientation,
    ratio: f32,
    rect: types.Rect,
    divider: types.Rect,
};

/// Infos dos splits (pré-ordem: pai antes dos filhos), dentro de `bounds`,
/// com `divider` px entre os lados. Devolve quantos foram escritos
/// (`≤ folhas - 1`). `OutOfBuffer` se `out` for menor.
pub fn dockSplits(
    layout: *const DockLayout,
    bounds: types.Rect,
    divider: f32,
    out: []DockSplitInfo,
) DockError!usize {
    var n: usize = 0;
    try splitsRec(layout, layout.root, bounds, sanitizeDivider(divider), out, &n);
    return n;
}

fn splitsRec(
    layout: *const DockLayout,
    node: u8,
    r: types.Rect,
    divider: f32,
    out: []DockSplitInfo,
    n: *usize,
) DockError!void {
    switch (layout.nodes[node]) {
        .leaf => {},
        .split => |s| {
            const sides = splitSides(r, s.orientation, s.ratio, divider);
            if (n.* >= out.len) return error.OutOfBuffer;
            out[n.*] = .{
                .node = node,
                .orientation = s.orientation,
                .ratio = s.ratio,
                .rect = r,
                .divider = sides.divider,
            };
            n.* += 1;
            try splitsRec(layout, s.first, sides.first, divider, out, n);
            try splitsRec(layout, s.second, sides.second, divider, out, n);
        },
    }
}

/// Zona de acoplamento dentro do rect de um painel alvo: uma borda
/// (redivide o alvo) ou o centro (troca os painéis de lugar).
pub const DockZone = enum { left, right, top, bottom, center };

/// Zona do `point` dentro do rect de um painel, com `edge` (fração do lado
/// disparada por vez, clampada a `[0, 0.5]`). Rect degenerado ⇒ `.center`.
/// Empates (cantos) resolvem na ordem left → right → top → bottom.
pub fn dockDropZone(rect: types.Rect, point: types.Vec2, edge: f32) DockZone {
    if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or
        !std.math.isFinite(rect.w) or !std.math.isFinite(rect.h) or
        !std.math.isFinite(point.x) or !std.math.isFinite(point.y))
    {
        return .center;
    }
    if (rect.w <= 0 or rect.h <= 0) return .center;
    const e = std.math.clamp(if (std.math.isFinite(edge)) edge else 0.25, 0, 0.5);
    const dx_left = (point.x - rect.x) / rect.w;
    const dx_right = 1 - dx_left;
    const dy_top = (point.y - rect.y) / rect.h;
    const dy_bottom = 1 - dy_top;
    const min = @min(@min(dx_left, dx_right), @min(dy_top, dy_bottom));
    if (min > e) return .center;
    if (dx_left == min) return .left;
    if (dx_right == min) return .right;
    if (dy_top == min) return .top;
    return .bottom;
}

/// Rect do realce de uma zona dentro do rect do alvo (metade do lado, ou
/// o rect inteiro no centro).
pub fn dockZoneRect(rect: types.Rect, zone: DockZone) types.Rect {
    const half_w = rect.w / 2;
    const half_h = rect.h / 2;
    return switch (zone) {
        .left => .{ .x = rect.x, .y = rect.y, .w = half_w, .h = rect.h },
        .right => .{ .x = rect.x + half_w, .y = rect.y, .w = half_w, .h = rect.h },
        .top => .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = half_h },
        .bottom => .{ .x = rect.x, .y = rect.y + half_h, .w = rect.w, .h = half_h },
        .center => rect,
    };
}

/// Move o painel `pane` para a borda `zone` do grupo do painel `target`:
/// remove `pane` de onde está (aba ou grupo) e redivide o grupo alvo, com
/// o painel movido no lado correspondente (`.left`/`.top` ⇒ lado inicial;
/// `.right`/`.bottom` ⇒ lado final). `.center` é recusado (use
/// `dockMergeTab`). Devolve `false` sem efeito se a operação for inválida
/// (`pane == target`, painel inexistente ou `pane` no mesmo grupo alvo).
pub fn dockMovePane(layout: *DockLayout, pane: u16, target: u16, zone: DockZone) bool {
    const orientation: DockOrientation = switch (zone) {
        .left, .right => .vertical,
        .top, .bottom => .horizontal,
        .center => return false,
    };
    const pane_first = switch (zone) {
        .left, .top => true,
        .right, .bottom => false,
        .center => return false,
    };
    if (pane == target) return false;
    const src = dockFindPane(layout, pane) orelse return false;
    const dst = dockFindPane(layout, target) orelse return false;
    if (src == dst) return false; // já estão no mesmo grupo
    if (!dockRemovePane(layout, pane)) return false;
    const idx = dockFindPane(layout, target) orelse return false;
    _ = dockSplitOrdered(layout, idx, orientation, 0.5, pane, pane_first) catch return false;
    return true;
}

/// Troca os painéis `a` e `b` de posição entre grupos (a estrutura não
/// muda: as abas correspondentes trocam, então cada painel passa a ocupar
/// o rect do outro). `false` se algum não existir, `a == b` ou os dois
/// estiverem no mesmo grupo (aí trocar de aba é `dockSetActiveTab`).
pub fn dockSwapPanes(layout: *DockLayout, a: u16, b: u16) bool {
    if (a == b) return false;
    const ia = dockFindPane(layout, a) orelse return false;
    const ib = dockFindPane(layout, b) orelse return false;
    if (ia == ib) return false;
    const ga = dockGroupMut(layout, ia) orelse return false;
    const gb = dockGroupMut(layout, ib) orelse return false;
    ga.panes[ga.indexOf(a).?] = b;
    gb.panes[gb.indexOf(b).?] = a;
    return true;
}

/// Aplica um drop do painel `pane` sobre `target` na `zone`: borda ⇒
/// `dockMovePane` (redivide o grupo alvo); centro ⇒ `dockMergeTab` (o
/// painel vira aba do grupo alvo).
pub fn dockApplyDrop(layout: *DockLayout, pane: u16, target: u16, zone: DockZone) bool {
    return switch (zone) {
        .center => dockMergeTab(layout, pane, target),
        else => dockMovePane(layout, pane, target, zone),
    };
}

/// Acopla `pane` como aba do grupo de `target`: remove o painel de origem
/// (dissolvendo o grupo dele se ficar vazio) e anexa ao grupo alvo, que
/// passa a tê-lo ativo. `false` sem efeito se `pane == target`, já forem o
/// mesmo grupo, o grupo alvo estiver cheio (`DockGroup.max_tabs`) ou algum
/// painel não existir.
pub fn dockMergeTab(layout: *DockLayout, pane: u16, target: u16) bool {
    if (pane == target) return false;
    const src = dockFindPane(layout, pane) orelse return false;
    const dst = dockFindPane(layout, target) orelse return false;
    if (src == dst) return false; // já são abas do mesmo grupo
    const g = dockGroupMut(layout, dst) orelse return false;
    if (g.isFull()) return false;
    if (!dockRemovePane(layout, pane)) return false;
    // A remoção pode recompactar a árvore: reencontra o grupo alvo.
    const dst2 = dockFindPane(layout, target) orelse return false;
    return dockAddTab(layout, dst2, pane);
}

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

    // Infos dos splits (mesma pré-ordem): nó, orientação, área, divisória.
    var infos: [DockLayout.max_panes]DockSplitInfo = undefined;
    const ni = try dockSplits(&layout, bounds, 8, &infos);
    try stdt.testing.expectEqual(@as(usize, 2), ni);
    try stdt.testing.expectEqual(@as(u8, 0), infos[0].node);
    try stdt.testing.expectEqual(DockOrientation.horizontal, infos[0].orientation);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), infos[0].ratio, 0.0001);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 400, 300), infos[0].rect);
    try stdt.testing.expectEqual(types.Rect.init(0, 146, 400, 8), infos[0].divider);
    try stdt.testing.expectEqual(@as(u8, @intCast(leaf_b)), infos[1].node);
    try stdt.testing.expectEqual(DockOrientation.vertical, infos[1].orientation);
    try stdt.testing.expectEqual(types.Rect.init(0, 154, 400, 146), infos[1].rect);
    try stdt.testing.expectEqual(types.Rect.init(196, 154, 8, 146), infos[1].divider);

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
    var tiny_info: [1]DockSplitInfo = undefined;
    try stdt.testing.expectError(error.OutOfBuffer, dockSplits(&layout, types.Rect.init(0, 0, 100, 100), 4, &tiny_info));

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

test "dock: painéis (id + rect) e busca por id" {
    const stdt = @import("std");
    var layout: DockLayout = undefined;
    dockInit(&layout, 5);
    const b = try dockSplit(&layout, 0, .vertical, 0.5, 6);
    _ = try dockSplit(&layout, b, .horizontal, 0.5, 7);

    var infos: [DockLayout.max_panes]DockPaneInfo = undefined;
    const n = try dockPanes(&layout, types.Rect.init(0, 0, 400, 300), 8, &infos);
    try stdt.testing.expectEqual(@as(usize, 3), n);
    // Mesma pré-ordem/geometria de `dockPaneRects`.
    var rects: [DockLayout.max_panes]types.Rect = undefined;
    const nr = try dockPaneRects(&layout, types.Rect.init(0, 0, 400, 300), 8, &rects);
    try stdt.testing.expectEqual(n, nr);
    for (infos[0..n], rects[0..nr]) |info, r| try stdt.testing.expectEqual(r, info.rect);
    try stdt.testing.expectEqual(@as(u16, 5), infos[0].pane());
    try stdt.testing.expectEqual(@as(u16, 6), infos[1].pane());
    try stdt.testing.expectEqual(@as(u16, 7), infos[2].pane());

    // `dockFindPane` acha o nó da folha; reforça o contrato de `hasPane`
    // já removido (remoção por id).
    try stdt.testing.expectEqual(@as(?usize, 1), dockFindPane(&layout, 5));
    try stdt.testing.expectEqual(@as(?u16, 7), dockNodePane(&layout, dockFindPane(&layout, 7).?));
    try stdt.testing.expectEqual(@as(?usize, null), dockFindPane(&layout, 99));
    try stdt.testing.expect(!dockRemovePane(&layout, 99));
}

test "dock: zonas de drop e realce" {
    const stdt = @import("std");
    const rect = types.Rect.init(0, 0, 100, 200);
    const left = types.Vec2.init(5, 100);
    const right = types.Vec2.init(95, 100);
    const top = types.Vec2.init(50, 5);
    const bottom = types.Vec2.init(50, 195);
    const center = types.Vec2.init(50, 100);

    try stdt.testing.expectEqual(DockZone.left, dockDropZone(rect, left, 0.25));
    try stdt.testing.expectEqual(DockZone.right, dockDropZone(rect, right, 0.25));
    try stdt.testing.expectEqual(DockZone.top, dockDropZone(rect, top, 0.25));
    try stdt.testing.expectEqual(DockZone.bottom, dockDropZone(rect, bottom, 0.25));
    try stdt.testing.expectEqual(DockZone.center, dockDropZone(rect, center, 0.25));

    // Fora do rect não é o hit-test (é do chamador): a métrica mais próxima
    // vence (aqui, a borda esquerda).
    try stdt.testing.expectEqual(DockZone.left, dockDropZone(rect, types.Vec2.init(-10, -10), 0.25));
    // Limites: `edge = 0` só dispara exatamente na borda; `edge > 0.5` é
    // clampado (aqui 0.9 ⇒ 0.5, e ainda assim é borda, não centro).
    try stdt.testing.expectEqual(DockZone.left, dockDropZone(rect, types.Vec2.init(0, 100), 0));
    try stdt.testing.expectEqual(DockZone.center, dockDropZone(rect, types.Vec2.init(1, 100), 0));
    try stdt.testing.expectEqual(DockZone.left, dockDropZone(rect, types.Vec2.init(49, 100), 0.5));
    try stdt.testing.expectEqual(DockZone.left, dockDropZone(rect, types.Vec2.init(30, 110), 0.9));
    // `edge` não-finito cai no padrão (0.25).
    try stdt.testing.expectEqual(DockZone.left, dockDropZone(rect, left, std.math.nan(f32)));
    // Rect degenerado/não-finito ⇒ centro.
    try stdt.testing.expectEqual(DockZone.center, dockDropZone(types.Rect.init(0, 0, 0, 200), center, 0.25));
    try stdt.testing.expectEqual(DockZone.center, dockDropZone(types.Rect.init(std.math.nan(f32), 0, 10, 10), center, 0.25));

    // Realce: metade correspondente, ou o rect inteiro no centro.
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 50, 200), dockZoneRect(rect, .left));
    try stdt.testing.expectEqual(types.Rect.init(50, 0, 50, 200), dockZoneRect(rect, .right));
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 100, 100), dockZoneRect(rect, .top));
    try stdt.testing.expectEqual(types.Rect.init(0, 100, 100, 100), dockZoneRect(rect, .bottom));
    try stdt.testing.expectEqual(rect, dockZoneRect(rect, .center));
}

test "dock: mover e trocar painéis (drop)" {
    const stdt = @import("std");
    const bounds = types.Rect.init(0, 0, 400, 300);

    // Painel 0 à esquerda; 1 e 2 empilhados à direita.
    var layout: DockLayout = undefined;
    dockInit(&layout, 0);
    const right = try dockSplit(&layout, 0, .vertical, 0.5, 1);
    _ = try dockSplit(&layout, right, .horizontal, 0.5, 2);

    // `.center` em `dockMovePane` é recusado (só `dockApplyDrop` troca).
    try stdt.testing.expect(!dockMovePane(&layout, 2, 0, .center));
    // Sobre si mesmo / alvo inexistente / painel inexistente: sem efeito.
    try stdt.testing.expect(!dockMovePane(&layout, 2, 2, .left));
    try stdt.testing.expect(!dockMovePane(&layout, 2, 99, .left));
    try stdt.testing.expect(!dockMovePane(&layout, 99, 0, .left));
    try stdt.testing.expect(!dockSwapPanes(&layout, 2, 2));
    try stdt.testing.expect(!dockSwapPanes(&layout, 2, 99));
    try stdt.testing.expectEqual(@as(usize, 3), dockLeafCount(&layout));
    try stdt.testing.expectEqual(@as(usize, 5), dockNodeCount(&layout));

    // Move o painel 2 para a esquerda do painel 0: dissolve o split dele e
    // redivide o alvo, com o movido no lado inicial.
    try stdt.testing.expect(dockMovePane(&layout, 2, 0, .left));
    try stdt.testing.expectEqual(@as(usize, 3), dockLeafCount(&layout));
    var infos: [DockLayout.max_panes]DockPaneInfo = undefined;
    _ = try dockPanes(&layout, bounds, 0, &infos);
    try stdt.testing.expectEqual(@as(u16, 2), infos[0].pane());
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 100, 300), infos[0].rect);
    try stdt.testing.expectEqual(@as(u16, 0), infos[1].pane());
    try stdt.testing.expectEqual(types.Rect.init(100, 0, 100, 300), infos[1].rect);
    try stdt.testing.expectEqual(@as(u16, 1), infos[2].pane());
    try stdt.testing.expectEqual(types.Rect.init(200, 0, 200, 300), infos[2].rect);

    // Depois do movimento, o novo split tem ratio 0.5.
    var splits: [DockLayout.max_panes]DockSplitInfo = undefined;
    const ns = try dockSplits(&layout, bounds, 0, &splits);
    try stdt.testing.expectEqual(@as(usize, 2), ns);
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), splits[1].ratio, 0.0001);

    // Move para baixo do painel 1 (orientação horizontal, lado final).
    try stdt.testing.expect(dockMovePane(&layout, 2, 1, .bottom));
    _ = try dockPanes(&layout, bounds, 0, &infos);
    try stdt.testing.expectEqual(@as(u16, 0), infos[0].pane());
    try stdt.testing.expectEqual(@as(u16, 1), infos[1].pane());
    try stdt.testing.expectEqual(@as(u16, 2), infos[2].pane());

    // Centro ⇒ vira aba do grupo alvo: `dockApplyDrop` chama `dockMergeTab`
    // (remove o painel de origem e o anexa ativo ao grupo alvo).
    try stdt.testing.expect(dockApplyDrop(&layout, 0, 2, .center));
    try stdt.testing.expectEqual(@as(usize, 2), dockLeafCount(&layout));
    _ = try dockPanes(&layout, bounds, 0, &infos);
    try stdt.testing.expectEqual(@as(u16, 1), infos[0].pane());
    try stdt.testing.expectEqual(@as(u8, 1), infos[0].group.count);
    try stdt.testing.expectEqual(@as(u16, 2), infos[1].group.tabs()[0]);
    try stdt.testing.expectEqual(@as(u16, 0), infos[1].group.tabs()[1]);
    try stdt.testing.expectEqual(@as(u8, 2), infos[1].group.count);
    try stdt.testing.expectEqual(@as(u16, 0), infos[1].pane()); // 0 ficou ativo
    try stdt.testing.expectEqual(@as(u8, 1), infos[1].group.active);
    try stdt.testing.expect(!dockApplyDrop(&layout, 0, 0, .center)); // si mesmo
    try stdt.testing.expect(!dockApplyDrop(&layout, 2, 0, .center)); // mesmo grupo

    // Borda ⇒ redivide o grupo alvo (via `dockApplyDrop`); aqui o painel 2
    // sai do grupo (que fica com o 0) e ganha grupo próprio acima do 1.
    try stdt.testing.expect(dockApplyDrop(&layout, 2, 1, .top));
    try stdt.testing.expectEqual(@as(usize, 3), dockLeafCount(&layout));

    // Layout de um painel só: nada a mover.
    var single: DockLayout = undefined;
    dockInit(&single, 42);
    try stdt.testing.expect(!dockMovePane(&single, 42, 42, .left));
    try stdt.testing.expect(!dockSwapPanes(&single, 42, 43));

    // Capacidade esgotada (16 painéis): remover liberta nós ⇒ mover cabe.
    var full: DockLayout = undefined;
    dockInit(&full, 0);
    var next: u16 = 1;
    while (next < DockLayout.max_panes) : (next += 1) {
        _ = try dockSplit(&full, full.len - 1, .horizontal, 0.5, next);
    }
    try stdt.testing.expectEqual(DockLayout.max_panes, dockLeafCount(&full));
    const moved_pane: u16 = DockLayout.max_panes - 1;
    try stdt.testing.expect(dockMovePane(&full, moved_pane, 0, .top));
    try stdt.testing.expectEqual(DockLayout.max_panes, dockLeafCount(&full));
    try stdt.testing.expect(full.len <= DockLayout.max_nodes);
}

test "dock: abas acopladas (grupo, ativo, add/remove/merge)" {
    const stdt = @import("std");
    const bounds = types.Rect.init(0, 0, 400, 300);

    var layout: DockLayout = undefined;
    dockInit(&layout, 0);
    try stdt.testing.expectEqual(@as(u8, 1), dockGroup(&layout, 0).?.count);
    try stdt.testing.expectEqual(@as(u16, 0), dockGroup(&layout, 0).?.activePane());
    try stdt.testing.expectEqualSlices(u16, &.{0}, dockGroup(&layout, 0).?.tabs());
    try stdt.testing.expectEqual(@as(?DockGroup, null), dockGroup(&layout, 9));

    // Anexa abas (a última vira ativa); duplicata e grupo cheio são
    // recusados (`max_tabs`).
    try stdt.testing.expect(dockAddTab(&layout, 0, 1));
    try stdt.testing.expect(dockAddTab(&layout, 0, 2));
    try stdt.testing.expectEqual(@as(u16, 2), dockNodePane(&layout, 0).?);
    try stdt.testing.expect(!dockAddTab(&layout, 0, 2));
    try stdt.testing.expect(dockAddTab(&layout, 0, 3));
    try stdt.testing.expect(dockGroup(&layout, 0).?.isFull());
    try stdt.testing.expect(!dockAddTab(&layout, 0, 4));
    try stdt.testing.expectEqual(@as(u8, 4), dockGroup(&layout, 0).?.count);

    // Um grupo só: uma folha, `dockPanes` reporta as 4 abas em ordem.
    var infos: [DockLayout.max_panes]DockPaneInfo = undefined;
    try stdt.testing.expectEqual(@as(usize, 1), try dockPanes(&layout, bounds, 0, &infos));
    try stdt.testing.expectEqual(@as(u8, 4), infos[0].group.count);
    try stdt.testing.expectEqualSlices(u16, &.{ 0, 1, 2, 3 }, infos[0].group.tabs());
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&layout));

    // `dockFindPane` acha qualquer aba; remover uma aba do meio ajusta o
    // índice ativo e não mexe na árvore.
    try stdt.testing.expectEqual(@as(?usize, 0), dockFindPane(&layout, 3));
    try stdt.testing.expect(dockRemoveTab(&layout, 0, 1));
    try stdt.testing.expectEqualSlices(u16, &.{ 0, 2, 3 }, dockGroup(&layout, 0).?.tabs());
    try stdt.testing.expectEqual(@as(u16, 3), dockGroup(&layout, 0).?.activePane());
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&layout));
    try stdt.testing.expect(!dockRemoveTab(&layout, 0, 99));

    // Aba ativa: foras da faixa são recusados; válida muda o painel ativo.
    try stdt.testing.expect(!dockSetActiveTab(&layout, 0, 9));
    try stdt.testing.expect(!dockSetActiveTab(&layout, 7, 0));
    try stdt.testing.expect(dockSetActiveTab(&layout, 0, 0));
    try stdt.testing.expectEqual(@as(u16, 0), dockNodePane(&layout, 0).?);

    // Grupo novo ao lado: a folha original (3 abas) fica num lado e o novo
    // painel no outro.
    const other = try dockSplit(&layout, 0, .vertical, 0.5, 9);
    try stdt.testing.expectEqual(@as(usize, 2), dockLeafCount(&layout));
    const g0 = dockFindPane(&layout, 0).?;
    try stdt.testing.expectEqual(@as(u8, 3), dockGroup(&layout, g0).?.count);
    try stdt.testing.expectEqual(@as(u8, 1), dockGroup(&layout, other).?.count);

    // Merge (centro): a aba 2 sai do grupo de 0 e vira aba ativa do 9.
    try stdt.testing.expect(dockMergeTab(&layout, 2, 9));
    try stdt.testing.expectEqualSlices(u16, &.{ 0, 3 }, dockGroup(&layout, dockFindPane(&layout, 0).?).?.tabs());
    try stdt.testing.expectEqualSlices(u16, &.{ 9, 2 }, dockGroup(&layout, dockFindPane(&layout, 9).?).?.tabs());
    try stdt.testing.expectEqual(@as(u16, 2), dockNodePane(&layout, dockFindPane(&layout, 9).?).?);

    // Mesmo grupo e painel inexistente são recusados.
    try stdt.testing.expect(!dockMergeTab(&layout, 2, 9));
    try stdt.testing.expect(!dockMergeTab(&layout, 99, 9));

    // Merge que esvazia o grupo de origem dissolve a folha.
    try stdt.testing.expect(dockMergeTab(&layout, 0, 9));
    try stdt.testing.expect(dockMergeTab(&layout, 3, 9));
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&layout));
    try stdt.testing.expectEqualSlices(u16, &.{ 9, 2, 0, 3 }, dockGroup(&layout, 0).?.tabs());
    try stdt.testing.expect(!dockAddTab(&layout, 0, 5)); // cheio

    // Alvo cheio ⇒ merge recusado sem efeito (nada é removido da origem).
    var full2: DockLayout = undefined;
    dockInit(&full2, 0);
    _ = try dockSplit(&full2, 0, .vertical, 0.5, 1);
    const f0 = dockFindPane(&full2, 0).?;
    const f1 = dockFindPane(&full2, 1).?;
    _ = dockAddTab(&full2, f0, 2);
    _ = dockAddTab(&full2, f0, 3);
    _ = dockAddTab(&full2, f0, 4);
    try stdt.testing.expect(dockGroup(&full2, f0).?.isFull());
    try stdt.testing.expect(!dockMergeTab(&full2, 1, 0));
    try stdt.testing.expectEqual(@as(usize, 2), dockLeafCount(&full2));
    try stdt.testing.expectEqualSlices(u16, &.{ 0, 2, 3, 4 }, dockGroup(&full2, f0).?.tabs());
    try stdt.testing.expectEqualSlices(u16, &.{1}, dockGroup(&full2, f1).?.tabs());

    // Trocar painéis entre grupos preserva a estrutura; no mesmo grupo é
    // recusado (lá o que muda é a aba ativa).
    var sw: DockLayout = undefined;
    dockInit(&sw, 0);
    _ = try dockSplit(&sw, 0, .vertical, 0.5, 1);
    _ = dockAddTab(&sw, dockFindPane(&sw, 0).?, 2);
    try stdt.testing.expect(dockSwapPanes(&sw, 0, 1));
    try stdt.testing.expectEqualSlices(u16, &.{ 1, 2 }, dockGroup(&sw, dockFindPane(&sw, 1).?).?.tabs());
    try stdt.testing.expectEqualSlices(u16, &.{0}, dockGroup(&sw, dockFindPane(&sw, 0).?).?.tabs());
    try stdt.testing.expect(!dockSwapPanes(&sw, 1, 2));
    try stdt.testing.expectEqual(@as(usize, 2), dockLeafCount(&sw));

    // Última aba de um layout de um grupo só: recusado (não deixa vazio).
    var one: DockLayout = undefined;
    dockInit(&one, 7);
    try stdt.testing.expect(!dockRemovePane(&one, 7));
    try stdt.testing.expect(!dockRemoveTab(&one, 0, 7));
    try stdt.testing.expectEqual(@as(usize, 1), dockLeafCount(&one));
}
