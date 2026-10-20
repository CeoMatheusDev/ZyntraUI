//! ZyntraUI — caminhos vetoriais (draw/path).
//!
//! Escopo M158: a GEOMETRIA do caminho vetorial (ícones, formas, gráficos)
//! — o módulo é puro: não aloca, não rasteriza e não conhece o framebuffer.
//! - `Builder`: monta um caminho com segmentos (`moveTo`/`lineTo`/
//!   `cubicTo`/`quadTo`/`close`) em um buffer do CHAMADOR.
//! - `flatten`: achata o caminho em polilinhas (contornos) com tolerância
//!   em pixels — é o que o rasterizador consome.
//! - `ContourRange`: a faixa de um contorno dentro da lista de pontos.
//! - `bounds`: o menor rect que contém o caminho achatado.
//! Ownership: os segmentos e os pontos achatados vivem nos buffers do
//! chamador (o chamador os mantém vivos até o desenho acabar).
//! Validação: coordenadas finitas; buffers curtos devolvem
//! `NoSpaceLeft`; tolerância <= 0 ou não-finita ⇒ `InvalidArgument`.

const std = @import("std");
const types = @import("../core/types.zig");

/// Erros do módulo de caminhos.
pub const Error = error{
    /// Argumento inválido (coordenada não-finita, tolerância inválida).
    InvalidArgument,
    /// O buffer do chamador não tem espaço para o resultado.
    NoSpaceLeft,
};

/// Soma de vetores.
fn vAdd(a: types.Vec2, b: types.Vec2) types.Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

/// Diferença de vetores.
fn vSub(a: types.Vec2, b: types.Vec2) types.Vec2 {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}

/// Vetor escalado.
fn vScale(a: types.Vec2, s: f32) types.Vec2 {
    return .{ .x = a.x * s, .y = a.y * s };
}

/// Comprimento do vetor.
fn vLen(a: types.Vec2) f32 {
    return @sqrt(a.x * a.x + a.y * a.y);
}

/// Curva cúbica de Bézier (dois pontos de controle + o ponto final).
pub const Cubic = extern struct {
    c1: types.Vec2 = .{},
    c2: types.Vec2 = .{},
    p: types.Vec2 = .{},
};

/// Curva quadrática de Bézier (um ponto de controle + o ponto final).
pub const Quad = extern struct {
    c: types.Vec2 = .{},
    p: types.Vec2 = .{},
};

/// Segmento de um caminho (antes do achatamento).
pub const Segment = union(enum) {
    /// Começa um novo contorno em `p`.
    move_to: types.Vec2,
    /// Linha até `p`.
    line_to: types.Vec2,
    /// Cúbica de Bézier até `p`.
    cubic_to: Cubic,
    /// Quadrática de Bézier até `p`.
    quad_to: Quad,
    /// Fecha o contorno atual (volta ao ponto de partida).
    close,
};

/// Faixa de um contorno dentro da lista de pontos achatados.
pub const ContourRange = extern struct {
    /// Primeiro ponto do contorno.
    start: u32 = 0,
    /// Quantidade de pontos (>= 2).
    len: u32 = 0,
    /// O contorno fecha sozinho (o último ponto liga no primeiro).
    closed: bool = false,
};

/// Caminho achatado: pontos + a faixa de cada contorno.
pub const Flat = struct {
    /// Todos os pontos (contornos seguidos).
    points: []const types.Vec2 = &.{},
    /// Um item por contorno.
    contours: []const ContourRange = &.{},

    /// Quantidade total de pontos.
    pub fn pointCount(self: Flat) usize {
        return self.points.len;
    }

    /// Quantidade de contornos.
    pub fn contourCount(self: Flat) usize {
        return self.contours.len;
    }

    /// Os pontos de um contorno (vazio se o índice é inválido).
    pub fn contourPoints(self: Flat, index: usize) []const types.Vec2 {
        if (index >= self.contours.len) return &.{};
        const c = self.contours[index];
        return self.points[c.start..][0..c.len];
    }

    /// Menor rect que contém todos os pontos (vazio se não há pontos).
    pub fn bounds(self: Flat) types.Rect {
        if (self.points.len == 0) return .{};
        var min_x = self.points[0].x;
        var min_y = self.points[0].y;
        var max_x = self.points[0].x;
        var max_y = self.points[0].y;
        for (self.points) |p| {
            min_x = @min(min_x, p.x);
            min_y = @min(min_y, p.y);
            max_x = @max(max_x, p.x);
            max_y = @max(max_y, p.y);
        }
        return .{
            .x = min_x,
            .y = min_y,
            .w = max_x - min_x,
            .h = max_y - min_y,
        };
    }
};

/// Construtor de caminhos: escreve os segmentos em um buffer do chamador.
pub const Builder = struct {
    /// Buffer de segmentos (o chamador detém).
    segs: []Segment = &.{},
    /// Segmentos já escritos.
    len: usize = 0,
    /// Ponto atual (o último `moveTo`/`lineTo`/fim de curva).
    current: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Ponto de partida do contorno atual.
    sub_start: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Há um contorno em andamento?
    has_current: bool = false,
    /// O contorno atual foi fechado?
    closed: bool = false,

    /// Cria um construtor sobre `buf` (segmentos do chamador).
    pub fn init(buf: []Segment) Builder {
        return .{ .segs = buf };
    }

    /// Segmentos escritos até agora.
    pub fn segments(self: *const Builder) []const Segment {
        return self.segs[0..self.len];
    }

    /// true se o caminho está vazio.
    pub fn isEmpty(self: *const Builder) bool {
        return self.len == 0;
    }

    fn push(self: *Builder, seg: Segment) Error!void {
        if (self.len >= self.segs.len) return Error.NoSpaceLeft;
        self.segs[self.len] = seg;
        self.len += 1;
    }

    fn valid(p: types.Vec2) bool {
        return std.math.isFinite(p.x) and std.math.isFinite(p.y);
    }

    /// Começa um contorno em `p`.
    pub fn moveTo(self: *Builder, p: types.Vec2) Error!void {
        if (!valid(p)) return Error.InvalidArgument;
        try self.push(.{ .move_to = p });
        self.current = p;
        self.sub_start = p;
        self.has_current = true;
        self.closed = false;
    }

    /// Linha até `p` (começa um contorno em `p` se não houver nenhum).
    pub fn lineTo(self: *Builder, p: types.Vec2) Error!void {
        if (!valid(p)) return Error.InvalidArgument;
        if (!self.has_current) return self.moveTo(p);
        try self.push(.{ .line_to = p });
        self.current = p;
        return;
    }

    /// Cúbica de Bézier até `p` (começa um contorno se não houver nenhum).
    pub fn cubicTo(self: *Builder, c1: types.Vec2, c2: types.Vec2, p: types.Vec2) Error!void {
        if (!valid(c1) or !valid(c2) or !valid(p)) return Error.InvalidArgument;
        if (!self.has_current) {
            try self.moveTo(p);
            return;
        }
        try self.push(.{ .cubic_to = .{ .c1 = c1, .c2 = c2, .p = p } });
        self.current = p;
    }

    /// Quadrática de Bézier até `p` (convertida em cúbica equivalente).
    pub fn quadTo(self: *Builder, c: types.Vec2, p: types.Vec2) Error!void {
        if (!valid(c) or !valid(p)) return Error.InvalidArgument;
        if (!self.has_current) {
            try self.moveTo(p);
            return;
        }
        // Equivalência exata: a quadrática vira cúbica com os controles
        // nos 2/3 e 1/3 do caminho.
        const c1 = vAdd(self.current, vScale(vSub(c, self.current), 2.0 / 3.0));
        const c2 = vAdd(p, vScale(vSub(c, p), 2.0 / 3.0));
        try self.cubicTo(c1, c2, p);
    }

    /// Fecha o contorno atual (volta ao ponto de partida).
    pub fn close(self: *Builder) Error!void {
        if (!self.has_current) return;
        if (self.closed) return;
        try self.push(.close);
        self.current = self.sub_start;
        self.closed = true;
    }

    /// Retângulo (contorno fechado).
    pub fn rect(self: *Builder, r: types.Rect) Error!void {
        if (!valid(.{ .x = r.x, .y = r.y }) or !std.math.isFinite(r.w) or
            !std.math.isFinite(r.h))
        {
            return Error.InvalidArgument;
        }
        if (r.w <= 0 or r.h <= 0) return Error.InvalidArgument;
        try self.moveTo(.{ .x = r.x, .y = r.y });
        try self.lineTo(.{ .x = r.x + r.w, .y = r.y });
        try self.lineTo(.{ .x = r.x + r.w, .y = r.y + r.h });
        try self.lineTo(.{ .x = r.x, .y = r.y + r.h });
        try self.close();
    }

    /// Retângulo de cantos arredondados (arcos aproximados por cúbicas).
    pub fn roundRect(self: *Builder, r: types.Rect, radius: f32) Error!void {
        if (!std.math.isFinite(radius) or radius < 0) return Error.InvalidArgument;
        if (!valid(.{ .x = r.x, .y = r.y }) or !std.math.isFinite(r.w) or
            !std.math.isFinite(r.h))
        {
            return Error.InvalidArgument;
        }
        if (r.w <= 0 or r.h <= 0) return Error.InvalidArgument;
        const rad = @min(radius, @min(r.w, r.h) / 2.0);
        if (rad <= 0) return self.rect(r);
        // Fator de círculo (4/3·tan(π/8)) para as cúbicas dos cantos.
        const k: f32 = 0.5522847498307936;
        const x0 = r.x;
        const y0 = r.y;
        const x1 = r.x + r.w;
        const y1 = r.y + r.h;
        try self.moveTo(.{ .x = x0 + rad, .y = y0 });
        try self.lineTo(.{ .x = x1 - rad, .y = y0 });
        try self.cubicTo(
            .{ .x = x1 - rad + rad * k, .y = y0 },
            .{ .x = x1, .y = y0 + rad - rad * k },
            .{ .x = x1, .y = y0 + rad },
        );
        try self.lineTo(.{ .x = x1, .y = y1 - rad });
        try self.cubicTo(
            .{ .x = x1, .y = y1 - rad + rad * k },
            .{ .x = x1 - rad + rad * k, .y = y1 },
            .{ .x = x1 - rad, .y = y1 },
        );
        try self.lineTo(.{ .x = x0 + rad, .y = y1 });
        try self.cubicTo(
            .{ .x = x0 + rad - rad * k, .y = y1 },
            .{ .x = x0, .y = y1 - rad + rad * k },
            .{ .x = x0, .y = y1 - rad },
        );
        try self.lineTo(.{ .x = x0, .y = y0 + rad });
        try self.cubicTo(
            .{ .x = x0, .y = y0 + rad - rad * k },
            .{ .x = x0 + rad - rad * k, .y = y0 },
            .{ .x = x0 + rad, .y = y0 },
        );
        try self.close();
    }

    /// Círculo (4 cúbicas).
    pub fn circle(self: *Builder, center: types.Vec2, radius: f32) Error!void {
        if (!valid(center) or !std.math.isFinite(radius)) return Error.InvalidArgument;
        if (radius <= 0) return Error.InvalidArgument;
        const k: f32 = 0.5522847498307936;
        const cx = center.x;
        const cy = center.y;
        try self.moveTo(.{ .x = cx + radius, .y = cy });
        try self.cubicTo(
            .{ .x = cx + radius, .y = cy + radius * k },
            .{ .x = cx + radius * k, .y = cy + radius },
            .{ .x = cx, .y = cy + radius },
        );
        try self.cubicTo(
            .{ .x = cx - radius * k, .y = cy + radius },
            .{ .x = cx - radius, .y = cy + radius * k },
            .{ .x = cx - radius, .y = cy },
        );
        try self.cubicTo(
            .{ .x = cx - radius, .y = cy - radius * k },
            .{ .x = cx - radius * k, .y = cy - radius },
            .{ .x = cx, .y = cy - radius },
        );
        try self.cubicTo(
            .{ .x = cx + radius * k, .y = cy - radius },
            .{ .x = cx + radius, .y = cy - radius * k },
            .{ .x = cx + radius, .y = cy },
        );
        try self.close();
    }
};

/// Quantidade de segmentos de uma cúbica para a tolerância `tol`.
///
/// Usa o erro quadrático da aproximação (a "flatness" da curva):
/// `n = ceil(sqrt(d2 / (8·tol)))`, com `d2` a maior segunda diferença
/// dos pontos de controle. Determinístico e independente da plataforma.
pub fn cubicSegments(p0: types.Vec2, c1: types.Vec2, c2: types.Vec2, p3: types.Vec2, tol: f32) u32 {
    const d2a = vLen(vAdd(vSub(p0, vScale(c1, 2.0)), c2));
    const d2b = vLen(vAdd(vSub(c1, vScale(c2, 2.0)), p3));
    const d2 = @max(d2a, d2b);
    if (d2 <= 0 or tol <= 0) return 1;
    const n = @ceil(@sqrt(d2 / (8.0 * tol)));
    return @max(1, @min(@as(u32, 256), @as(u32, @intFromFloat(n))));
}

/// Fecha o contorno em andamento: escreve a faixa em `out_contours`.
/// Contornos degenerados (menos de 2 pontos) são descartados.
fn flushContour(
    point_count: *usize,
    contour_count: *usize,
    out_contours: []ContourRange,
    contour_start: usize,
    closed: bool,
) Error!void {
    const count = point_count.* - contour_start;
    if (count < 2) return; // contorno degenerado: descartado
    if (contour_count.* >= out_contours.len) return Error.NoSpaceLeft;
    out_contours[contour_count.*] = .{
        .start = @intCast(contour_start),
        .len = @intCast(count),
        .closed = closed,
    };
    contour_count.* += 1;
}

/// Achata os segmentos em polilinhas.
///
/// `out_points` recebe todos os pontos (contornos seguidos) e
/// `out_contours` recebe uma faixa por contorno. O resultado é
/// determinístico: a mesma entrada e a mesma tolerância dão o mesmo
/// caminho.
///
/// Erros: `InvalidArgument` (tolerância inválida ou coordenada não-finita),
/// `NoSpaceLeft` (buffers curtos — o resultado parcial é descartado).
pub fn flatten(
    segments: []const Segment,
    tol: f32,
    out_points: []types.Vec2,
    out_contours: []ContourRange,
) Error!Flat {
    if (!std.math.isFinite(tol) or tol <= 0) return Error.InvalidArgument;

    var pts: usize = 0;
    var conts: usize = 0;
    var cur: types.Vec2 = .{ .x = 0, .y = 0 };
    var start: types.Vec2 = .{ .x = 0, .y = 0 };
    var open = false; // há um contorno em andamento
    var closed = false;
    var contour_start: usize = 0;

    for (segments) |seg| {
        switch (seg) {
            .move_to => |p| {
                if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y)) return Error.InvalidArgument;
                if (open) try flushContour(&pts, &conts, out_contours, contour_start, closed);
                if (pts >= out_points.len) return Error.NoSpaceLeft;
                out_points[pts] = p;
                pts += 1;
                contour_start = pts - 1;
                cur = p;
                start = p;
                open = true;
                closed = false;
            },
            .line_to => |p| {
                if (!std.math.isFinite(p.x) or !std.math.isFinite(p.y)) return Error.InvalidArgument;
                if (!open) {
                    if (pts >= out_points.len) return Error.NoSpaceLeft;
                    out_points[pts] = p;
                    pts += 1;
                    contour_start = pts - 1;
                    cur = p;
                    start = p;
                    open = true;
                    closed = false;
                    break;
                }
                if (pts >= out_points.len) return Error.NoSpaceLeft;
                out_points[pts] = p;
                pts += 1;
                cur = p;
            },
            .cubic_to => |c| {
                if (!std.math.isFinite(c.c1.x) or !std.math.isFinite(c.c1.y) or
                    !std.math.isFinite(c.c2.x) or !std.math.isFinite(c.c2.y) or
                    !std.math.isFinite(c.p.x) or !std.math.isFinite(c.p.y))
                {
                    return Error.InvalidArgument;
                }
                if (!open) {
                    if (pts >= out_points.len) return Error.NoSpaceLeft;
                    out_points[pts] = cur;
                    pts += 1;
                    contour_start = pts - 1;
                    open = true;
                    closed = false;
                }
                const n = cubicSegments(cur, c.c1, c.c2, c.p, tol);
                for (1..n + 1) |i| {
                    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                    const p = cubicAt(cur, c.c1, c.c2, c.p, t);
                    if (pts >= out_points.len) return Error.NoSpaceLeft;
                    out_points[pts] = p;
                    pts += 1;
                }
                cur = c.p;
            },
            .quad_to => |c| {
                if (!std.math.isFinite(c.c.x) or !std.math.isFinite(c.c.y) or
                    !std.math.isFinite(c.p.x) or !std.math.isFinite(c.p.y))
                {
                    return Error.InvalidArgument;
                }
                const c1 = vAdd(cur, vScale(vSub(c.c, cur), 2.0 / 3.0));
                const c2 = vAdd(c.p, vScale(vSub(c.c, c.p), 2.0 / 3.0));
                if (!open) {
                    if (pts >= out_points.len) return Error.NoSpaceLeft;
                    out_points[pts] = cur;
                    pts += 1;
                    contour_start = pts - 1;
                    open = true;
                    closed = false;
                }
                const n = cubicSegments(cur, c1, c2, c.p, tol);
                for (1..n + 1) |i| {
                    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                    const p = cubicAt(cur, c1, c2, c.p, t);
                    if (pts >= out_points.len) return Error.NoSpaceLeft;
                    out_points[pts] = p;
                    pts += 1;
                }
                cur = c.p;
            },
            .close => {
                if (!open) break;
                try flushContour(&pts, &conts, out_contours, contour_start, true);
                open = false;
                cur = start;
            },
        }
    }
    if (open) try flushContour(&pts, &conts, out_contours, contour_start, closed);

    return .{
        .points = out_points[0..pts],
        .contours = out_contours[0..conts],
    };
}

/// Ponto de uma cúbica de Bézier em `t` (0..1).
pub fn cubicAt(p0: types.Vec2, c1: types.Vec2, c2: types.Vec2, p3: types.Vec2, t: f32) types.Vec2 {
    const u = 1.0 - t;
    const w0 = u * u * u;
    const w1 = 3.0 * u * u * t;
    const w2 = 3.0 * u * t * t;
    const w3 = t * t * t;
    return .{
        .x = p0.x * w0 + c1.x * w1 + c2.x * w2 + p3.x * w3,
        .y = p0.y * w0 + c1.y * w1 + c2.y * w2 + p3.y * w3,
    };
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "path: construtor monta segmentos" {
    var segs: [16]Segment = undefined;
    var b = Builder.init(&segs);
    try std.testing.expect(b.isEmpty());
    try b.moveTo(.{ .x = 0, .y = 0 });
    try b.lineTo(.{ .x = 10, .y = 0 });
    try b.lineTo(.{ .x = 10, .y = 10 });
    try b.close();
    try std.testing.expectEqual(@as(usize, 4), b.len);
    try std.testing.expectEqual(Segment{ .move_to = .{ .x = 0, .y = 0 } }, b.segments()[0]);
    try std.testing.expect(b.segments()[3] == .close);
}

test "path: buffer curto devolve NoSpaceLeft" {
    var segs: [1]Segment = undefined;
    var b = Builder.init(&segs);
    try b.moveTo(.{ .x = 0, .y = 0 });
    try std.testing.expectError(Error.NoSpaceLeft, b.lineTo(.{ .x = 1, .y = 1 }));
}

test "path: coordenada não-finita é rejeitada" {
    var segs: [8]Segment = undefined;
    var b = Builder.init(&segs);
    try std.testing.expectError(Error.InvalidArgument, b.moveTo(.{ .x = std.math.nan(f32), .y = 0 }));
    try std.testing.expectError(Error.InvalidArgument, b.lineTo(.{ .x = 0, .y = std.math.inf(f32) }));
    try std.testing.expectError(Error.InvalidArgument, b.circle(.{ .x = 0, .y = 0 }, -1));
    try std.testing.expectError(Error.InvalidArgument, b.roundRect(.{ .x = 0, .y = 0, .w = 10, .h = 10 }, -1));
}

test "path: achatamento de um quadrado" {
    var segs: [16]Segment = undefined;
    var b = Builder.init(&segs);
    try b.rect(.{ .x = 0, .y = 0, .w = 10, .h = 20 });
    var pts: [32]types.Vec2 = undefined;
    var conts: [4]ContourRange = undefined;
    const flat = try flatten(b.segments(), 0.25, &pts, &conts);
    try std.testing.expectEqual(@as(usize, 1), flat.contourCount());
    try std.testing.expectEqual(@as(usize, 4), flat.pointCount());
    try std.testing.expect(flat.contours[0].closed);
    const r = flat.bounds();
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), r.w, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), r.h, 0.001);
}

test "path: achatamento de uma cúbica" {
    var segs: [16]Segment = undefined;
    var b = Builder.init(&segs);
    try b.moveTo(.{ .x = 0, .y = 0 });
    try b.cubicTo(.{ .x = 0, .y = 10 }, .{ .x = 10, .y = 10 }, .{ .x = 10, .y = 0 });
    var pts: [64]types.Vec2 = undefined;
    var conts: [4]ContourRange = undefined;
    const flat = try flatten(b.segments(), 0.1, &pts, &conts);
    try std.testing.expect(flat.pointCount() > 4);
    // O ponto final é exato.
    const last = flat.points[flat.pointCount() - 1];
    try std.testing.expectApproxEqAbs(@as(f32, 10), last.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last.y, 0.001);
    // O meio da curva está acima da reta.
    const mid = flat.points[flat.pointCount() / 2];
    try std.testing.expect(mid.y > 4.0);
}

test "path: círculo fecha e tem o raio certo" {
    var segs: [64]Segment = undefined;
    var b = Builder.init(&segs);
    try b.circle(.{ .x = 50, .y = 50 }, 20);
    var pts: [256]types.Vec2 = undefined;
    var conts: [4]ContourRange = undefined;
    const flat = try flatten(b.segments(), 0.1, &pts, &conts);
    try std.testing.expectEqual(@as(usize, 1), flat.contourCount());
    try std.testing.expect(flat.contours[0].closed);
    const r = flat.bounds();
    try std.testing.expectApproxEqAbs(@as(f32, 40), r.w, 0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 40), r.h, 0.2);
    // Todo ponto está a ~20 do centro.
    for (flat.points) |p| {
        const d = @sqrt(@as(f32, @floatCast((p.x - 50) * (p.x - 50) + (p.y - 50) * (p.y - 50))));
        try std.testing.expectApproxEqAbs(@as(f32, 20), d, 0.2);
    }
}

test "path: dois contornos independentes" {
    var segs: [32]Segment = undefined;
    var b = Builder.init(&segs);
    try b.rect(.{ .x = 0, .y = 0, .w = 10, .h = 10 });
    try b.rect(.{ .x = 20, .y = 20, .w = 10, .h = 10 });
    var pts: [64]types.Vec2 = undefined;
    var conts: [4]ContourRange = undefined;
    const flat = try flatten(b.segments(), 0.25, &pts, &conts);
    try std.testing.expectEqual(@as(usize, 2), flat.contourCount());
    try std.testing.expectEqual(@as(usize, 8), flat.pointCount());
    const c0 = flat.contourPoints(0);
    const c1 = flat.contourPoints(1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), c0[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), c1[0].x, 0.001);
}

test "path: tolerância inválida e buffer curto" {
    var segs: [16]Segment = undefined;
    var b = Builder.init(&segs);
    try b.rect(.{ .x = 0, .y = 0, .w = 10, .h = 10 });
    var pts: [2]types.Vec2 = undefined;
    var conts: [4]ContourRange = undefined;
    try std.testing.expectError(Error.InvalidArgument, flatten(b.segments(), 0, &pts, &conts));
    try std.testing.expectError(Error.InvalidArgument, flatten(b.segments(), std.math.nan(f32), &pts, &conts));
    try std.testing.expectError(Error.NoSpaceLeft, flatten(b.segments(), 0.25, &pts, &conts));
}

test "path: quadrática vira cúbica equivalente" {
    var segs: [8]Segment = undefined;
    var b = Builder.init(&segs);
    try b.moveTo(.{ .x = 0, .y = 0 });
    try b.quadTo(.{ .x = 5, .y = 10 }, .{ .x = 10, .y = 0 });
    try std.testing.expectEqual(@as(usize, 2), b.len);
    const seg = b.segments()[1];
    try std.testing.expect(seg == .cubic_to);
    const c = seg.cubic_to;
    // O ponto médio da quadrática: (5, 5).
    const mid = cubicAt(.{ .x = 0, .y = 0 }, c.c1, c.c2, c.p, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), mid.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), mid.y, 0.001);
}

test "path: roundRect com raio grande fica dentro do rect" {
    var segs: [64]Segment = undefined;
    var b = Builder.init(&segs);
    try b.roundRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, 100);
    var pts: [256]types.Vec2 = undefined;
    var conts: [4]ContourRange = undefined;
    const flat = try flatten(b.segments(), 0.1, &pts, &conts);
    const r = flat.bounds();
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20), r.w, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 10), r.h, 0.01);
}
