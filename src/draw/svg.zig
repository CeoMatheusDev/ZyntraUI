//! ZyntraUI — parser de path SVG (draw/svg).
//!
//! Escopo M160: transforma a string de um `<path>` SVG ("M 0 0 L 10
//! 10 C ... Z") em segmentos de caminho (ver `draw.path`).
//! - Comandos suportados: `M/m` (moveto), `L/l` (lineto), `H/h` e
//!   `V/v` (lineto horizontal/vertical), `C/c` (cúbica), `S/s` (cúbica
//!   suave), `Q/q` (quadrática), `T/t` (quadrática suave), `A/a`
//!   (arco) e `Z/z` (fecha).
//! - Números: `1`, `1.5`, `.5`, `-1`, `1e-3` (separadores: espaço e
//!   vírgula; o sinal também separa).
//! - Repetição implícita: depois de `M`, os pares seguintes são
//!   `L` (relativo: `l`).
//! - O arco (`A`) é convertido em cúbicas de Bézier (no máximo 90°
//!   por segmento) — a conversão é a mesma dos viewers 2D.
//!
//! Erros: `InvalidSyntax` (comando ou número inválido), `InvalidArgument`
//! (buffer de segmentos pequeno, coordenada não-finita).

const std = @import("std");
const types = @import("../core/types.zig");
const path_mod = @import("path.zig");

/// Erros do parser.
pub const Error = error{
    /// A string não é um path SVG válido.
    InvalidSyntax,
    /// Argumento inválido (buffer pequeno, coordenada não-finita).
    InvalidArgument,
};

/// Estado do parser.
const Parser = struct {
    text: []const u8,
    pos: usize = 0,
    builder: path_mod.Builder,
    /// Ponto atual (o último alcançado).
    current: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Último ponto de controle de uma cúbica (para `S`).
    last_cubic_ctrl: ?types.Vec2 = null,
    /// Último ponto de controle de uma quadrática (para `T`).
    last_quad_ctrl: ?types.Vec2 = null,
    /// Início do contorno atual (`Z` volta para cá).
    sub_start: types.Vec2 = .{ .x = 0, .y = 0 },
    /// Último comando lido (para a repetição implícita).
    prev: u8 = 0,

    fn isSpace(c: u8) bool {
        return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == ',' or c == '\x0c';
    }

    fn skipSpace(self: *Parser) void {
        while (self.pos < self.text.len and isSpace(self.text[self.pos])) self.pos += 1;
    }

    fn atEnd(self: *Parser) bool {
        self.skipSpace();
        return self.pos >= self.text.len;
    }

    /// Lê um número (sinal, inteiro, fração, expoente).
    fn number(self: *Parser) Error!f32 {
        self.skipSpace();
        const start = self.pos;
        if (self.pos < self.text.len and (self.text[self.pos] == '+' or self.text[self.pos] == '-')) {
            self.pos += 1; // o sinal entra na fatia
        }
        var digits: usize = 0;
        while (self.pos < self.text.len and std.ascii.isDigit(self.text[self.pos])) : (self.pos += 1) {
            digits += 1;
        }
        if (self.pos < self.text.len and self.text[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.text.len and std.ascii.isDigit(self.text[self.pos])) : (self.pos += 1) {
                digits += 1;
            }
        }
        if (digits == 0) return Error.InvalidSyntax;
        if (self.pos < self.text.len and (self.text[self.pos] == 'e' or self.text[self.pos] == 'E')) {
            const save = self.pos;
            self.pos += 1;
            if (self.pos < self.text.len and (self.text[self.pos] == '+' or self.text[self.pos] == '-')) self.pos += 1;
            var exp_digits: usize = 0;
            while (self.pos < self.text.len and std.ascii.isDigit(self.text[self.pos])) : (self.pos += 1) {
                exp_digits += 1;
            }
            if (exp_digits == 0) self.pos = save; // "1e" → número 1 + lixo
        }
        const slice = self.text[start..self.pos];
        const v = std.fmt.parseFloat(f32, slice) catch return Error.InvalidSyntax;
        if (!std.math.isFinite(v)) return Error.InvalidSyntax;
        return v;
    }

    /// Lê um parâmetro booleano (flag) do arco.
    fn flag(self: *Parser) Error!bool {
        self.skipSpace();
        if (self.pos >= self.text.len) return Error.InvalidSyntax;
        const c = self.text[self.pos];
        if (c != '0' and c != '1') return Error.InvalidSyntax;
        self.pos += 1;
        return c == '1';
    }
};

/// Ponto finito (erro se não for).
fn point(x: f32, y: f32) Error!types.Vec2 {
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return Error.InvalidArgument;
    return .{ .x = x, .y = y };
}

/// Analisa um path SVG e escreve os segmentos no buffer do chamador.
///
/// Devolve o construtor (com os segmentos escritos) — use
/// `builder.segments()` para os segmentos e
/// `draw.path.flatten` para achatar.
///
/// Exemplo: `parsePath("M 0 0 L 10 0 L 10 10 Z", &buf)`.
pub fn parsePath(text: []const u8, buf: []path_mod.Segment) Error!path_mod.Builder {
    var p = Parser{ .text = text, .builder = path_mod.Builder.init(buf) };
    var cmd: u8 = 0;
    while (true) {
        p.skipSpace();
        if (p.pos >= p.text.len) break;
        const c = p.text[p.pos];
        if (std.ascii.isAlphabetic(c)) {
            cmd = c;
            p.pos += 1;
            // Um path começa sempre com moveto (regra do SVG).
            if (p.prev == 0 and cmd != 'M' and cmd != 'm') return Error.InvalidSyntax;
        } else {
            // Repetição implícita: depois de M/m valem L/l; depois de
            // qualquer outro comando, o próprio comando (relativo ou não).
            if (cmd == 0) return Error.InvalidSyntax;
            cmd = switch (cmd) {
                'M' => 'L',
                'm' => 'l',
                else => cmd,
            };
        }
        try runCommand(&p, cmd);
        p.prev = cmd;
    }
    return p.builder;
}

/// Executa um comando (os parâmetros já estão no parser).
fn runCommand(p: *Parser, cmd: u8) Error!void {
    const rel = std.ascii.isLower(cmd);
    const upper = std.ascii.toUpper(cmd);
    switch (upper) {
        'M' => {
            const x = try p.number();
            const y = try p.number();
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            p.builder.moveTo(target) catch return Error.InvalidArgument;
            p.current = target;
            p.sub_start = target;
            p.last_cubic_ctrl = null;
            p.last_quad_ctrl = null;
        },
        'L' => {
            const x = try p.number();
            const y = try p.number();
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            p.builder.lineTo(target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_cubic_ctrl = null;
            p.last_quad_ctrl = null;
        },
        'H' => {
            const x = try p.number();
            const target = try point(if (rel) p.current.x + x else x, p.current.y);
            p.builder.lineTo(target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_cubic_ctrl = null;
            p.last_quad_ctrl = null;
        },
        'V' => {
            const y = try p.number();
            const target = try point(p.current.x, if (rel) p.current.y + y else y);
            p.builder.lineTo(target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_cubic_ctrl = null;
            p.last_quad_ctrl = null;
        },
        'C' => {
            const c1x = try p.number();
            const c1y = try p.number();
            const c2x = try p.number();
            const c2y = try p.number();
            const x = try p.number();
            const y = try p.number();
            const c1 = try point(if (rel) p.current.x + c1x else c1x, if (rel) p.current.y + c1y else c1y);
            const c2 = try point(if (rel) p.current.x + c2x else c2x, if (rel) p.current.y + c2y else c2y);
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            p.builder.cubicTo(c1, c2, target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_cubic_ctrl = c2;
            p.last_quad_ctrl = null;
        },
        'S' => {
            const c2x = try p.number();
            const c2y = try p.number();
            const x = try p.number();
            const y = try p.number();
            // O primeiro controle é o reflexo do anterior (se houver).
            const c1: types.Vec2 = if (p.last_cubic_ctrl) |lc|
                .{ .x = 2 * p.current.x - lc.x, .y = 2 * p.current.y - lc.y }
            else
                p.current;
            const c2 = try point(if (rel) p.current.x + c2x else c2x, if (rel) p.current.y + c2y else c2y);
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            p.builder.cubicTo(c1, c2, target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_cubic_ctrl = c2;
            p.last_quad_ctrl = null;
        },
        'Q' => {
            const cx = try p.number();
            const cy = try p.number();
            const x = try p.number();
            const y = try p.number();
            const c = try point(if (rel) p.current.x + cx else cx, if (rel) p.current.y + cy else cy);
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            p.builder.quadTo(c, target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_quad_ctrl = c;
            p.last_cubic_ctrl = null;
        },
        'T' => {
            const x = try p.number();
            const y = try p.number();
            const c: types.Vec2 = if (p.last_quad_ctrl) |lc|
                .{ .x = 2 * p.current.x - lc.x, .y = 2 * p.current.y - lc.y }
            else
                p.current;
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            p.builder.quadTo(c, target) catch return Error.InvalidArgument;
            p.current = target;
            p.last_quad_ctrl = c;
            p.last_cubic_ctrl = null;
        },
        'A' => {
            const rx = try p.number();
            const ry = try p.number();
            const rot = try p.number();
            const large = try p.flag();
            const sweep = try p.flag();
            const x = try p.number();
            const y = try p.number();
            const target = try point(if (rel) p.current.x + x else x, if (rel) p.current.y + y else y);
            try arcTo(p, p.current, rx, ry, rot, large, sweep, target);
            p.current = target;
            p.last_cubic_ctrl = null;
            p.last_quad_ctrl = null;
        },
        'Z' => {
            p.builder.close() catch return Error.InvalidArgument;
            p.current = p.sub_start;
            p.last_cubic_ctrl = null;
            p.last_quad_ctrl = null;
        },
        else => return Error.InvalidSyntax,
    }
}

/// Converte um arco SVG (parâmetros de extremidade) em cúbicas.
fn arcTo(
    p: *Parser,
    from: types.Vec2,
    rx_in: f32,
    ry_in: f32,
    rot_deg: f32,
    large: bool,
    sweep: bool,
    to: types.Vec2,
) Error!void {
    var rx = @abs(rx_in);
    var ry = @abs(ry_in);
    // Raios zerados ⇒ linha reta.
    if (rx < 1e-9 or ry < 1e-9) {
        p.builder.lineTo(to) catch return Error.InvalidArgument;
        return;
    }
    const phi = rot_deg * std.math.pi / 180.0;
    const cos_phi = @cos(phi);
    const sin_phi = @sin(phi);
    const dx2 = (from.x - to.x) / 2.0;
    const dy2 = (from.y - to.y) / 2.0;
    const x1p = cos_phi * dx2 + sin_phi * dy2;
    const y1p = -sin_phi * dx2 + cos_phi * dy2;
    // Escala dos raios quando são pequenos demais.
    const lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
        const s = @sqrt(lambda);
        rx *= s;
        ry *= s;
    }
    const rx2 = rx * rx;
    const ry2 = ry * ry;
    const num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
    const den = rx2 * y1p * y1p + ry2 * x1p * x1p;
    var coef: f32 = 0;
    if (den > 0 and num > 0) coef = @sqrt(num / den);
    if (large == sweep) coef = -coef;
    const cxp = coef * (rx * y1p / ry);
    const cyp = coef * -(ry * x1p / rx);
    const cx = cos_phi * cxp - sin_phi * cyp + (from.x + to.x) / 2.0;
    const cy = sin_phi * cxp + cos_phi * cyp + (from.y + to.y) / 2.0;
    const ux = (x1p - cxp) / rx;
    const uy = (y1p - cyp) / ry;
    const vx = (-x1p - cxp) / rx;
    const vy = (-y1p - cyp) / ry;
    const theta1 = angleBetween(1, 0, ux, uy);
    var delta = angleBetween(ux, uy, vx, vy);
    if (!sweep and delta > 0) delta -= 2.0 * std.math.pi;
    if (sweep and delta < 0) delta += 2.0 * std.math.pi;

    // No máximo 90° por segmento.
    const segments: u32 = @intFromFloat(@ceil(@abs(delta) / (std.math.pi / 2.0)));
    const n = if (segments == 0) 1 else segments;
    const step = delta / @as(f32, @floatFromInt(n));
    const alpha = 4.0 / 3.0 * @tan(step / 4.0);
    var theta = theta1;
    var cur = from;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const next = theta + step;
        const cos_t = @cos(theta);
        const sin_t = @sin(theta);
        const cos_n = @cos(next);
        const sin_n = @sin(next);
        // Ponto na elipse (com a rotação).
        const pointAt = struct {
            fn f(ccx: f32, ccy: f32, erx: f32, ery: f32, c: f32, s: f32, ct: f32, st: f32) types.Vec2 {
                const ex = erx * ct;
                const ey = ery * st;
                return .{ .x = ccx + c * ex - s * ey, .y = ccy + s * ex + c * ey };
            }
        }.f;
        const p2 = pointAt(cx, cy, rx, ry, cos_phi, sin_phi, cos_n, sin_n);
        // Derivadas (para os controles da cúbica).
        const d1 = struct {
            fn f(erx: f32, ery: f32, c: f32, s: f32, ct: f32, st: f32) types.Vec2 {
                const ex = -erx * st;
                const ey = ery * ct;
                return .{ .x = c * ex - s * ey, .y = s * ex + c * ey };
            }
        }.f;
        const d1v = d1(rx, ry, cos_phi, sin_phi, cos_t, sin_t);
        const c1: types.Vec2 = .{ .x = cur.x + alpha * d1v.x, .y = cur.y + alpha * d1v.y };
        const d2v = d1(rx, ry, cos_phi, sin_phi, cos_n, sin_n);
        const c2: types.Vec2 = .{ .x = p2.x - alpha * d2v.x, .y = p2.y - alpha * d2v.y };
        // O último segmento termina exatamente no destino.
        const last = i + 1 == n;
        const end: types.Vec2 = if (last) to else p2;
        p.builder.cubicTo(c1, c2, end) catch return Error.InvalidArgument;
        cur = end;
        theta = next;
    }
}

/// Ângulo entre dois vetores (em radianos, em (-π, π]).
fn angleBetween(ux: f32, uy: f32, vx: f32, vy: f32) f32 {
    const dot = ux * vx + uy * vy;
    const len = @sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (len <= 0) return 0;
    var ang = std.math.acos(std.math.clamp(dot / len, -1.0, 1.0));
    if (ux * vy - uy * vx < 0) ang = -ang;
    return ang;
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test "svg: caminho simples com moveTo/lineTo/close" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 10 20 L 30 40 Z", &segs);
    try std.testing.expectEqual(@as(usize, 3), b.len);
    try std.testing.expect(b.segments()[0] == .move_to);
    try std.testing.expect(b.segments()[1] == .line_to);
    try std.testing.expect(b.segments()[2] == .close);
    const mv = b.segments()[0].move_to;
    try std.testing.expectApproxEqAbs(@as(f32, 10), mv.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), mv.y, 0.001);
}

test "svg: coordenadas relativas" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("m 10 10 l 5 0 l 0 5", &segs);
    try std.testing.expectEqual(@as(usize, 3), b.len);
    const l1 = b.segments()[1].line_to;
    try std.testing.expectApproxEqAbs(@as(f32, 15), l1.x, 0.001);
    const l2 = b.segments()[2].line_to;
    try std.testing.expectApproxEqAbs(@as(f32, 15), l2.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15), l2.y, 0.001);
}

test "svg: repetição implícita depois do moveto" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 0 0 10 0 10 10", &segs);
    try std.testing.expectEqual(@as(usize, 3), b.len);
    try std.testing.expect(b.segments()[1] == .line_to);
    try std.testing.expect(b.segments()[2] == .line_to);
    const l2 = b.segments()[2].line_to;
    try std.testing.expectApproxEqAbs(@as(f32, 10), l2.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), l2.y, 0.001);
}

test "svg: H e V" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 5 5 H 20 V 30", &segs);
    try std.testing.expectEqual(@as(usize, 3), b.len);
    const h = b.segments()[1].line_to;
    try std.testing.expectApproxEqAbs(@as(f32, 20), h.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), h.y, 0.001);
    const v = b.segments()[2].line_to;
    try std.testing.expectApproxEqAbs(@as(f32, 20), v.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), v.y, 0.001);
}

test "svg: números sem separador e com expoente" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M1.5-2.5L1e1,0", &segs);
    try std.testing.expectEqual(@as(usize, 2), b.len);
    const mv = b.segments()[0].move_to;
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), mv.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -2.5), mv.y, 0.001);
    const ln = b.segments()[1].line_to;
    try std.testing.expectApproxEqAbs(@as(f32, 10), ln.x, 0.001);
}

test "svg: curva cúbica e suave" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 0 0 C 0 10 10 10 10 0 S 20 -10 20 0", &segs);
    try std.testing.expectEqual(@as(usize, 3), b.len);
    try std.testing.expect(b.segments()[1] == .cubic_to);
    try std.testing.expect(b.segments()[2] == .cubic_to);
    // O reflexo do controle anterior (10,10) em torno do ponto atual
    // (10,0) vira o primeiro controle: (10,-10).
    const c = b.segments()[2].cubic_to;
    try std.testing.expectApproxEqAbs(@as(f32, 10), c.c1.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -10), c.c1.y, 0.001);
}

test "svg: quadrática e suave" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 0 0 Q 5 10 10 0 T 20 0", &segs);
    try std.testing.expectEqual(@as(usize, 3), b.len);
    // A quadrática é convertida em cúbica.
    try std.testing.expect(b.segments()[1] == .cubic_to);
    try std.testing.expect(b.segments()[2] == .cubic_to);
}

test "svg: arco vira cúbicas" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 0 0 A 10 10 0 0 1 20 0", &segs);
    // Um arco de 180° ⇒ 2 segmentos de 90° (mais o moveto).
    try std.testing.expectEqual(@as(usize, 3), b.len);
    try std.testing.expect(b.segments()[0] == .move_to);
    try std.testing.expect(b.segments()[1] == .cubic_to);
    try std.testing.expect(b.segments()[2] == .cubic_to);
    // O fim é o ponto pedido.
    const last = b.segments()[2].cubic_to;
    try std.testing.expectApproxEqAbs(@as(f32, 20), last.p.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last.p.y, 0.01);
}

test "svg: arco com raio zero vira linha" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 0 0 A 0 0 0 0 1 10 10", &segs);
    try std.testing.expectEqual(@as(usize, 2), b.len);
    try std.testing.expect(b.segments()[1] == .line_to);
}

test "svg: sintaxe inválida" {
    var segs: [16]path_mod.Segment = undefined;
    try std.testing.expectError(Error.InvalidSyntax, parsePath("X 1 2", &segs));
    try std.testing.expectError(Error.InvalidSyntax, parsePath("M 1", &segs));
    try std.testing.expectError(Error.InvalidSyntax, parsePath("M 1 zzz", &segs));
    try std.testing.expectError(Error.InvalidSyntax, parsePath("L 1 2", &segs));
}

test "svg: buffer de segmentos pequeno" {
    var segs: [1]path_mod.Segment = undefined;
    try std.testing.expectError(Error.InvalidArgument, parsePath("M 0 0 L 1 1", &segs));
}

test "svg: o path achatado tem o bbox esperado" {
    var segs: [16]path_mod.Segment = undefined;
    const b = try parsePath("M 0 0 L 40 0 L 40 20 Z", &segs);
    var points: [64]types.Vec2 = undefined;
    var contours: [4]path_mod.ContourRange = undefined;
    const flat = try path_mod.flatten(b.segments(), 0.25, &points, &contours);
    const r = flat.bounds();
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), r.w, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), r.h, 0.001);
}

// ---------------------------------------------------------------------------
// Fuzz
// ---------------------------------------------------------------------------

test "fuzz svg: o parser nunca quebra (nada de panic, sem laço infinito)" {
    try std.testing.fuzz({}, fuzzParse, .{});
}

fn fuzzParse(_: void, smith: *std.testing.Smith) !void {
    var buf: [128]u8 = undefined;
    smith.bytes(&buf);
    const n: usize = smith.valueRangeAtMost(u8, 0, 128);
    const input = buf[0..n];

    var segs: [256]path_mod.Segment = undefined;
    const builder = parsePath(input, &segs) catch {
        // Path inválido: erro esperado (nunca panic).
        return;
    };
    // O path válido tem segmentos coerentes.
    for (builder.segments()) |seg| {
        switch (seg) {
            .move_to, .line_to => |p| {
                try std.testing.expect(std.math.isFinite(p.x) and std.math.isFinite(p.y));
            },
            .cubic_to => |c| {
                try std.testing.expect(std.math.isFinite(c.c1.x) and std.math.isFinite(c.c1.y));
                try std.testing.expect(std.math.isFinite(c.c2.x) and std.math.isFinite(c.c2.y));
                try std.testing.expect(std.math.isFinite(c.p.x) and std.math.isFinite(c.p.y));
            },
            .quad_to => |c| {
                try std.testing.expect(std.math.isFinite(c.c.x) and std.math.isFinite(c.c.y));
                try std.testing.expect(std.math.isFinite(c.p.x) and std.math.isFinite(c.p.y));
            },
            .close => {},
        }
    }
    // O achatamento não pode estourar os buffers nem o tempo.
    var points: [1024]types.Vec2 = undefined;
    var contours: [128]path_mod.ContourRange = undefined;
    const flat = path_mod.flatten(builder.segments(), 0.25, &points, &contours) catch |err| {
        try std.testing.expectEqual(error.NoSpaceLeft, err);
        return;
    };
    // Cada contorno cabe nos pontos.
    for (flat.contours) |c| {
        try std.testing.expect(c.start + c.len <= flat.points.len);
        try std.testing.expect(c.len >= 2);
    }
}
