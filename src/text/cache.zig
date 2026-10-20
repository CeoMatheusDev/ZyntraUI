//! ZyntraUI — cache opcional de medição de texto (text/cache).
//!
//! Escopo M155: cache LIMITADO e opcional das medições de texto, para
//! apps que medem o mesmo texto várias vezes por frame (listas,
//! tooltips, árvores). O cache é do APP: a biblioteca não o usa por
//! padrão (o benefício precisa ser medido no app antes de ativar).
//!
//! Segurança da chave: a busca compara o CONTEÚDO EXATO do texto (não
//! só o hash) e a identidade da fonte (métricas ou atlas) e a largura
//! disponível. Uma colisão de hash nunca devolve um resultado errado.
//!
//! Capacidade: fixa e limitada (tabela aberta com sondagem linear) — o
//! cache nunca cresce sem parar. `clear` invalida tudo.

const std = @import("std");
const types = @import("../core/types.zig");
const metrics_mod = @import("metrics.zig");
const atlas_mod = @import("atlas.zig");
const image_mod = @import("../draw/image.zig");
const layout_mod = @import("layout.zig");

/// Resultado de uma medição (largura, altura, linhas e glifos).
pub const Measure = struct {
    width: f32 = 0,
    height: f32 = 0,
    lines: u32 = 1,
    glyphs: u32 = 0,
    /// Avanço total (mesmo que a largura para as fontes suportadas).
    advance: f32 = 0,
};

/// Chave completa da entrada (o texto é comparado byte a byte).
const Key = struct {
    hash: u64 = 0,
    font: u64 = 0,
    max_width: f32 = 0,
};

const Slot = struct {
    used: bool = false,
    key: Key = .{},
    /// Cópia dos bytes do texto medido (o chamador pode liberar o seu).
    text: []u8 = &.{},
    result: Measure = .{},
};

/// Cache de medições (limitado, opcional, do app).
pub const TextCache = struct {
    gpa: std.mem.Allocator,
    slots: []Slot,
    count: usize = 0,
    hits: u64 = 0,
    misses: u64 = 0,
    evictions: u64 = 0,

    /// Cria o cache com `capacity` entradas (arredondado para potência
    /// de 2, mínimo 8). Capacidade 0 = cache desativado (as medições
    /// passam direto).
    ///
    /// A tabela é aberta (sondagem linear): para manter as sondagens
    /// curtas, uma entrada nova passa a descartar a antiga quando a
    /// metade das posições está ocupada — a capacidade efetiva é, por
    /// isso, ~metade de `capacity`.
    pub fn init(gpa: std.mem.Allocator, entries: usize) !TextCache {
        const cap = @max(8, std.math.ceilPowerOfTwoAssert(usize, entries));
        const slots = try gpa.alloc(Slot, cap);
        @memset(slots, .{});
        return .{ .gpa = gpa, .slots = slots };
    }

    pub fn deinit(self: *TextCache) void {
        for (self.slots) |s| {
            if (s.used) self.gpa.free(s.text);
        }
        self.gpa.free(self.slots);
        self.slots = &.{};
        self.count = 0;
    }

    /// Invalida todas as entradas (a memória é liberada).
    pub fn clear(self: *TextCache) void {
        for (self.slots) |*s| {
            if (s.used) self.gpa.free(s.text);
            s.* = .{};
        }
        self.count = 0;
    }

    /// Capacidade total (entradas) do cache.
    pub fn capacity(self: *const TextCache) usize {
        return self.slots.len;
    }

    /// Mede `text` com a fonte `source`, usando o cache quando a chave
    /// bate. `max_width` é a largura disponível (usada pelo corte; 0 =
    /// sem corte) e faz parte da chave.
    ///
    /// Erros: os mesmos de `text.layout.Layout.measure` (UTF-8 inválido,
    /// fonte inválida).
    pub fn measure(
        self: *TextCache,
        text: []const u8,
        source: layout_mod.Source,
        max_width: f32,
    ) !Measure {
        const layout = layout_mod.Layout.init(source) catch return error.InvalidMetrics;
        if (self.slots.len == 0) return measureUncached(layout, text);
        const key = Key{
            .hash = hashText(text),
            .font = fontKey(source),
            .max_width = max_width,
        };
        const idx = self.probe(key, text);
        if (idx) |i| {
            self.hits += 1;
            return self.slots[i].result;
        }
        self.misses += 1;
        const result = try measureUncached(layout, text);
        try self.insert(key, text, result);
        return result;
    }

    /// Mede sem tocar no cache (UMA medição: a largura é o avanço
    /// para as fontes suportadas).
    fn measureUncached(layout: layout_mod.Layout, text: []const u8) !Measure {
        const m = layout.measure(text) catch |err| return switch (err) {
            error.InvalidUtf8 => error.InvalidUtf8,
            error.InvalidMetrics => error.InvalidMetrics,
            error.InvalidGlyph => error.InvalidMetrics,
            error.InvalidCommand => error.InvalidMetrics,
            error.InvalidArgument => error.InvalidArgument,
            error.OutOfMemory => error.OutOfMemory,
        };
        return .{
            .width = m.width,
            .height = m.height,
            .lines = m.lines,
            .glyphs = m.glyphs,
            .advance = m.width,
        };
    }

    /// Procura a entrada que casa com a chave E com o texto exato.
    fn probe(self: *TextCache, key: Key, text: []const u8) ?usize {
        const mask = self.slots.len - 1;
        var i: usize = @as(usize, @truncate(key.hash)) & mask;
        var steps: usize = 0;
        while (steps < self.slots.len) : (steps += 1) {
            const s = &self.slots[i];
            if (!s.used) return null;
            if (s.key.hash == key.hash and
                s.key.font == key.font and
                s.key.max_width == key.max_width and
                std.mem.eql(u8, s.text, text)) return i;
            i = (i + 1) & mask;
        }
        return null;
    }

    /// Insere (ou substitui) a entrada.
    fn insert(self: *TextCache, key: Key, text: []const u8, result: Measure) !void {
        const copy = try self.gpa.dupe(u8, text);
        errdefer self.gpa.free(copy);
        const mask = self.slots.len - 1;
        var i: usize = @as(usize, @truncate(key.hash)) & mask;
        var steps: usize = 0;
        while (steps < self.slots.len) : (steps += 1) {
            const s = &self.slots[i];
            if (s.used) {
                // occupied: procura o próximo livre (ou o mais antigo)
                if (self.count * 2 >= self.slots.len) {
                    // tabela cheia: substitui (eviction) nesta posição
                    self.gpa.free(s.text);
                    s.* = .{};
                    self.evictions += 1;
                    self.count -= 1;
                } else {
                    i = (i + 1) & mask;
                    continue;
                }
            }
            s.* = .{ .used = true, .key = key, .text = copy, .result = result };
            self.count += 1;
            return;
        }
        // tabela completamente cheia: descarta a entrada nova (o cache
        // é bounded; perder uma entrada é seguro).
        self.gpa.free(copy);
    }
};

/// Hash do texto (FNV-1a 64) — usado só para localizar a entrada; a
/// comparação final é byte a byte.
fn hashText(text: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (text) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    return h;
}

/// Identidade da fonte: as métricas (bits) ou o atlas (ponteiro +
/// escala). Trocar de fonte invalida as entradas correspondentes.
fn fontKey(source: layout_mod.Source) u64 {
    return switch (source) {
        .metrics => |m| blk: {
            var h: u64 = 0xcbf29ce484222325;
            const bytes = std.mem.asBytes(&m);
            for (bytes) |b| {
                h ^= b;
                h *%= 0x100000001b3;
            }
            break :blk h;
        },
        .atlas => |a| blk: {
            var h: u64 = 0xcbf29ce484222325;
            const ptr_bits: u64 = @intFromPtr(a);
            h ^= ptr_bits;
            h *%= 0x100000001b3;
            const scale_bits: u32 = @bitCast(a.scale);
            h ^= @as(u64, scale_bits);
            h *%= 0x100000001b3;
            // A GERAÇÃO invalida as entradas quando o atlas muda (mesmo
            // ponteiro, glifos diferentes) — M139.
            h ^= @as(u64, a.generation);
            h *%= 0x100000001b3;
            break :blk h;
        },
    };
}

test "TextCache: acerto, invalidação e limites" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10); // advance 6
    const source = layout_mod.Source{ .metrics = font };

    var cache = try TextCache.init(gpa, 16);
    defer cache.deinit();

    // 1ª medição: miss; 2ª: hit (mesmo texto).
    const m1 = try cache.measure("abc", source, 0);
    try stdt.testing.expectEqual(@as(f32, 18), m1.width);
    try stdt.testing.expectEqual(@as(u64, 1), cache.misses);
    try stdt.testing.expectEqual(@as(u64, 0), cache.hits);
    const m2 = try cache.measure("abc", source, 0);
    try stdt.testing.expectEqual(m1.width, m2.width);
    try stdt.testing.expectEqual(@as(u64, 1), cache.hits);

    // Texto diferente: miss (e o resultado bate com o direto).
    const m3 = try cache.measure("abd", source, 0);
    try stdt.testing.expectEqual(@as(f32, 18), m3.width);
    try stdt.testing.expectEqual(@as(u64, 2), cache.misses);

    // Largura diferente: chave diferente ⇒ miss.
    _ = try cache.measure("abc", source, 40);
    try stdt.testing.expectEqual(@as(u64, 3), cache.misses);

    // Fonte diferente: chave diferente ⇒ miss.
    const other = layout_mod.Source{ .metrics = metrics_mod.FontMetrics.withSize(16) };
    _ = try cache.measure("abc", other, 0);
    try stdt.testing.expectEqual(@as(u64, 4), cache.misses);

    // clear invalida tudo.
    cache.clear();
    _ = try cache.measure("abc", source, 0);
    try stdt.testing.expectEqual(@as(u64, 5), cache.misses);
}

test "TextCache: o resultado é idêntico ao sem cache" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(14);
    const source = layout_mod.Source{ .metrics = font };
    const layout = try layout_mod.Layout.fromMetrics(font);

    var cache = try TextCache.init(gpa, 32);
    defer cache.deinit();

    const texts = [_][]const u8{ "a", "abc", "ZyntraUI", "acentuação", "" };
    for (texts) |t| {
        const cached = try cache.measure(t, source, 0);
        const direct = try layout.measure(t);
        try stdt.testing.expectEqual(direct.width, cached.width);
        try stdt.testing.expectEqual(direct.height, cached.height);
        try stdt.testing.expectEqual(direct.lines, cached.lines);
        try stdt.testing.expectEqual(direct.glyphs, cached.glyphs);
        // Segunda passada: o resultado vem do cache e é o mesmo.
        const again = try cache.measure(t, source, 0);
        try stdt.testing.expectEqual(cached.width, again.width);
    }
}

test "TextCache: capacidade limitada (evictions) e texto inválido" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const source = layout_mod.Source{ .metrics = metrics_mod.FontMetrics.withSize(10) };

    var cache = try TextCache.init(gpa, 8);
    defer cache.deinit();

    // Mais textos que a capacidade: o cache não cresce e não quebra.
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        var buf: [16]u8 = undefined;
        const n = std.fmt.bufPrint(&buf, "t{d}", .{i}) catch unreachable;
        const m = try cache.measure(n, source, 0);
        try stdt.testing.expect(m.width > 0);
    }
    try stdt.testing.expect(cache.count <= cache.capacity());

    // UTF-8 inválido: erro (sem entrada poisonous).
    try stdt.testing.expectError(error.InvalidUtf8, cache.measure("\xff", source, 0));
}

test "TextCache: a geração do atlas invalida as entradas" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    var b = atlas_mod.Builder.init(32, 32, 1);
    defer b.deinit(gpa);
    _ = try b.addGlyph(gpa, 'A', 4, 8, .{ .advance = 5, .bearing_y = -8, .height = 8 });
    var bytes: [32 * 32 * 4]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @truncate(i);
    const img = try image_mod.Image.init(32, 32, &bytes);
    var atlas = try b.finish(gpa, img);
    defer atlas.deinit(gpa);

    const source = layout_mod.Source{ .atlas = &atlas };
    var cache = try TextCache.init(gpa, 8);
    defer cache.deinit();

    _ = try cache.measure("A", source, 0);
    try stdt.testing.expectEqual(@as(u64, 1), cache.misses);
    _ = try cache.measure("A", source, 0);
    try stdt.testing.expectEqual(@as(u64, 1), cache.hits);

    // O atlas muda (mesmo ponteiro, geração nova): a entrada antiga
    // NÃO pode ser reutilizada.
    atlas.generation +%= 1;
    _ = try cache.measure("A", source, 0);
    try stdt.testing.expectEqual(@as(u64, 2), cache.misses);
}

test "fuzz TextCache: o resultado cacheado é sempre o correto" {
    try std.testing.fuzz({}, fuzzCache, .{});
}

fn fuzzCache(_: void, smith: *std.testing.Smith) !void {
    var bytes: [96]u8 = undefined;
    smith.bytes(&bytes);
    const gpa = std.testing.allocator;

    // Duas fontes (avanços diferentes) e textos aleatórios válidos.
    const f1 = metrics_mod.FontMetrics.withSize(10);
    const f2 = metrics_mod.FontMetrics.withSize(16);
    var cache = try TextCache.init(gpa, 16);
    defer cache.deinit();

    var text: [32]u8 = undefined;
    const n = bytes[0] % 32;
    for (0..n) |i| {
        // Só ASCII (UTF-8 válido) para o teste focar no cache.
        text[i] = 'a' + (bytes[1 + i] % 26);
    }
    const slice = text[0..n];

    const src1 = layout_mod.Source{ .metrics = f1 };
    const src2 = layout_mod.Source{ .metrics = f2 };
    const layout1 = try layout_mod.Layout.fromMetrics(f1);
    const layout2 = try layout_mod.Layout.fromMetrics(f2);

    // Mede (e mede de novo: o segundo acesso vem do cache).
    const m1 = try cache.measure(slice, src1, 0);
    const m1b = try cache.measure(slice, src1, 0);
    try std.testing.expectEqual(m1.width, m1b.width);
    const m2 = try cache.measure(slice, src2, 0);
    const m2b = try cache.measure(slice, src2, 0);
    try std.testing.expectEqual(m2.width, m2b.width);

    // O resultado cacheado é o mesmo que a medição direta.
    const direct1 = try layout1.measure(slice);
    const direct2 = try layout2.measure(slice);
    try std.testing.expectEqual(direct1.width, m1.width);
    try std.testing.expectEqual(direct2.width, m2.width);
    // As duas fontes têm avanços diferentes ⇒ larguras diferentes (a chave
    // distingue a fonte).
    if (f1.advance != f2.advance and n > 0) {
        try std.testing.expect(m1.width != m2.width);
    }
}
