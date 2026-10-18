//! ZyntraUI — comandos de desenho (draw/commands).
//!
//! Contrato renderer-independente:
//! - Produtores (widgets) apenas enfileiram `DrawCommand` em pixels
//!   lógicos; nenhum backend é referenciado aqui.
//! - Consumidores (renderers externos) iteram `DrawList.items()` em
//!   ordem e executam batching próprio.
//! - Coordenadas `NaN/Inf` são rejeitadas (`InvalidCommand`).
//! Ownership: `DrawList` detém o buffer; alocador do chamador.
//! `clear` no início do frame invalida slices anteriores.
//! ABI C: payloads `extern struct`, tags `u8`; projeção plana em M5.

const std = @import("std");
const types = @import("../core/types.zig");
const metrics_mod = @import("../text/metrics.zig");

/// Comando único de desenho.
pub const DrawCommand = union(enum) {
    /// Limpa o viewport com cor sólida (normalmente primeiro).
    clear: extern struct { color: types.Color },
    rect_filled: extern struct {
        rect: types.Rect,
        color: types.Color,
    },
    rect_outline: extern struct {
        rect: types.Rect,
        color: types.Color,
        thickness: f32,
    },
    line: extern struct {
        p0: types.Vec2,
        p1: types.Vec2,
        color: types.Color,
        thickness: f32,
    },
    circle_filled: extern struct {
        center: types.Vec2,
        radius: f32,
        color: types.Color,
    },
    /// Define clip retangular (scissor) para comandos seguintes.
    /// `null_rect=true` remove o clip.
    clip: extern struct {
        rect: types.Rect,
        null_rect: bool,
    },
    /// Texto para o backend rasterizar. Os bytes vivem na arena da
    /// `DrawList` (`text_bytes`); `start/len` são offsets (estáveis
    /// mesmo se a arena realocar). `width` é a medida fallback gravada
    /// no push (backends com shaping próprio podem diferir).
    text: extern struct {
        pos: types.Vec2,
        color: types.Color,
        size: f32,
        width: f32,
        start: u32,
        len: u32,
    },
    /// Retângulo de cantos arredondados uniformes (`radius` em px,
    /// clampado a `min(w,h)/2` pelo backend). O backend de referência
    /// usa distância assinada (SDF) com cobertura fracionária — bordas
    /// anti-serrilhadas. `radius == 0` degenera num retângulo com
    /// bordas AA (para bordas exatas use `rect_filled`).
    rect_rounded: extern struct {
        rect: types.Rect,
        radius: f32,
        color: types.Color,
    },
    /// Preenchimento em gradiente LINEAR: `color0` em `p0`, `color1` em
    /// `p1` (projeção do pixel no eixo `p0→p1`, clampada a [0,1]).
    /// `p0 == p1` degenera em `color0` sólido. O gradiente fica contido
    /// em `rect` (clamp nas bordas).
    rect_gradient: extern struct {
        rect: types.Rect,
        p0: types.Vec2,
        p1: types.Vec2,
        color0: types.Color,
        color1: types.Color,
    },
    /// Sombra projetada de um retângulo de cantos arredondados: a
    /// silhueta `rect` é deslocada por `offset` e atenuada em `blur` px
    /// (falloff LINEAR centrado na borda — aproximação barata de blur via
    /// SDF, sem passe offscreen). Não desenha a forma: desenhe-a por cima.
    rect_shadow: extern struct {
        rect: types.Rect,
        radius: f32,
        offset: types.Vec2,
        blur: f32,
        color: types.Color,
    },
    /// Desfoca (box blur separável) o que JÁ foi desenhado dentro de
    /// `rect` — "backdrop blur" (vidro fosco). Ordem importa: só afeta
    /// comandos ANTERIORES. `radius` em px (arredondado; < 0.5 = no-op).
    /// Os canais RGBA são desfocados independentemente (não
    /// premultiplicado).
    blur: extern struct {
        rect: types.Rect,
        radius: f32,
    },

    fn finite(v: f32) bool {
        return std.math.isFinite(v);
    }

    pub fn isValid(self: DrawCommand) bool {
        switch (self) {
            .clear => return true,
            .rect_filled => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0;
            },
            .rect_outline => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.thickness) and c.thickness > 0;
            },
            .line => |c| {
                return finite(c.p0.x) and finite(c.p0.y) and
                    finite(c.p1.x) and finite(c.p1.y) and
                    finite(c.thickness) and c.thickness > 0;
            },
            .circle_filled => |c| {
                return finite(c.center.x) and finite(c.center.y) and
                    finite(c.radius) and c.radius >= 0;
            },
            .clip => |c| {
                if (c.null_rect) return true;
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0;
            },
            .text => |c| {
                return finite(c.pos.x) and finite(c.pos.y) and
                    finite(c.size) and c.size > 0 and
                    finite(c.width) and c.width >= 0;
            },
            .rect_rounded => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.radius) and c.radius >= 0;
            },
            .rect_gradient => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.p0.x) and finite(c.p0.y) and
                    finite(c.p1.x) and finite(c.p1.y);
            },
            .rect_shadow => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.radius) and c.radius >= 0 and
                    finite(c.offset.x) and finite(c.offset.y) and
                    finite(c.blur) and c.blur >= 0;
            },
            .blur => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.radius) and c.radius >= 0;
            },
        }
    }

    /// Cópia de `self` deslocada por (`dx`,`dy`) no espaço do frame: move
    /// toda a geometria (rects, pontos, centros, posição de texto e clip),
    /// preservando cores, espessuras e raios. `.clear` não tem geometria;
    /// `.rect_shadow` desloca o rect mas mantém `offset` (é relativo);
    /// `.clip` com `null_rect` mantém o rect (ignorado).
    ///
    /// Em `.text` só `pos` muda: `start`/`len` continuam válidos na MESMA
    /// `DrawList` de origem. Para outra lista use
    /// `DrawList.translateInto`, que remonta os bytes e reescreve os
    /// offsets.
    pub fn translated(self: DrawCommand, dx: f32, dy: f32) DrawCommand {
        var out = self;
        switch (out) {
            .clear => {},
            .clip => |*c| {
                if (!c.null_rect) moveRect(&c.rect, dx, dy);
            },
            .rect_filled => |*c| moveRect(&c.rect, dx, dy),
            .rect_outline => |*c| moveRect(&c.rect, dx, dy),
            .rect_rounded => |*c| moveRect(&c.rect, dx, dy),
            .rect_gradient => |*c| {
                moveRect(&c.rect, dx, dy);
                moveVec(&c.p0, dx, dy);
                moveVec(&c.p1, dx, dy);
            },
            .rect_shadow => |*c| moveRect(&c.rect, dx, dy),
            .blur => |*c| moveRect(&c.rect, dx, dy),
            .line => |*c| {
                moveVec(&c.p0, dx, dy);
                moveVec(&c.p1, dx, dy);
            },
            .circle_filled => |*c| moveVec(&c.center, dx, dy),
            .text => |*c| moveVec(&c.pos, dx, dy),
        }
        return out;
    }
};

fn moveRect(r: *types.Rect, dx: f32, dy: f32) void {
    r.x += dx;
    r.y += dy;
}

fn moveVec(p: *types.Vec2, dx: f32, dy: f32) void {
    p.x += dx;
    p.y += dy;
}

/// Lista de desenho do frame (bump por frame + retenção de capacidade).
/// `text_bytes` é a arena dos textos de comandos `.text`; comandos
/// guardam offsets, nunca slices (seguro contra realocação).
pub const DrawList = struct {
    list: std.ArrayList(DrawCommand),
    text_bytes: std.ArrayList(u8) = .empty,

    const Self = @This();

    pub fn initEmpty() Self {
        return .{ .list = .empty, .text_bytes = .empty };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.list.deinit(gpa);
        self.text_bytes.deinit(gpa);
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.list.clearRetainingCapacity();
        self.text_bytes.clearRetainingCapacity();
    }

    pub fn len(self: *const Self) usize {
        return self.list.items.len;
    }

    pub fn items(self: *const Self) []const DrawCommand {
        return self.list.items;
    }

    /// Resolve os bytes UTF-8 de um comando `.text`. Retorna vazio se o
    /// comando não for texto ou os offsets forem inconsistentes
    /// (defensivo para backends; nunca crasha).
    pub fn textOf(self: *const Self, cmd: DrawCommand) []const u8 {
        const t = switch (cmd) {
            .text => |p| p,
            else => return &.{},
        };
        const start: usize = t.start;
        const end: usize = start + t.len;
        const buf = self.text_bytes.items;
        if (start > end or end > buf.len) return &.{};
        return buf[start..end];
    }

    pub fn push(self: *Self, gpa: std.mem.Allocator, cmd: DrawCommand) !void {
        if (!cmd.isValid()) return error.InvalidCommand;
        try self.list.append(gpa, cmd);
    }

    /// Reconstrói `out` como esta lista deslocada por (`dx`,`dy`): limpa
    /// `out` (retendo capacidade), desloca cada comando (ver
    /// `DrawCommand.translated`) e remonta os bytes de texto, reescrevendo
    /// os offsets — a lista resultante é autocontida em `out`. `out` deve
    /// ser OUTRA lista (limpar `self` destruiria a origem).
    pub fn translateInto(
        self: *const Self,
        gpa: std.mem.Allocator,
        out: *Self,
        dx: f32,
        dy: f32,
    ) !void {
        out.clearRetainingCapacity();
        for (self.list.items) |cmd| {
            if (cmd != .text) {
                try out.push(gpa, cmd.translated(dx, dy));
                continue;
            }
            const bytes = self.textOf(cmd);
            const start: u32 = @intCast(out.text_bytes.items.len);
            try out.text_bytes.appendSlice(gpa, bytes);
            var copy = cmd.translated(dx, dy);
            copy.text.start = start;
            copy.text.len = @intCast(bytes.len);
            try out.push(gpa, copy);
        }
    }

    pub fn clear(self: *Self, gpa: std.mem.Allocator, color: types.Color) !void {
        try self.push(gpa, .{ .clear = .{ .color = color } });
    }

    /// Define o clip retangular (scissor) para os comandos seguintes;
    /// `null` remove o clip. Vale até o próximo `clip`/`clear` da lista.
    pub fn clip(self: *Self, gpa: std.mem.Allocator, rect: ?types.Rect) !void {
        try self.push(gpa, .{ .clip = .{
            .rect = rect orelse .{},
            .null_rect = rect == null,
        } });
    }

    pub fn rectFilled(self: *Self, gpa: std.mem.Allocator, rect: types.Rect, color: types.Color) !void {
        try self.push(gpa, .{ .rect_filled = .{ .rect = rect, .color = color } });
    }

    pub fn rectOutline(self: *Self, gpa: std.mem.Allocator, rect: types.Rect, color: types.Color, thickness: f32) !void {
        try self.push(gpa, .{ .rect_outline = .{ .rect = rect, .color = color, .thickness = thickness } });
    }

    pub fn line(self: *Self, gpa: std.mem.Allocator, p0: types.Vec2, p1: types.Vec2, color: types.Color, thickness: f32) !void {
        try self.push(gpa, .{ .line = .{ .p0 = p0, .p1 = p1, .color = color, .thickness = thickness } });
    }

    pub fn circleFilled(self: *Self, gpa: std.mem.Allocator, center: types.Vec2, radius: f32, color: types.Color) !void {
        try self.push(gpa, .{ .circle_filled = .{ .center = center, .color = color, .radius = radius } });
    }

    /// Retângulo de cantos arredondados (bordas AA no backend de referência).
    pub fn rectRounded(self: *Self, gpa: std.mem.Allocator, rect: types.Rect, radius: f32, color: types.Color) !void {
        try self.push(gpa, .{ .rect_rounded = .{ .rect = rect, .radius = radius, .color = color } });
    }

    /// Gradiente linear `color0` (em `p0`) → `color1` (em `p1`) dentro de `rect`.
    pub fn rectGradient(
        self: *Self,
        gpa: std.mem.Allocator,
        rect: types.Rect,
        p0: types.Vec2,
        p1: types.Vec2,
        color0: types.Color,
        color1: types.Color,
    ) !void {
        try self.push(gpa, .{ .rect_gradient = .{
            .rect = rect,
            .p0 = p0,
            .p1 = p1,
            .color0 = color0,
            .color1 = color1,
        } });
    }

    /// Sombra projetada de um retângulo arredondado (`off` desloca, `blur` atenua).
    pub fn rectShadow(
        self: *Self,
        gpa: std.mem.Allocator,
        rect: types.Rect,
        radius: f32,
        off: types.Vec2,
        blur: f32,
        color: types.Color,
    ) !void {
        try self.push(gpa, .{ .rect_shadow = .{
            .rect = rect,
            .radius = radius,
            .offset = off,
            .blur = blur,
            .color = color,
        } });
    }

    /// Desfoca (box blur) o conteúdo desenhado antes, dentro de `rect`.
    pub fn backdropBlur(self: *Self, gpa: std.mem.Allocator, rect: types.Rect, radius: f32) !void {
        try self.push(gpa, .{ .blur = .{ .rect = rect, .radius = radius } });
    }

    /// Enfileira texto copiando os bytes para a arena interna.
    /// Valida UTF-8 no push (backend nunca recebe texto malformado).
    /// Textos que não couberem em offsets `u32` retornam `OutOfMemory`.
    pub fn pushText(
        self: *Self,
        gpa: std.mem.Allocator,
        pos: types.Vec2,
        color: types.Color,
        font: metrics_mod.FontMetrics,
        text: []const u8,
    ) !void {
        if (!font.isValid()) return error.InvalidMetrics;
        const m = try metrics_mod.measure(text, font);
        const start = self.text_bytes.items.len;
        if (start > std.math.maxInt(u32) or text.len > std.math.maxInt(u32) - start) {
            return error.OutOfMemory;
        }
        try self.text_bytes.appendSlice(gpa, text);
        try self.push(gpa, .{ .text = .{
            .pos = pos,
            .color = color,
            .size = font.size,
            .width = m.width,
            .start = @intCast(start),
            .len = @intCast(text.len),
        } });
    }
};

test "DrawList helpers + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    try dl.clear(gpa, types.Color.rgb(10, 20, 30));
    try dl.rectFilled(gpa, types.Rect.init(0, 0, 10, 10), types.Color.rgb(255, 0, 0));
    try dl.rectOutline(gpa, types.Rect.init(0, 0, 10, 10), types.Color.rgb(0, 255, 0), 1.0);
    try dl.line(gpa, types.Vec2.init(0, 0), types.Vec2.init(5, 5), types.Color.rgb(0, 0, 255), 2.0);
    try dl.circleFilled(gpa, types.Vec2.init(3, 3), 4.0, types.Color.rgb(255, 255, 0));
    try dl.rectRounded(gpa, types.Rect.init(0, 0, 10, 10), 3.0, types.Color.rgb(10, 20, 30));
    try dl.clip(gpa, types.Rect.init(0, 0, 10, 10));
    try dl.clip(gpa, null);
    try stdt.testing.expectEqual(@as(usize, 8), dl.len());
    try stdt.testing.expect(dl.items()[5].isValid());
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 10, 10), dl.items()[6].clip.rect);
    try stdt.testing.expect(!dl.items()[6].clip.null_rect);
    try stdt.testing.expect(dl.items()[7].clip.null_rect);

    // Inválidos:
    try stdt.testing.expectError(error.InvalidCommand, dl.rectFilled(
        gpa,
        types.Rect.init(0, 0, -1, 5),
        types.Color.rgb(0, 0, 0),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.rectRounded(
        gpa,
        types.Rect.init(0, 0, 10, 10),
        -1.0,
        types.Color.rgb(0, 0, 0),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.rectRounded(
        gpa,
        types.Rect.init(0, 0, 10, 10),
        std.math.nan(f32),
        types.Color.rgb(0, 0, 0),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.line(
        gpa,
        types.Vec2.init(std.math.nan(f32), 0),
        types.Vec2.init(0, 0),
        types.Color.rgb(0, 0, 0),
        1.0,
    ));
    const cap = dl.list.capacity;
    dl.clearRetainingCapacity();
    try stdt.testing.expectEqual(@as(usize, 0), dl.len());
    try stdt.testing.expect(dl.list.capacity >= cap);
}

test "DrawList rectGradient + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    try dl.rectGradient(
        gpa,
        types.Rect.init(0, 0, 4, 4),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    try stdt.testing.expect(dl.items()[0].isValid());

    // Eixo não-finito é rejeitado sem enfileirar.
    try stdt.testing.expectError(error.InvalidCommand, dl.rectGradient(
        gpa,
        types.Rect.init(0, 0, 4, 4),
        types.Vec2.init(std.math.nan(f32), 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.rectGradient(
        gpa,
        types.Rect.init(0, 0, -1, 4),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    ));
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
}

test "DrawList rectShadow + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    try dl.rectShadow(
        gpa,
        types.Rect.init(0, 0, 10, 10),
        4,
        types.Vec2.init(2, 3),
        6,
        .{ .r = 0, .g = 0, .b = 0, .a = 128 },
    );
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    try stdt.testing.expect(dl.items()[0].isValid());

    try stdt.testing.expectError(error.InvalidCommand, dl.rectShadow(
        gpa,
        types.Rect.init(0, 0, 10, 10),
        4,
        types.Vec2.init(0, 0),
        -1,
        types.Color.rgb(0, 0, 0),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.rectShadow(
        gpa,
        types.Rect.init(0, 0, 10, 10),
        4,
        types.Vec2.init(std.math.inf(f32), 0),
        1,
        types.Color.rgb(0, 0, 0),
    ));
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
}

test "DrawList backdropBlur + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    try dl.backdropBlur(gpa, types.Rect.init(0, 0, 20, 20), 8);
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    try stdt.testing.expect(dl.items()[0].isValid());

    try stdt.testing.expectError(error.InvalidCommand, dl.backdropBlur(
        gpa,
        types.Rect.init(0, 0, 20, 20),
        -1,
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.backdropBlur(
        gpa,
        types.Rect.init(0, 0, 20, std.math.nan(f32)),
        2,
    ));
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
}

test "DrawList pushText copia, resolve e valida" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);
    const font = metrics_mod.FontMetrics.withSize(10); // advance=6

    // Buffer mutável do chamador pode morrer após o push: a lista copiou.
    var owned = try gpa.dupe(u8, "AB€");
    defer gpa.free(owned);
    try dl.pushText(gpa, types.Vec2.init(1, 2), types.Color.rgb(1, 2, 3), font, owned);
    owned[0] = 'X';
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    const cmd = dl.items()[0];
    try stdt.testing.expectEqualStrings("AB€", dl.textOf(cmd));
    try stdt.testing.expectEqual(@as(f32, 18), cmd.text.width);

    // Segundo push acumula offsets; texto vazio é no-op válido.
    try dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), font, "");
    try dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), font, "C");
    try stdt.testing.expectEqualStrings("C", dl.textOf(dl.items()[2]));
    try stdt.testing.expectEqualStrings("", dl.textOf(dl.items()[1]));

    // Não-texto e offsets absurdos retornam vazio sem crashar.
    const not_text: DrawCommand = .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } };
    try stdt.testing.expectEqualStrings("", dl.textOf(not_text));
    var forged = dl.items()[2];
    forged.text.len = std.math.maxInt(u32);
    try stdt.testing.expectEqualStrings("", dl.textOf(forged));

    // UTF-8 inválido e fonte inválida rejeitados sem enfileirar.
    const before = dl.len();
    try stdt.testing.expectError(error.InvalidUtf8, dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), font, "\xff"));
    try stdt.testing.expectError(error.InvalidMetrics, dl.pushText(gpa, types.Vec2.init(0, 0), types.Color.rgb(0, 0, 0), .{ .size = 0 }, "A"));
    try stdt.testing.expectEqual(before, dl.len());
}

test "fuzz pushText/textOf: sem crash, UTF-8 coerente, offsets contidos" {
    try std.testing.fuzz({}, fuzzPushText, .{});
}

fn fuzzPushText(_: void, smith: *std.testing.Smith) !void {
    var fb: [40]u8 = undefined;
    smith.bytes(&fb);
    const bits: [2]f32 = @bitCast(fb[0..8].*);
    const gpa = std.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);

    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    // Texto com bytes arbitrários (pode ser UTF-8 inválido).
    // n em 0..31 para fb[9..9+n] nunca exceder os 40 bytes.
    const n: usize = @as(usize, fb[8]) % 32;
    const text = fb[9 .. 9 + n];
    const pos = types.Vec2.init(bits[0], bits[1]);

    // Sem crash nunca; válido entra e resolve idêntico, inválido é
    // rejeitado sem enfileirar (contrato da M6 sob ataque).
    const before = dl.len();
    if (dl.pushText(gpa, pos, types.Color.rgb(1, 2, 3), font, text)) {
        try std.testing.expectEqual(before + 1, dl.len());
        const cmd = dl.items()[before];
        try std.testing.expectEqualStrings(text, dl.textOf(cmd));
        // Offsets dentro da arena.
        try std.testing.expect(cmd.text.start + cmd.text.len <= dl.text_bytes.items.len);
    } else |err| {
        try std.testing.expect(err == error.InvalidUtf8 or err == error.InvalidMetrics or err == error.InvalidCommand or err == error.OutOfMemory);
        try std.testing.expectEqual(before, dl.len());
    }
}

test "DrawList translateInto desloca geometria e remonta o texto" {
    const gpa = std.testing.allocator;
    const font = metrics_mod.FontMetrics.withSize(10);
    const red = types.Color.rgb(200, 10, 10);

    var src = DrawList.initEmpty();
    defer src.deinit(gpa);
    try src.clear(gpa, types.Color.rgb(1, 1, 1));
    try src.push(gpa, .{ .clip = .{ .rect = types.Rect.init(0, 0, 20, 20), .null_rect = false } });
    try src.rectFilled(gpa, types.Rect.init(0, 0, 10, 10), red);
    try src.rectOutline(gpa, types.Rect.init(1, 1, 8, 8), red, 1.5);
    try src.line(gpa, types.Vec2.init(0, 0), types.Vec2.init(4, 4), red, 2);
    try src.circleFilled(gpa, types.Vec2.init(5, 5), 2, red);
    try src.rectRounded(gpa, types.Rect.init(2, 2, 6, 6), 1, red);
    try src.rectGradient(
        gpa,
        types.Rect.init(0, 0, 8, 8),
        types.Vec2.init(0, 0),
        types.Vec2.init(0, 8),
        red,
        types.Color.rgb(10, 10, 200),
    );
    try src.rectShadow(gpa, types.Rect.init(0, 0, 8, 8), 2, types.Vec2.init(1, 2), 3, red);
    try src.backdropBlur(gpa, types.Rect.init(0, 0, 6, 6), 2);
    try src.pushText(gpa, types.Vec2.init(3, 4), red, font, "olá");
    try std.testing.expectEqual(@as(usize, 11), src.len());

    var out = DrawList.initEmpty();
    defer out.deinit(gpa);
    try src.translateInto(gpa, &out, 100, 50);

    // Um comando por origem, mesma ordem.
    try std.testing.expectEqual(src.len(), out.len());
    // `.clear` não tem geometria; `.clip` desloca o rect.
    try std.testing.expect(out.items()[0] == .clear);
    try std.testing.expectEqual(types.Rect.init(100, 50, 20, 20), out.items()[1].clip.rect);
    // Rects, pontos e centros deslocados; cores e espessuras intactas.
    try std.testing.expectEqual(types.Rect.init(100, 50, 10, 10), out.items()[2].rect_filled.rect);
    try std.testing.expectEqual(red, out.items()[2].rect_filled.color);
    try std.testing.expectEqual(@as(f32, 1.5), out.items()[3].rect_outline.thickness);
    try std.testing.expectEqual(types.Vec2.init(100, 50), out.items()[4].line.p0);
    try std.testing.expectEqual(types.Vec2.init(104, 54), out.items()[4].line.p1);
    try std.testing.expectEqual(types.Vec2.init(105, 55), out.items()[5].circle_filled.center);
    try std.testing.expectEqual(types.Rect.init(102, 52, 6, 6), out.items()[6].rect_rounded.rect);
    try std.testing.expectEqual(types.Vec2.init(100, 50), out.items()[7].rect_gradient.p0);
    try std.testing.expectEqual(types.Vec2.init(100, 58), out.items()[7].rect_gradient.p1);
    // Sombra: rect desloca, `offset` é relativo (fica).
    try std.testing.expectEqual(types.Rect.init(100, 50, 8, 8), out.items()[8].rect_shadow.rect);
    try std.testing.expectEqual(types.Vec2.init(1, 2), out.items()[8].rect_shadow.offset);
    try std.testing.expectEqual(types.Rect.init(100, 50, 6, 6), out.items()[9].blur.rect);
    // Texto: posição deslocada, bytes remontados na arena de `out`.
    const t = out.items()[10];
    try std.testing.expectEqual(types.Vec2.init(103, 54), t.text.pos);
    try std.testing.expectEqualStrings("olá", out.textOf(t));
    try std.testing.expect(t.text.start + t.text.len <= out.text_bytes.items.len);

    // Reconstruir limpa `out` (sem acumular) e retém capacidade.
    const cap = out.list.capacity;
    try src.translateInto(gpa, &out, 0, 0);
    try std.testing.expectEqual(src.len(), out.len());
    try std.testing.expect(out.list.capacity >= cap);

    // Sem deslocamento, a geometria é idêntica à origem.
    for (src.items(), out.items()) |a, b| {
        if (a == .text) {
            try std.testing.expectEqual(a.text.pos, b.text.pos);
            try std.testing.expectEqualStrings(src.textOf(a), out.textOf(b));
        } else if (a == .clear) {
            try std.testing.expect(b == .clear);
        } else {
            try std.testing.expect(std.meta.eql(a.translated(0, 0), b));
        }
    }
}
