//! ZyntraUI — modelo puro de grafo de nós (graph/view).
//!
//! Sem `Context` e sem alocação: transformação mundo↔tela, geometria de
//! nós/pinos, curva das arestas e hit-test. O widget
//! `widgets/graph_view` consome este módulo; desenho e interação ficam
//! lá.
//!
//! Convenções:
//! - `Transform`: `tela = mundo * zoom + pan` (`zoom > 0`).
//! - Pinos: entrada na borda esquerda, saída na direita, distribuídos
//!   uniformemente na altura do nó (`y = pos.y + (i+1) * h / (n+1)`).
//! - Arestas: Bézier cúbica com controles horizontais simétricos.
//! - `hitNode`: iteração reversa (o último desenhado fica no topo).
//! - Índices fora de faixa são sempre tratados como ausentes (nunca
//!   crasham).

const std = @import("std");
const types = @import("../core/types.zig");

pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;

/// Transformação afim mundo↔tela (pan + zoom uniforme).
pub const Transform = struct {
    /// Deslocamento em px de tela (aplicado depois do zoom).
    pan: Vec2 = .{ .x = 0, .y = 0 },
    /// Fator de escala uniforme (> 0).
    zoom: f32 = 1.0,

    pub fn isValid(self: Transform) bool {
        return std.math.isFinite(self.pan.x) and std.math.isFinite(self.pan.y) and
            std.math.isFinite(self.zoom) and self.zoom > 0;
    }

    pub fn worldToScreen(self: Transform, p: Vec2) Vec2 {
        return .{ .x = p.x * self.zoom + self.pan.x, .y = p.y * self.zoom + self.pan.y };
    }

    pub fn screenToWorld(self: Transform, p: Vec2) Vec2 {
        return .{ .x = (p.x - self.pan.x) / self.zoom, .y = (p.y - self.pan.y) / self.zoom };
    }

    /// Escala o zoom por `factor` mantendo `anchor` (tela) fixo, com
    /// clamp em `[lo, hi]` (bordas ordenadas antes). Devolve `self` se
    /// algo for inválido (`lo`/`hi` não-finitos, `factor <= 0`, zoom
    /// resultante fora de `(0, inf)`).
    pub fn zoomAt(self: Transform, anchor: Vec2, factor: f32, lo: f32, hi: f32) Transform {
        if (!self.isValid()) return self;
        if (!std.math.isFinite(factor) or factor <= 0) return self;
        if (!std.math.isFinite(lo) or !std.math.isFinite(hi)) return self;
        const z = std.math.clamp(self.zoom * factor, @min(lo, hi), @max(lo, hi));
        if (!std.math.isFinite(z) or z <= 0) return self;
        const w = self.screenToWorld(anchor);
        return .{
            .pan = .{ .x = anchor.x - w.x * z, .y = anchor.y - w.y * z },
            .zoom = z,
        };
    }
};

/// Lado do nó onde fica o pino.
pub const PortSide = enum { input, output };

/// Nó do grafo (geometria em espaço-mundo).
pub const GraphNode = struct {
    /// Canto superior-esquerdo (mundo).
    pos: Vec2 = .{ .x = 0, .y = 0 },
    /// Tamanho (mundo); `w`/`h` devem ser > 0.
    size: Vec2 = .{ .x = 120, .y = 48 },
    /// Rótulo do título (emprestado só durante a chamada; vazio ⇒ sem
    /// texto).
    title: []const u8 = "",
    /// Nº de pinos à esquerda (entradas) e à direita (saídas).
    inputs: u32 = 0,
    outputs: u32 = 0,

    pub fn isValid(self: GraphNode) bool {
        return std.math.isFinite(self.pos.x) and std.math.isFinite(self.pos.y) and
            std.math.isFinite(self.size.x) and std.math.isFinite(self.size.y) and
            self.size.x > 0 and self.size.y > 0;
    }

    pub fn rect(self: GraphNode) Rect {
        return .{ .x = self.pos.x, .y = self.pos.y, .w = self.size.x, .h = self.size.y };
    }

    fn portCount(self: GraphNode, side: PortSide) u32 {
        return if (side == .input) self.inputs else self.outputs;
    }
};

/// Aresta dirigida `from`→`to` entre nós (índices em `[]GraphNode`).
pub const GraphEdge = struct {
    from: u32 = 0,
    to: u32 = 0,
    /// Pino de saída em `from` e de entrada em `to` (clampados ao total).
    from_port: u32 = 0,
    to_port: u32 = 0,
};

/// Centro do pino `index` no lado `side` de `n` (mundo).
/// Entradas na borda esquerda, saídas na direita; distribuição uniforme
/// (`y = pos.y + (i+1) * h / (count+1)`). `count == 0` ⇒ centro vertical
/// da borda, mesmo que `index` seja pedido; `index >= count` clampa no
/// último pino.
pub fn portPos(n: GraphNode, side: PortSide, index: u32) Vec2 {
    const count = n.portCount(side);
    const x = if (side == .input) n.pos.x else n.pos.x + n.size.x;
    if (count == 0) return .{ .x = x, .y = n.pos.y + n.size.y / 2 };
    const i: f32 = @floatFromInt(@min(index, count - 1));
    const c: f32 = @floatFromInt(count);
    return .{ .x = x, .y = n.pos.y + (i + 1) * n.size.y / (c + 1) };
}

/// Extremos (mundo) de `e` no sentido do desenho: saída de `from` →
/// entrada de `to`. `null` se algum índice estiver fora de faixa.
pub fn edgeAnchors(nodes: []const GraphNode, e: GraphEdge) ?[2]Vec2 {
    if (e.from >= nodes.len or e.to >= nodes.len) return null;
    return .{
        portPos(nodes[e.from], .output, e.from_port),
        portPos(nodes[e.to], .input, e.to_port),
    };
}

/// Controles da Bézier cúbica de `a` para `b`: deslocamento horizontal
/// `max(24, |dx| / 2)`, simétrico nos dois extremos (curva "S").
pub fn bezierControls(a: Vec2, b: Vec2) [2]Vec2 {
    const d = @max(24.0, @abs(b.x - a.x) * 0.5);
    return .{
        .{ .x = a.x + d, .y = a.y },
        .{ .x = b.x - d, .y = b.y },
    };
}

/// Ponto da Bézier cúbica em `t` (0..1), forma de Bernstein.
pub fn bezierPoint(a: Vec2, c1: Vec2, c2: Vec2, b: Vec2, t: f32) Vec2 {
    const u = 1 - t;
    const w0 = u * u * u;
    const w1 = 3 * u * u * t;
    const w2 = 3 * u * t * t;
    const w3 = t * t * t;
    return .{
        .x = w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x,
        .y = w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y,
    };
}

/// Índice do nó que contém `p` (mundo), do topo para o fundo (o último
/// desenhado vence). `null` se nenhum. Nós com `w`/`h` <= 0 nunca são
/// atingidos.
pub fn hitNode(nodes: []const GraphNode, p: Vec2) ?usize {
    var i = nodes.len;
    while (i > 0) {
        i -= 1;
        if (nodes[i].rect().contains(p)) return i;
    }
    return null;
}

/// Passo da grade (unidades de mundo) para um espaçamento-alvo de
/// `target_px` px de tela: o "número redondo" mais próximo de
/// `target_px / zoom` na família 1, 2, 5 × 10^k (limiares 1.5 / 3.5 /
/// 7.5). Devolve `0` (sem grade) se qualquer entrada for não-finita ou
/// não-positiva, ou se o passo calculado não for finito e positivo.
pub fn gridStep(zoom: f32, target_px: f32) f32 {
    if (!std.math.isFinite(zoom) or zoom <= 0) return 0;
    if (!std.math.isFinite(target_px) or target_px <= 0) return 0;
    const raw = target_px / zoom;
    if (!std.math.isFinite(raw) or raw <= 0) return 0;
    // Maior potência de 10 <= raw (multiplicação exata em f32 até 10^10).
    var guard: u32 = 0;
    var mag: f32 = 1;
    while (mag * 10 <= raw and guard < 64) : (guard += 1) mag *= 10;
    while (mag > raw and guard < 128) : (guard += 1) mag /= 10;
    if (!std.math.isFinite(mag) or mag <= 0) return 0;
    const n = raw / mag; // 1..10
    const mult: f32 = if (n < 1.5) 1 else if (n < 3.5) 2 else if (n < 7.5) 5 else 10;
    const step = mult * mag;
    return if (std.math.isFinite(step) and step > 0) step else 0;
}

test "Transform: mundo↔tela, zoomAt e guardas" {
    const stdt = @import("std");
    const t = Transform{ .pan = .{ .x = 10, .y = 20 }, .zoom = 2 };
    try stdt.testing.expect(t.isValid());
    const s = t.worldToScreen(.{ .x = 3, .y = 4 });
    try stdt.testing.expectEqual(@as(f32, 16), s.x); // 3*2 + 10
    try stdt.testing.expectEqual(@as(f32, 28), s.y); // 4*2 + 20
    const w = t.screenToWorld(s);
    try stdt.testing.expectEqual(@as(f32, 3), w.x);
    try stdt.testing.expectEqual(@as(f32, 4), w.y);

    // O ponto-mundo sob a âncora não se move ao aplicar zoom.
    const anchor = Vec2.init(50, 40);
    const before = t.screenToWorld(anchor);
    const t2 = t.zoomAt(anchor, 1.5, 0.25, 4);
    try stdt.testing.expectEqual(@as(f32, 3), t2.zoom);
    const after = t2.worldToScreen(before);
    try stdt.testing.expectApproxEqAbs(anchor.x, after.x, 1e-4);
    try stdt.testing.expectApproxEqAbs(anchor.y, after.y, 1e-4);

    // Clamp nas bordas (argumentos em qualquer ordem).
    try stdt.testing.expectEqual(@as(f32, 4), t.zoomAt(anchor, 100, 4, 0.25).zoom);
    try stdt.testing.expectEqual(@as(f32, 0.25), t.zoomAt(anchor, 0.001, 4, 0.25).zoom);
    // Inválidos ⇒ inalterado.
    try stdt.testing.expectEqual(@as(f32, 2), t.zoomAt(anchor, std.math.nan(f32), 0.25, 4).zoom);
    try stdt.testing.expectEqual(@as(f32, 2), t.zoomAt(anchor, 2, 0.25, std.math.inf(f32)).zoom);
    try stdt.testing.expect(!(Transform{ .zoom = 0 }).isValid());
    try stdt.testing.expect(!(Transform{ .zoom = std.math.nan(f32) }).isValid());
}

test "GraphNode: validade, rect e portPos" {
    const stdt = @import("std");
    const n = GraphNode{
        .pos = .{ .x = 0, .y = 0 },
        .size = .{ .x = 100, .y = 60 },
        .inputs = 2,
        .outputs = 3,
    };
    try stdt.testing.expect(n.isValid());
    const r = n.rect();
    try stdt.testing.expectEqual(@as(f32, 100), r.w);
    try stdt.testing.expectEqual(@as(f32, 60), r.h);

    // Entradas à esquerda: 1*60/3 = 20, 2*60/3 = 40.
    const in0 = portPos(n, .input, 0);
    try stdt.testing.expectEqual(@as(f32, 0), in0.x);
    try stdt.testing.expectEqual(@as(f32, 20), in0.y);
    try stdt.testing.expectEqual(@as(f32, 40), portPos(n, .input, 1).y);
    // Índice acima do total clampa no último pino.
    try stdt.testing.expectEqual(@as(f32, 40), portPos(n, .input, 9).y);
    // Saídas à direita: 1*60/4 = 15.
    const o0 = portPos(n, .output, 0);
    try stdt.testing.expectEqual(@as(f32, 100), o0.x);
    try stdt.testing.expectEqual(@as(f32, 15), o0.y);

    // Sem pinos: centro vertical da borda.
    const none = GraphNode{ .pos = .{ .x = 4, .y = 10 }, .size = .{ .x = 10, .y = 20 } };
    const c = portPos(none, .output, 0);
    try stdt.testing.expectEqual(@as(f32, 14), c.x);
    try stdt.testing.expectEqual(@as(f32, 20), c.y);

    // Inválidos.
    try stdt.testing.expect(!(GraphNode{ .size = .{ .x = 0, .y = 10 } }).isValid());
    try stdt.testing.expect(!(GraphNode{ .pos = .{ .x = std.math.nan(f32), .y = 0 } }).isValid());
}

test "edgeAnchors: liga saída→entrada e rejeita índices" {
    const stdt = @import("std");
    const nodes = [_]GraphNode{
        .{ .pos = .{ .x = 0, .y = 0 }, .size = .{ .x = 20, .y = 20 }, .outputs = 1 },
        .{ .pos = .{ .x = 60, .y = 0 }, .size = .{ .x = 20, .y = 20 }, .inputs = 1 },
    };
    const a = edgeAnchors(&nodes, .{ .from = 0, .to = 1 }).?;
    try stdt.testing.expectEqual(@as(f32, 20), a[0].x); // saída: borda direita
    try stdt.testing.expectEqual(@as(f32, 10), a[0].y);
    try stdt.testing.expectEqual(@as(f32, 60), a[1].x); // entrada: borda esquerda
    try stdt.testing.expectEqual(@as(f32, 10), a[1].y);

    try stdt.testing.expect(edgeAnchors(&nodes, .{ .from = 0, .to = 5 }) == null);
    try stdt.testing.expect(edgeAnchors(&nodes, .{ .from = 9, .to = 0 }) == null);
    try stdt.testing.expect(edgeAnchors(&.{}, .{}) == null);
}

test "bezier: extremos, meio e controle mínimo" {
    const stdt = @import("std");
    const a = Vec2.init(0, 0);
    const b = Vec2.init(100, 0);
    const c = bezierControls(a, b);
    try stdt.testing.expectEqual(@as(f32, 50), c[0].x); // max(24, 100/2)
    try stdt.testing.expectEqual(@as(f32, 50), c[1].x); // 100 - 50
    try stdt.testing.expectEqual(@as(f32, 0), c[0].y);

    const p0 = bezierPoint(a, c[0], c[1], b, 0);
    try stdt.testing.expectEqual(@as(f32, 0), p0.x);
    const p1 = bezierPoint(a, c[0], c[1], b, 1);
    try stdt.testing.expectEqual(@as(f32, 100), p1.x);
    // Simétrico: (3*0.5*50 + 3*0.5*50 + 0.125*100) = 50.
    const pm = bezierPoint(a, c[0], c[1], b, 0.5);
    try stdt.testing.expectEqual(@as(f32, 50), pm.x);
    try stdt.testing.expectEqual(@as(f32, 0), pm.y);

    // Distância curta: controle mínimo de 24 px.
    const cc = bezierControls(a, Vec2.init(10, 0));
    try stdt.testing.expectEqual(@as(f32, 24), cc[0].x);
    try stdt.testing.expectEqual(@as(f32, -14), cc[1].x);
}

test "hitNode: topo vence, inválidos e vazio" {
    const stdt = @import("std");
    const nodes = [_]GraphNode{
        .{ .pos = .{ .x = 0, .y = 0 }, .size = .{ .x = 50, .y = 50 } },
        .{ .pos = .{ .x = 10, .y = 10 }, .size = .{ .x = 50, .y = 50 } },
        .{ .pos = .{ .x = 0, .y = 0 }, .size = .{ .x = 0, .y = 0 } }, // inválido
    };
    try stdt.testing.expectEqual(@as(?usize, 1), hitNode(&nodes, Vec2.init(20, 20)));
    // (55,55) está só no nó 1.
    try stdt.testing.expectEqual(@as(?usize, 1), hitNode(&nodes, Vec2.init(55, 55)));
    // (5,5) está no nó 0 (o inválido não conta).
    try stdt.testing.expectEqual(@as(?usize, 0), hitNode(&nodes, Vec2.init(5, 5)));
    try stdt.testing.expectEqual(@as(?usize, null), hitNode(&nodes, Vec2.init(200, 200)));
    try stdt.testing.expectEqual(@as(?usize, null), hitNode(&.{}, Vec2.init(0, 0)));
}

test "gridStep: números redondos, escala e guardas" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(f32, 50), gridStep(1.0, 64));
    try stdt.testing.expectEqual(@as(f32, 100), gridStep(1.0, 100));
    try stdt.testing.expectEqual(@as(f32, 200), gridStep(1.0, 150));
    try stdt.testing.expectEqual(@as(f32, 50), gridStep(2.0, 100));
    try stdt.testing.expectEqual(@as(f32, 20), gridStep(0.5, 10));
    try stdt.testing.expectApproxEqAbs(@as(f32, 0.5), gridStep(1.0, 0.5), 1e-6);
    // Guardas.
    try stdt.testing.expectEqual(@as(f32, 0), gridStep(0, 64));
    try stdt.testing.expectEqual(@as(f32, 0), gridStep(-1, 64));
    try stdt.testing.expectEqual(@as(f32, 0), gridStep(1, 0));
    try stdt.testing.expectEqual(@as(f32, 0), gridStep(std.math.nan(f32), 64));
    try stdt.testing.expectEqual(@as(f32, 0), gridStep(1, std.math.inf(f32)));
    try stdt.testing.expectEqual(@as(f32, 0), gridStep(std.math.inf(f32), 64));
}
