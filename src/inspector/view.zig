//! ZyntraUI — modelo puro de property inspector (inspector/view).
//!
//! Sem `Context` e sem alocação: descritores de propriedade (ponteiros
//! para a memória do chamador), formatação determinística de números,
//! aritmética de arraste/teclado, hit-test de linha e métricas de
//! rolagem. O widget `widgets/inspector_view` consome este módulo.
//!
//! Convenções:
//! - `Property.value` é um apontador para memória do CHAMADOR: o widget
//!   lê e escreve por ali (mesmo idioma do `slider`, que recebe `*f32`).
//! - Números: inteiros em `i64`, reais em `f32`; formatação com
//!   aritmética inteira (determinística, sem depender de formatação de
//!   ponto flutuante da std).
//! - `decimals` de reais: 0..`max_decimals` (o resto é clampado).
//! - Faixa opcional: `Range` só é aplicada quando `min < max`.
//! - Índices fora de faixa são tratados como ausentes.

const std = @import("std");
const types = @import("../core/types.zig");

/// Máximo de casas decimais exibidas num real.
pub const max_decimals: u32 = 6;

/// Tipo de valor/editor de uma propriedade.
pub const Kind = enum { boolean, integer, real, text, choice };

/// Faixa de clamp (aplicada quando `min < max`).
pub const Range = struct {
    min: f32 = 0,
    max: f32 = 1,
};

/// Editor de escolha: índice atual (memória do chamador) + rótulos.
pub const Choice = struct {
    /// Índice da opção atual; clampado para `0..options.len` pelo widget.
    index: *u32,
    /// Rótulos, na ordem (não pode ser vazio).
    options: []const []const u8,
};

/// Valor editável (apontador para memória do chamador).
pub const Value = union(enum) {
    boolean: *bool,
    integer: *i64,
    real: *f32,
    /// Texto somente-leitura exibido na coluna de valores.
    text: []const u8,
    choice: Choice,
};

/// Propriedade exibida numa linha do inspector.
pub const Property = struct {
    /// Nome exibido na coluna da esquerda (vazio ⇒ sem texto).
    name: []const u8 = "",
    /// Valor/editor da linha.
    value: Value,
    /// Somente-leitura: não aceita edição (nem arraste/teclado).
    readonly: bool = false,
    /// Incremento por pixel de arraste (e passo das setas); `null` usa
    /// `1` para inteiros e `InspectorViewOptions.step` para reais.
    step: ?f32 = null,
    /// Casas decimais de reais (`null` usa `InspectorViewOptions.decimals`).
    decimals: ?u32 = null,
    /// Faixa de clamp de inteiros/reais.
    range: ?Range = null,

    /// Tipo derivado da variante ativa.
    pub fn kind(self: Property) Kind {
        return switch (self.value) {
            .boolean => .boolean,
            .integer => .integer,
            .real => .real,
            .text => .text,
            .choice => .choice,
        };
    }

    pub fn isValid(self: Property) bool {
        if (self.step) |s| {
            if (!std.math.isFinite(s) or s <= 0) return false;
        }
        if (self.decimals) |d| {
            if (d > max_decimals) return false;
        }
        if (self.range) |r| {
            if (!std.math.isFinite(r.min) or !std.math.isFinite(r.max)) return false;
        }
        switch (self.value) {
            .boolean, .integer, .real, .text => {},
            .choice => |ch| {
                if (ch.options.len == 0) return false;
            },
        }
        return true;
    }

    /// Passo efetivo por pixel/tecla (sem modificadores).
    pub fn effectiveStep(self: Property, fallback: f32) f32 {
        if (self.step) |s| return s;
        return switch (self.kind()) {
            .integer => 1.0,
            else => fallback,
        };
    }

    /// Casas decimais efetivas de um real.
    pub fn effectiveDecimals(self: Property, fallback: u32) u32 {
        const d = self.decimals orelse fallback;
        return @min(d, max_decimals);
    }
};

/// Escreve `v` em decimal em `buf`; devolve os bytes escritos.
pub fn formatInt(buf: []u8, v: i64) usize {
    const neg = v < 0;
    // Magnitude sem estourar no `i64` mínimo.
    const mag: u64 = if (neg)
        @as(u64, @intCast(-(v + 1))) + 1
    else
        @as(u64, @intCast(v));
    var n: usize = 0;
    if (neg and n < buf.len) {
        buf[n] = '-';
        n += 1;
    }
    return n + writeDigits(buf[n..], mag);
}

/// Escreve `v` com `decimals` casas (0..`max_decimals`) em `buf`;
/// devolve os bytes escritos (0 = sem rótulo: `v` não-finito ou absurdo).
pub fn formatReal(buf: []u8, v: f32, decimals: u32) usize {
    if (!std.math.isFinite(v)) return 0;
    const d = @min(decimals, max_decimals);
    var scale: u64 = 1;
    var i: u32 = 0;
    while (i < d) : (i += 1) scale *= 10;
    const scaled_f = @abs(v) * @as(f32, @floatFromInt(scale));
    if (!(scaled_f < 1.0e18)) return 0; // guarda: evita estouro na conversão
    const scaled: u64 = @intFromFloat(@round(scaled_f));
    const whole = scaled / scale;
    const frac = scaled % scale;
    var n: usize = 0;
    if (v < 0 and scaled != 0 and n < buf.len) {
        buf[n] = '-';
        n += 1;
    }
    n += writeDigits(buf[n..], whole);
    if (d > 0) {
        if (n < buf.len) {
            buf[n] = '.';
            n += 1;
        }
        n += writePadded(buf[n..], frac, d);
    }
    return n;
}

/// Valor após arraste horizontal: `anchor + dx * step`.
/// Entradas não-finitas devolvem `anchor`.
pub fn dragValue(anchor: f32, dx: f32, step: f32) f32 {
    if (!std.math.isFinite(anchor) or !std.math.isFinite(dx) or !std.math.isFinite(step)) {
        return anchor;
    }
    return anchor + dx * step;
}

/// Aplica a faixa (quando `min < max`); sem faixa ou não-finito ⇒ `v`.
pub fn clampToRange(v: f32, range: ?Range) f32 {
    if (!std.math.isFinite(v)) return v;
    const r = range orelse return v;
    if (!(r.min < r.max)) return v;
    return std.math.clamp(v, r.min, r.max);
}

/// Arredonda para `i64` saturando valores fora do intervalo representável
/// (não-finito ⇒ 0).
pub fn toInt(v: f32) i64 {
    if (!std.math.isFinite(v)) return 0;
    const clamped = std.math.clamp(@round(v), -9.0e18, 9.0e18);
    return @intFromFloat(clamped);
}

/// Índice da linha em `y` (px LOCAIS no conteúdo, 0 = topo da primeira
/// linha). `null` se fora de `[0, count * row_h)`.
pub fn rowAtY(y: f32, row_h: f32, count: usize) ?usize {
    if (!std.math.isFinite(y) or !std.math.isFinite(row_h) or row_h <= 0) return null;
    if (y < 0) return null;
    const idx = @floor(y / row_h);
    if (!std.math.isFinite(idx) or idx < 0) return null;
    if (idx >= @as(f32, @floatFromInt(count))) return null;
    return @intFromFloat(idx);
}

/// Altura total do conteúdo (px).
pub fn contentHeight(count: usize, row_h: f32) f32 {
    if (!std.math.isFinite(row_h) or row_h <= 0) return 0;
    return @as(f32, @floatFromInt(count)) * row_h;
}

/// Rolagem máxima para um viewport de altura `viewport_h` (px).
pub fn maxScroll(count: usize, viewport_h: f32, row_h: f32) f32 {
    if (!std.math.isFinite(viewport_h) or viewport_h < 0) return 0;
    return @max(0, contentHeight(count, row_h) - viewport_h);
}

/// Próximo índice ao circular `len` opções a partir de `index`
/// (`delta` típico ±1). `null` se `len == 0`.
pub fn cycleIndex(index: u32, len: usize, delta: i32) ?u32 {
    if (len == 0) return null;
    const l: i64 = @intCast(len);
    var i: i64 = @mod(@as(i64, @intCast(index)), l);
    i = @mod(i + delta, l);
    return @intCast(i);
}

fn writeDigits(buf: []u8, v: u64) usize {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var x = v;
    if (x == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (x > 0) : (x /= 10) {
            tmp[n] = '0' + @as(u8, @intCast(x % 10));
            n += 1;
        }
    }
    const m = @min(n, buf.len);
    var i: usize = 0;
    while (i < m) : (i += 1) buf[i] = tmp[n - 1 - i];
    return m;
}

fn writePadded(buf: []u8, v: u64, width: usize) usize {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var x = v;
    while (n < width and n < tmp.len) : (n += 1) {
        tmp[n] = '0' + @as(u8, @intCast(x % 10));
        x /= 10;
    }
    const m = @min(n, buf.len);
    var i: usize = 0;
    while (i < m) : (i += 1) buf[i] = tmp[m - 1 - i];
    return m;
}

// --- tests ---

test "formatInt: sinais, extremos e buffer curto" {
    const stdt = @import("std");
    var buf: [32]u8 = undefined;
    try stdt.testing.expectEqualStrings("0", buf[0..formatInt(&buf, 0)]);
    try stdt.testing.expectEqualStrings("42", buf[0..formatInt(&buf, 42)]);
    try stdt.testing.expectEqualStrings("-7", buf[0..formatInt(&buf, -7)]);
    try stdt.testing.expectEqualStrings(
        "9223372036854775807",
        buf[0..formatInt(&buf, std.math.maxInt(i64))],
    );
    try stdt.testing.expectEqualStrings(
        "-9223372036854775808",
        buf[0..formatInt(&buf, std.math.minInt(i64))],
    );
    // Buffer curto: corta no tamanho disponível.
    var tiny: [3]u8 = undefined;
    try stdt.testing.expectEqual(@as(usize, 3), formatInt(&tiny, 1234));
    try stdt.testing.expectEqualStrings("123", tiny[0..3]);
}

test "formatReal: casas, arredondamento e guardas" {
    const stdt = @import("std");
    var buf: [32]u8 = undefined;
    try stdt.testing.expectEqualStrings("1.5", buf[0..formatReal(&buf, 1.5, 1)]);
    try stdt.testing.expectEqualStrings("1.50", buf[0..formatReal(&buf, 1.5, 2)]);
    try stdt.testing.expectEqualStrings("2", buf[0..formatReal(&buf, 2.0, 0)]);
    try stdt.testing.expectEqualStrings("-0.25", buf[0..formatReal(&buf, -0.25, 2)]);
    try stdt.testing.expectEqualStrings("0.13", buf[0..formatReal(&buf, 0.125, 2)]);
    // Arredonda e propaga o transporte.
    try stdt.testing.expectEqualStrings("1.0", buf[0..formatReal(&buf, 0.96, 1)]);
    try stdt.testing.expectEqualStrings("10.00", buf[0..formatReal(&buf, 9.999, 2)]);
    // Zero negativo não recebe sinal.
    try stdt.testing.expectEqualStrings("0.0", buf[0..formatReal(&buf, -0.0, 1)]);
    // Guardas.
    try stdt.testing.expectEqual(@as(usize, 0), formatReal(&buf, std.math.nan(f32), 2));
    try stdt.testing.expectEqual(@as(usize, 0), formatReal(&buf, 1.0e30, 2));
}

test "dragValue, clampToRange e toInt" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(f32, 2.5), dragValue(2, 50, 0.01));
    try stdt.testing.expectEqual(@as(f32, 2), dragValue(2, 50, std.math.nan(f32)));
    // Entrada não-finita devolve a âncora (identidade).
    try stdt.testing.expectEqual(std.math.inf(f32), dragValue(std.math.inf(f32), 1, 1));
    // Sem faixa (`min >= max`) nada é clampado.
    try stdt.testing.expectEqual(@as(f32, 5), clampToRange(5, null));
    try stdt.testing.expectEqual(@as(f32, 5), clampToRange(5, .{ .min = 1, .max = 1 }));
    try stdt.testing.expectEqual(@as(f32, 1), clampToRange(0.5, .{ .min = 1, .max = 3 }));
    try stdt.testing.expectEqual(@as(f32, 3), clampToRange(9, .{ .min = 1, .max = 3 }));
    try stdt.testing.expectEqual(@as(f32, 2), clampToRange(2, .{ .min = 1, .max = 3 }));
    try stdt.testing.expectEqual(@as(i64, 3), toInt(2.5));
    try stdt.testing.expectEqual(@as(i64, -3), toInt(-2.5));
    try stdt.testing.expectEqual(@as(i64, 0), toInt(std.math.inf(f32)));
    // Satura no intervalo representável (o valor exato depende do `f32`).
    try stdt.testing.expect(toInt(1.0e30) > 8_900_000_000_000_000_000);
    try stdt.testing.expect(toInt(-1.0e30) < -8_900_000_000_000_000_000);
}

test "rowAtY, contentHeight e maxScroll" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(?usize, 0), rowAtY(0, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, 0), rowAtY(19.9, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, 2), rowAtY(45, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, null), rowAtY(60, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, null), rowAtY(-0.5, 20, 3));
    try stdt.testing.expectEqual(@as(?usize, null), rowAtY(10, 0, 3));
    try stdt.testing.expectEqual(@as(?usize, null), rowAtY(10, 20, 0));
    try stdt.testing.expectEqual(@as(f32, 60), contentHeight(3, 20));
    try stdt.testing.expectEqual(@as(f32, 0), contentHeight(3, 0));
    try stdt.testing.expectEqual(@as(f32, 20), maxScroll(3, 40, 20));
    try stdt.testing.expectEqual(@as(f32, 0), maxScroll(3, 60, 20));
    try stdt.testing.expectEqual(@as(f32, 0), maxScroll(3, -1, 20));
}

test "cycleIndex: wrap nos dois sentidos e normalização" {
    const stdt = @import("std");
    try stdt.testing.expectEqual(@as(?u32, 1), cycleIndex(0, 3, 1));
    try stdt.testing.expectEqual(@as(?u32, 0), cycleIndex(2, 3, 1));
    try stdt.testing.expectEqual(@as(?u32, 2), cycleIndex(0, 3, -1));
    try stdt.testing.expectEqual(@as(?u32, 1), cycleIndex(4, 3, 0)); // 4 mod 3
    try stdt.testing.expectEqual(@as(?u32, null), cycleIndex(0, 0, 1));
}

test "Property: kind, effectiveStep/Decimals e validade" {
    const stdt = @import("std");
    var b = false;
    var i: i64 = 0;
    var r: f32 = 0;
    var idx: u32 = 1;
    const opts = [_][]const u8{ "a", "b" };

    const pb = Property{ .value = .{ .boolean = &b } };
    try stdt.testing.expectEqual(Kind.boolean, pb.kind());
    try stdt.testing.expect(pb.isValid());
    const pi = Property{ .value = .{ .integer = &i } };
    try stdt.testing.expectEqual(@as(f32, 1), pi.effectiveStep(0.01));
    const pr = Property{ .value = .{ .real = &r }, .step = 0.5, .decimals = 9 };
    try stdt.testing.expectEqual(@as(f32, 0.5), pr.effectiveStep(0.01));
    try stdt.testing.expectEqual(@as(u32, 6), pr.effectiveDecimals(3)); // clampado
    try stdt.testing.expect(!pr.isValid()); // decimals > max_decimals
    const pr0 = Property{ .value = .{ .real = &r }, .decimals = 0 };
    try stdt.testing.expectEqual(@as(u32, 0), pr0.effectiveDecimals(3));
    const pr_def = Property{ .value = .{ .real = &r } };
    try stdt.testing.expectEqual(@as(u32, 3), pr_def.effectiveDecimals(3));
    const pc = Property{ .value = .{ .choice = .{ .index = &idx, .options = &opts } } };
    try stdt.testing.expectEqual(Kind.choice, pc.kind());
    try stdt.testing.expect(pc.isValid());
    // Escolha sem opções é inválida; passo <= 0 também.
    const pc_empty = Property{ .value = .{ .choice = .{ .index = &idx, .options = &.{} } } };
    try stdt.testing.expect(!pc_empty.isValid());
    const p_step0 = Property{ .value = .{ .real = &r }, .step = 0 };
    try stdt.testing.expect(!p_step0.isValid());
    const p_nan = Property{ .value = .{ .real = &r }, .range = .{ .min = std.math.nan(f32), .max = 1 } };
    try stdt.testing.expect(!p_nan.isValid());
    const pt = Property{ .value = .{ .text = "x" } };
    try stdt.testing.expectEqual(Kind.text, pt.kind());
}
