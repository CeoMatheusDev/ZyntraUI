//! ZyntraUI — serialização do layout de docking (dock/serialize).
//!
//! Modelo M79 (Docking, passo 4c): converte um `DockLayout` num blob binário
//! **versionado** e de volta, para persistência (salvar/restaurar o arranjo
//! de painéis entre execuções). Puro, sem alocação: o chamador fornece o
//! buffer de saída (`dockSerialize`) ou os bytes de entrada
//! (`dockDeserialize`).
//!
//! Formato v1 (little-endian, sem padding):
//!
//! ```text
//! cabeçalho (8 B): "ZDKL" | versão u16 | len u8 | root u8
//! nó folha:  tag 0 | count u8 | active u8 | panes: count × u16
//! nó split:  tag 1 | orientação u8 (0=h, 1=v) | ratio f32 | first u8 | second u8
//! ```
//!
//! `len` é o número de nós (1..`DockLayout.max_nodes`) e `root` o índice da
//! raiz (`< len`). Os nós vêm em ordem de índice (0..len), com folhas e
//! splits misturados — a posição é a do array do layout.
//!
//! Regras de leitura (`dockDeserialize` valida entrada não confiável e é
//! tudo-ou-nada: em erro, `out` fica intacto):
//! - magic/versão: magic errado ⇒ `InvalidFormat`; versão diferente ⇒
//!   `UnsupportedVersion` (use `dockSerialVersion` para ler antes).
//! - `len`/`root` fora da faixa ⇒ `InvalidFormat`.
//! - folha: `count` em `1..DockGroup.max_tabs`, `active < count`, sem abas
//!   repetidas no mesmo grupo.
//! - split: orientação conhecida, `ratio` finito em `[0,1]`, filhos `< len`.
//! - árvore: todos os nós em `0..len` alcançáveis a partir de `root`
//!   exatamente uma vez (rejeita ciclos, filhos compartilhados e órfãos).
//!
//! `dockSerialize` assume um layout válido (não valida); o formato é
//! canônico (round-trip re-serializa byte a byte).

const std = @import("std");
const layout_mod = @import("layout.zig");

const DockLayout = layout_mod.DockLayout;
const DockGroup = layout_mod.DockGroup;
const DockOrientation = layout_mod.DockOrientation;

/// Erros da serialização. `OutOfBuffer` só vem de `dockSerialize` (buffer de
/// saída pequeno); `InvalidFormat`/`UnsupportedVersion` só de
/// `dockDeserialize`/`dockSerialVersion`.
pub const Error = error{ OutOfBuffer, InvalidFormat, UnsupportedVersion };

/// Versão do formato escrita por `dockSerialize` e aceita por
/// `dockDeserialize`.
pub const version: u16 = 1;

/// Tamanho máximo de um blob (cabeçalho + `max_nodes` folhas cheias).
pub const max_size: usize =
    header_size + DockLayout.max_nodes * (leaf_fixed + DockGroup.max_tabs * 2);

const magic = [4]u8{ 'Z', 'D', 'K', 'L' };
/// magic (4) + versão (2) + len (1) + root (1).
const header_size: usize = 8;
/// tag (1) + count (1) + active (1).
const leaf_fixed: usize = 3;
/// tag (1) + orientação (1) + ratio (4) + first (1) + second (1).
const split_size: usize = 8;
/// Corpo do split após o tag (sem o byte do tag).
const split_body: usize = split_size - 1;

const tag_leaf: u8 = 0;
const tag_split: u8 = 1;

/// Tamanho exato do blob de `layout` (cabeçalho + nós). Usa os `count` reais
/// das folhas — um layout inválido (len fora da faixa) é clampado.
pub fn dockSerializedSize(layout: *const DockLayout) usize {
    var n: usize = header_size;
    for (layout.nodes[0..@min(layout.len, DockLayout.max_nodes)]) |node| {
        n += switch (node) {
            .leaf => |g| leaf_fixed + @as(usize, g.count) * 2,
            .split => split_size,
        };
    }
    return n;
}

/// Lê a versão do cabeçalho sem interpretar o corpo — para decidir migrações
/// antes de `dockDeserialize`. `InvalidFormat` se magic/cabeçalho inválidos.
pub fn dockSerialVersion(bytes: []const u8) Error!u16 {
    if (bytes.len < header_size) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[0..magic.len], &magic)) return error.InvalidFormat;
    return std.mem.readInt(u16, bytes[4..][0..2], .little);
}

/// Serializa `layout` em `out` e devolve o número de bytes escritos. Requer
/// `out.len >= dockSerializedSize(layout)` (`OutOfBuffer` caso contrário) e
/// um layout válido (`InvalidFormat` se `len` for 0 ou passar de `max_nodes`).
pub fn dockSerialize(layout: *const DockLayout, out: []u8) Error!usize {
    if (layout.len == 0 or layout.len > DockLayout.max_nodes) return error.InvalidFormat;
    if (out.len < dockSerializedSize(layout)) return error.OutOfBuffer;

    var at: usize = 0;
    @memcpy(out[0..magic.len], &magic);
    at = magic.len;
    std.mem.writeInt(u16, out[at..][0..2], version, .little);
    at += 2;
    out[at] = @intCast(layout.len);
    at += 1;
    out[at] = layout.root;
    at += 1;

    for (layout.nodes[0..layout.len]) |node| {
        switch (node) {
            .leaf => |g| {
                out[at] = tag_leaf;
                at += 1;
                out[at] = g.count;
                at += 1;
                out[at] = g.active;
                at += 1;
                for (g.tabs()) |pane| {
                    std.mem.writeInt(u16, out[at..][0..2], pane, .little);
                    at += 2;
                }
            },
            .split => |s| {
                out[at] = tag_split;
                at += 1;
                out[at] = @backingInt(s.orientation);
                at += 1;
                std.mem.writeInt(u32, out[at..][0..4], @bitCast(s.ratio), .little);
                at += 4;
                out[at] = s.first;
                at += 1;
                out[at] = s.second;
                at += 1;
            },
        }
    }
    return at;
}

/// Lê um blob de `bytes` para `out` e devolve os bytes consumidos. Tudo ou
/// nada: em erro `out` não é tocado (a leitura vai para um temporário).
/// Ver as regras de validação no cabeçalho do arquivo.
pub fn dockDeserialize(out: *DockLayout, bytes: []const u8) Error!usize {
    var tmp: DockLayout = undefined;
    const used = try readInto(&tmp, bytes);
    out.* = tmp;
    return used;
}

fn readInto(layout: *DockLayout, bytes: []const u8) Error!usize {
    if (bytes.len < header_size) return error.InvalidFormat;
    if (!std.mem.eql(u8, bytes[0..magic.len], &magic)) return error.InvalidFormat;
    const v = std.mem.readInt(u16, bytes[4..][0..2], .little);
    if (v != version) return error.UnsupportedVersion;

    const len: usize = bytes[6];
    const root: u8 = bytes[7];
    if (len == 0 or len > DockLayout.max_nodes) return error.InvalidFormat;
    if (root >= len) return error.InvalidFormat;

    var at: usize = header_size;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (at >= bytes.len) return error.InvalidFormat;
        const tag = bytes[at];
        at += 1;
        switch (tag) {
            tag_leaf => {
                try need(bytes, at, 2);
                const count: usize = bytes[at];
                const active = bytes[at + 1];
                at += 2;
                if (count == 0 or count > DockGroup.max_tabs) return error.InvalidFormat;
                if (active >= count) return error.InvalidFormat;
                var g = DockGroup{};
                var k: usize = 0;
                while (k < count) : (k += 1) {
                    try need(bytes, at, 2);
                    g.panes[k] = std.mem.readInt(u16, bytes[at..][0..2], .little);
                    at += 2;
                }
                g.count = @intCast(count);
                g.active = active;
                // Abas repetidas no mesmo grupo violam o invariante.
                k = 0;
                while (k < count) : (k += 1) {
                    var j = k + 1;
                    while (j < count) : (j += 1) {
                        if (g.panes[k] == g.panes[j]) return error.InvalidFormat;
                    }
                }
                layout.nodes[i] = .{ .leaf = g };
            },
            tag_split => {
                try need(bytes, at, split_body);
                const orientation = std.enums.fromInt(DockOrientation, bytes[at]) orelse
                    return error.InvalidFormat;
                at += 1;
                const ratio: f32 = @bitCast(std.mem.readInt(u32, bytes[at..][0..4], .little));
                at += 4;
                if (!std.math.isFinite(ratio) or ratio < 0 or ratio > 1) return error.InvalidFormat;
                const first = bytes[at];
                const second = bytes[at + 1];
                at += 2;
                if (first >= len or second >= len) return error.InvalidFormat;
                layout.nodes[i] = .{ .split = .{
                    .orientation = orientation,
                    .ratio = ratio,
                    .first = first,
                    .second = second,
                } };
            },
            else => return error.InvalidFormat,
        }
    }

    layout.len = len;
    layout.root = root;
    if (!isValidTree(layout)) return error.InvalidFormat;
    return at;
}

fn need(bytes: []const u8, at: usize, n: usize) Error!void {
    if (at + n > bytes.len) return error.InvalidFormat;
}

/// `true` se todo nó em `0..len` é alcançável de `root` exatamente uma vez
/// (rejeita ciclos, filhos compartilhados, auto-referência e órfãos).
fn isValidTree(layout: *const DockLayout) bool {
    if (layout.len == 0 or layout.len > DockLayout.max_nodes) return false;
    if (layout.root >= layout.len) return false;
    var visited: [DockLayout.max_nodes]bool = undefined;
    @memset(&visited, false);
    var seen: usize = 0;
    if (!walk(layout, layout.root, &visited, &seen)) return false;
    return seen == layout.len;
}

fn walk(layout: *const DockLayout, node: u8, visited: *[DockLayout.max_nodes]bool, seen: *usize) bool {
    if (node >= layout.len or visited[node]) return false;
    visited[node] = true;
    seen.* += 1;
    switch (layout.nodes[node]) {
        .leaf => {},
        .split => |s| {
            if (s.first >= layout.len or s.second >= layout.len) return false;
            if (!walk(layout, s.first, visited, seen)) return false;
            if (!walk(layout, s.second, visited, seen)) return false;
        },
    }
    return true;
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

const stdt = std.testing;
const types = @import("../core/types.zig");

/// Layout de exemplo com grupos, abas e splits aninhados.
fn sampleLayout() !DockLayout {
    var layout: DockLayout = undefined;
    layout_mod.dockInit(&layout, 0);
    const right = try layout_mod.dockSplit(&layout, 0, .vertical, 0.5, 1);
    _ = try layout_mod.dockSplit(&layout, right, .horizontal, 0.25, 2);
    const g0 = layout_mod.dockFindPane(&layout, 0).?;
    _ = layout_mod.dockAddTab(&layout, g0, 3);
    _ = layout_mod.dockAddTab(&layout, g0, 4);
    _ = layout_mod.dockSetActiveTab(&layout, g0, 1);
    return layout;
}

/// Compara dois layouts campo a campo (por nó), ignorando os bytes não
/// usados de `DockGroup.panes`.
fn expectSameLayout(a: *const DockLayout, b: *const DockLayout) !void {
    try stdt.expectEqual(a.len, b.len);
    try stdt.expectEqual(a.root, b.root);
    for (a.nodes[0..a.len], b.nodes[0..b.len]) |na, nb| {
        switch (na) {
            .leaf => |ga| {
                const gb = switch (nb) {
                    .leaf => |g| g,
                    .split => return error.TestExpectedEqual,
                };
                try stdt.expectEqual(ga.count, gb.count);
                try stdt.expectEqual(ga.active, gb.active);
                try stdt.expectEqualSlices(u16, ga.tabs(), gb.tabs());
            },
            .split => |sa| {
                const sb = switch (nb) {
                    .split => |s| s,
                    .leaf => return error.TestExpectedEqual,
                };
                try stdt.expectEqual(sa.orientation, sb.orientation);
                try stdt.expectEqual(sa.first, sb.first);
                try stdt.expectEqual(sa.second, sb.second);
                try stdt.expectEqual(sa.ratio, sb.ratio);
            },
        }
    }
}

test "dock serial: round-trip preserva estrutura, abas e ratio" {
    const layout = try sampleLayout();
    var buf: [max_size]u8 = undefined;
    const n = try dockSerialize(&layout, &buf);
    try stdt.expectEqual(dockSerializedSize(&layout), n);
    try stdt.expect(n <= max_size);
    try stdt.expectEqual(version, try dockSerialVersion(&buf));

    var back: DockLayout = undefined;
    try stdt.expectEqual(n, try dockDeserialize(&back, buf[0..n]));
    try expectSameLayout(&layout, &back);

    // Canônico: re-serializar dá byte a byte o mesmo blob.
    var again: [max_size]u8 = undefined;
    try stdt.expectEqual(n, try dockSerialize(&back, &again));
    try stdt.expectEqualSlices(u8, buf[0..n], again[0..n]);
}

test "dock serial: geometria e abas equivalentes após o round-trip" {
    const bounds = types.Rect.init(0, 0, 400, 300);
    const layout = try sampleLayout();
    var buf: [max_size]u8 = undefined;
    const n = try dockSerialize(&layout, &buf);
    var back: DockLayout = undefined;
    _ = try dockDeserialize(&back, buf[0..n]);

    try stdt.expectEqual(layout_mod.dockLeafCount(&layout), layout_mod.dockLeafCount(&back));
    try stdt.expectEqual(layout_mod.dockNodeCount(&layout), layout_mod.dockNodeCount(&back));

    var a: [DockLayout.max_panes]layout_mod.DockPaneInfo = undefined;
    var b: [DockLayout.max_panes]layout_mod.DockPaneInfo = undefined;
    const na = try layout_mod.dockPanes(&layout, bounds, 6, &a);
    const nb = try layout_mod.dockPanes(&back, bounds, 6, &b);
    try stdt.expectEqual(na, nb);
    for (a[0..na], b[0..nb]) |ia, ib| {
        try stdt.expectEqual(ia.node, ib.node);
        try stdt.expectEqual(ia.pane(), ib.pane());
        try stdt.expectEqual(ia.rect, ib.rect);
        try stdt.expectEqualSlices(u16, ia.group.tabs(), ib.group.tabs());
    }
    var sa: [DockLayout.max_panes]layout_mod.DockSplitInfo = undefined;
    var sb: [DockLayout.max_panes]layout_mod.DockSplitInfo = undefined;
    const na2 = try layout_mod.dockSplits(&layout, bounds, 6, &sa);
    const nb2 = try layout_mod.dockSplits(&back, bounds, 6, &sb);
    try stdt.expectEqual(na2, nb2);
    for (sa[0..na2], sb[0..nb2]) |x, y| {
        try stdt.expectEqual(x.node, y.node);
        try stdt.expectEqual(x.orientation, y.orientation);
        try stdt.expectEqual(x.ratio, y.ratio);
        try stdt.expectEqual(x.divider, y.divider);
    }
}

test "dock serial: layout cheio (16 grupos com abas) cabe em max_size" {
    var layout: DockLayout = undefined;
    layout_mod.dockInit(&layout, 0);
    var next: u16 = 1;
    // 8 grupos de 2 painéis (16 painéis) via splits + abas.
    while (next < 8) : (next += 1) {
        _ = try layout_mod.dockSplit(&layout, layout.len - 1, .horizontal, 0.5, next);
    }
    try stdt.expectEqual(@as(usize, 8), layout_mod.dockLeafCount(&layout));
    var extra: u16 = 8;
    var i: usize = 0;
    while (i < layout.len and extra < 16) : (i += 1) {
        if (layout_mod.dockGroupMut(&layout, i)) |g| {
            if (g.count == 1) {
                _ = layout_mod.dockAddTab(&layout, i, extra);
                extra += 1;
            }
        }
    }
    try stdt.expectEqual(@as(u16, 16), extra);

    var buf: [max_size]u8 = undefined;
    const n = try dockSerialize(&layout, &buf);
    try stdt.expect(dockSerializedSize(&layout) <= max_size);
    var back: DockLayout = undefined;
    _ = try dockDeserialize(&back, buf[0..n]);
    try expectSameLayout(&layout, &back);
}

test "dock serial: buffer pequeno ⇒ OutOfBuffer sem tocar o destino" {
    const layout = try sampleLayout();
    const need_bytes = dockSerializedSize(&layout);
    var small: [header_size + 2]u8 = undefined;
    try stdt.expectError(error.OutOfBuffer, dockSerialize(&layout, &small));
    try stdt.expect(need_bytes > small.len);

    // Um buffer exato funciona.
    var exact: [max_size]u8 = undefined;
    try stdt.expectEqual(need_bytes, try dockSerialize(&layout, exact[0..need_bytes]));
}

test "dock serial: erros de formato, versão e estado intacto" {
    const layout = try sampleLayout();
    var buf: [max_size]u8 = undefined;
    const n = try dockSerialize(&layout, &buf);
    const blob = buf[0..n];

    // Versão e magic.
    var vbad: [max_size]u8 = undefined;
    @memcpy(vbad[0..n], blob);
    std.mem.writeInt(u16, vbad[4..][0..2], 2, .little);
    var out: DockLayout = undefined;
    try stdt.expectError(error.UnsupportedVersion, dockDeserialize(&out, vbad[0..n]));
    try stdt.expectEqual(@as(u16, 2), try dockSerialVersion(vbad[0..n]));

    var mbad: [max_size]u8 = undefined;
    @memcpy(mbad[0..n], blob);
    mbad[0] = 'X';
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, mbad[0..n]));
    try stdt.expectError(error.InvalidFormat, dockSerialVersion(mbad[0..n]));

    // Curto/truncado.
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, blob[0..3]));
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, blob[0 .. n - 1]));
    try stdt.expectError(error.InvalidFormat, dockSerialVersion(blob[0..4]));

    // len/root fora da faixa e tag desconhecido.
    var bad: [max_size]u8 = undefined;
    @memcpy(bad[0..n], blob);
    bad[6] = 0; // len 0
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));
    @memcpy(bad[0..n], blob);
    bad[6] = DockLayout.max_nodes + 1; // len grande
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));
    @memcpy(bad[0..n], blob);
    bad[7] = bad[6]; // root == len ⇒ fora
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));
    @memcpy(bad[0..n], blob);
    bad[header_size] = 9; // tag inválido no nó 0
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));

    // Tudo-ou-nada: uma leitura inválida não altera o destino.
    var keep = try sampleLayout();
    const snapshot = keep;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&keep, bad[0..n]));
    try expectSameLayout(&snapshot, &keep);
    try stdt.expectEqual(version, try dockSerialVersion(blob));
}

test "dock serial: valida invariantes da folha e do split" {
    var layout: DockLayout = undefined;
    layout_mod.dockInit(&layout, 7);
    var buf: [max_size]u8 = undefined;
    const n = try dockSerialize(&layout, &buf);
    try stdt.expectEqual(@as(usize, header_size + leaf_fixed + 2), n);
    try stdt.expectEqual(@as(u8, tag_leaf), buf[header_size]);
    try stdt.expectEqual(@as(u8, 1), buf[header_size + 1]);
    try stdt.expectEqual(@as(u8, 0), buf[header_size + 2]);

    var out: DockLayout = undefined;
    var bad: [max_size]u8 = undefined;

    // count 0 / acima do teto.
    @memcpy(bad[0..n], buf[0..n]);
    bad[header_size + 1] = 0;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));
    @memcpy(bad[0..n], buf[0..n]);
    bad[header_size + 1] = DockGroup.max_tabs + 1;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));

    // active fora da faixa.
    @memcpy(bad[0..n], buf[0..n]);
    bad[header_size + 2] = 1;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, bad[0..n]));

    // Abas repetidas no grupo: layout de 2 painéis iguais não passa pelo
    // `dockAddTab`, então monta o blob à mão (count 2, panes {7,7}).
    var dup: [max_size]u8 = undefined;
    @memcpy(dup[0 .. header_size + leaf_fixed], buf[0 .. header_size + leaf_fixed]);
    dup[6] = 1;
    dup[header_size + 1] = 2;
    dup[header_size + 3] = 7;
    dup[header_size + 4] = 0;
    dup[header_size + 5] = 7;
    dup[header_size + 6] = 0;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, dup[0 .. header_size + leaf_fixed + 4]));
}

test "dock serial: valida a árvore (ciclo, filho compartilhado, órfão)" {
    // Blob válido de 3 nós: split(no 0) com filhos 1 e 2 (folhas 5 e 6).
    var ok: [header_size + split_size + 2 * (leaf_fixed + 2)]u8 = undefined;
    @memcpy(ok[0..4], "ZDKL");
    std.mem.writeInt(u16, ok[4..][0..2], version, .little);
    ok[6] = 3;
    ok[7] = 0;
    const n0 = header_size;
    const n1 = n0 + split_size;
    const n2 = n1 + leaf_fixed + 2;
    ok[n0] = tag_split;
    ok[n0 + 1] = 0; // horizontal
    std.mem.writeInt(u32, ok[n0 + 2 ..][0..4], @bitCast(@as(f32, 0.5)), .little);
    ok[n0 + 6] = 1;
    ok[n0 + 7] = 2;
    ok[n1] = tag_leaf;
    ok[n1 + 1] = 1;
    ok[n1 + 2] = 0;
    ok[n1 + 3] = 5;
    ok[n1 + 4] = 0;
    ok[n2] = tag_leaf;
    ok[n2 + 1] = 1;
    ok[n2 + 2] = 0;
    ok[n2 + 3] = 6;
    ok[n2 + 4] = 0;

    var out: DockLayout = undefined;
    try stdt.expectEqual(ok.len, try dockDeserialize(&out, &ok));
    try stdt.expectEqual(@as(usize, 3), layout_mod.dockNodeCount(&out));
    try stdt.expectEqual(@as(usize, 2), layout_mod.dockLeafCount(&out));
    try stdt.expectEqual(@as(?f32, 0.5), layout_mod.dockSplitRatio(&out, 0));

    // Ciclo: o split aponta para si mesmo.
    var cyc = ok;
    cyc[n0 + 6] = 0;
    cyc[n0 + 7] = 0;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, &cyc));

    // Filho compartilhado: os dois filhos são o nó 1.
    var shared = ok;
    shared[n0 + 7] = 1;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, &shared));

    // Órfãos: root é a folha 1, então os nós 0 e 2 ficam inalcançáveis.
    var orf = ok;
    orf[7] = 1;
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, &orf));
}

test "dock serial: ratio não finito/fora de [0,1] é rejeitado" {
    var layout: DockLayout = undefined;
    layout_mod.dockInit(&layout, 0);
    _ = try layout_mod.dockSplit(&layout, 0, .vertical, 0.5, 1);
    var buf: [max_size]u8 = undefined;
    const n = try dockSerialize(&layout, &buf);
    // Localiza o split (nó 0) e corrompe o ratio.
    try stdt.expectEqual(@as(u8, tag_split), buf[header_size]);
    var out: DockLayout = undefined;
    const ratio_at = header_size + 2;
    std.mem.writeInt(u32, buf[ratio_at..][0..4], @bitCast(std.math.inf(f32)), .little);
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, buf[0..n]));
    std.mem.writeInt(u32, buf[ratio_at..][0..4], @bitCast(@as(f32, 1.5)), .little);
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, buf[0..n]));
    std.mem.writeInt(u32, buf[ratio_at..][0..4], @bitCast(@as(f32, -0.5)), .little);
    try stdt.expectError(error.InvalidFormat, dockDeserialize(&out, buf[0..n]));
}

test "dock serial: lista vazia é inválida na escrita" {
    var zero: DockLayout = undefined;
    zero.len = 0;
    zero.root = 0;
    var buf: [max_size]u8 = undefined;
    try stdt.expectError(error.InvalidFormat, dockSerialize(&zero, &buf));
}

test "fuzz dock serial: lixo nunca vira layout inválido" {
    try std.testing.fuzz({}, fuzzDockDeserialize, .{});
}

fn fuzzDockDeserialize(_: void, smith: *std.testing.Smith) !void {
    var buf: [max_size + 16]u8 = undefined;
    smith.bytes(&buf);
    var layout: DockLayout = undefined;
    if (dockDeserialize(&layout, &buf)) |used| {
        try stdt.expect(used <= buf.len);
        try stdt.expect(layout.len >= 1 and layout.len <= DockLayout.max_nodes);
        try stdt.expect(layout.root < layout.len);
        try stdt.expect(isValidTree(&layout));
        // Canônico e estável: re-serializar dá o mesmo blob (prefixo).
        var again: [max_size]u8 = undefined;
        const m = try dockSerialize(&layout, &again);
        try stdt.expectEqual(used, m);
        try stdt.expectEqualSlices(u8, buf[0..used], again[0..m]);
    } else |_| {}
}
