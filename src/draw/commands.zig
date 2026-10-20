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
const image_mod = @import("image.zig");

/// Glifo de um run: região na imagem do atlas + deslocamento no run
/// (pixels lógicos). Ver `DrawCommand.glyph_run`.
pub const GlyphRef = extern struct {
    src_x: u32 = 0,
    src_y: u32 = 0,
    src_w: u32 = 0,
    src_h: u32 = 0,
    /// Deslocamento horizontal do glifo no run (px lógicos).
    dx: f32 = 0,
    /// Deslocamento vertical do glifo no run (px lógicos).
    dy: f32 = 0,
};

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
    circle_outline: extern struct {
        center: types.Vec2,
        radius: f32,
        color: types.Color,
        thickness: f32,
    },
    circle_dashed: extern struct {
        center: types.Vec2,
        radius: f32,
        color: types.Color,
        thickness: f32,
        dash_len: f32,
        gap_len: f32,
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
    /// Run de glifos de um atlas: N glifos de uma imagem, cada um com
    /// sua região de origem e deslocamento. `refs` aponta para os
    /// glifos (copiados pela `DrawList` em blocos estáveis — o ponteiro
    /// do comando não muda enquanto o frame vive).
    /// `scale` = pixels do atlas por pixel lógico (1 = 1:1).
    glyph_run: extern struct {
        pos: types.Vec2,
        color: types.Color,
        pixels: ?[*]const u8,
        width: u32,
        height: u32,
        stride: u32,
        scale: f32 = 1.0,
        /// Bounds do run (usado no culling).
        bounds: types.Rect,
        refs: ?[*]const GlyphRef,
        count: u32,
    },
    /// Alfa global para os comandos SEGUINTES (até o próximo `.alpha`).
    /// `factor` em 0..1 multiplica o alfa das cores desenhadas depois
    /// dele — é o gancho de animações (fade in/out) sobre widgets. Vale
    /// até o fim do frame (ou até o próximo comando de alfa).
    alpha: extern struct {
        factor: f32 = 1.0,
    },
    /// Blit de uma imagem RGBA8 para `rect` (escala livre).
    /// `src` é a região inteira de origem (sprites/atlas); `pixels`
    /// aponta para o buffer do chamador, que precisa permanecer válido
    /// até o backend consumir o frame. `stride` está em bytes e `tint`
    /// modula RGBA (branco opaco = identidade). O backend de referência
    /// amostra com bilinear e respeita clip/culling.
    image: extern struct {
        rect: types.Rect,
        src: image_mod.Region,
        pixels: ?[*]const u8,
        width: u32,
        height: u32,
        stride: u32,
        tint: types.Color,
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
    /// Preenchimento em gradiente RADIAL: `color0` no centro do
    /// `rect`, `color1` na borda (raio `radius` a partir do centro).
    /// Gradiente contido em `rect` (clamp nas bordas).
    rect_gradient_radial: extern struct {
        rect: types.Rect,
        radius: f32,
        color0: types.Color,
        color1: types.Color,
    },
    /// Preenchimento em gradiente CONÍCO: `color0` no ângulo `start_angle`
    /// (radianos, medido desde +X, sentido anti-horário), `color1` em
    /// `start_angle + sweep`. O centro é o centro de `rect`.
    rect_gradient_conic: extern struct {
        rect: types.Rect,
        center: types.Vec2,
        start_angle: f32,
        sweep: f32,
        color0: types.Color,
        color1: types.Color,
    },
    /// Reta tracejada: `dash_len` px de traço, `gap_len` px de vazio,
    /// ao longo de `p0→p1`. Fase 0 em `p0`.
    line_dashed: extern struct {
        p0: types.Vec2,
        p1: types.Vec2,
        color: types.Color,
        thickness: f32,
        dash_len: f32,
        gap_len: f32,
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
            .circle_outline => |c| {
                return finite(c.center.x) and finite(c.center.y) and
                    finite(c.radius) and c.radius >= 0 and
                    finite(c.thickness) and c.thickness > 0;
            },
            .circle_dashed => |c| {
                return finite(c.center.x) and finite(c.center.y) and
                    finite(c.radius) and c.radius >= 0 and
                    finite(c.thickness) and c.thickness > 0 and
                    finite(c.dash_len) and c.dash_len > 0 and
                    finite(c.gap_len) and c.gap_len > 0;
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
            .alpha => |c| {
                return finite(c.factor) and c.factor >= 0;
            },
            .glyph_run => |c| {
                if (!finite(c.pos.x) or !finite(c.pos.y)) return false;
                if (c.pixels == null) return false;
                if (c.width == 0 or c.height == 0) return false;
                const row_bytes = @as(u64, c.width) * image_mod.bytes_per_pixel;
                if (row_bytes > std.math.maxInt(u32)) return false;
                if (@as(u64, c.stride) < row_bytes) return false;
                if (@as(u64, c.stride) * c.height > std.math.maxInt(usize)) return false;
                if (!finite(c.scale) or c.scale <= 0) return false;
                if (!finite(c.bounds.x) or !finite(c.bounds.y) or
                    !finite(c.bounds.w) or !finite(c.bounds.h)) return false;
                if (c.bounds.w < 0 or c.bounds.h < 0) return false;
                return c.count == 0 or c.refs != null;
            },
            .image => |c| {
                if (!finite(c.rect.x) or !finite(c.rect.y) or
                    !finite(c.rect.w) or !finite(c.rect.h) or
                    c.rect.w < 0 or c.rect.h < 0) return false;
                if (c.pixels == null) return false;
                if (c.width == 0 or c.height == 0) return false;
                const row_bytes = @as(u64, c.width) * image_mod.bytes_per_pixel;
                if (row_bytes > std.math.maxInt(u32)) return false;
                if (@as(u64, c.stride) < row_bytes) return false;
                const needed = @as(u64, c.stride) * c.height;
                if (needed > std.math.maxInt(usize)) return false;
                return c.src.isValidFor(c.width, c.height);
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
            .rect_gradient_radial => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.radius) and c.radius >= 0;
            },
            .rect_gradient_conic => |c| {
                return finite(c.rect.x) and finite(c.rect.y) and
                    finite(c.rect.w) and finite(c.rect.h) and
                    c.rect.w >= 0 and c.rect.h >= 0 and
                    finite(c.center.x) and finite(c.center.y) and
                    finite(c.start_angle) and finite(c.sweep);
            },
            .line_dashed => |c| {
                return finite(c.p0.x) and finite(c.p0.y) and
                    finite(c.p1.x) and finite(c.p1.y) and
                    finite(c.thickness) and c.thickness > 0 and
                    finite(c.dash_len) and c.dash_len > 0 and
                    finite(c.gap_len) and c.gap_len > 0;
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
            .rect_gradient_radial => |*c| moveRect(&c.rect, dx, dy),
            .rect_gradient_conic => |*c| {
                moveRect(&c.rect, dx, dy);
                moveVec(&c.center, dx, dy);
            },
            .line_dashed => |*c| {
                moveVec(&c.p0, dx, dy);
                moveVec(&c.p1, dx, dy);
            },
            .rect_gradient => |*c| {
                moveRect(&c.rect, dx, dy);
                moveVec(&c.p0, dx, dy);
                moveVec(&c.p1, dx, dy);
            },
            .rect_shadow => |*c| moveRect(&c.rect, dx, dy),
            .blur => |*c| moveRect(&c.rect, dx, dy),
            .image => |*c| moveRect(&c.rect, dx, dy),
            .glyph_run => |*c| {
                c.pos.x += dx;
                c.pos.y += dy;
                moveRect(&c.bounds, dx, dy);
            },
            .alpha => {},
            .line => |*c| {
                moveVec(&c.p0, dx, dy);
                moveVec(&c.p1, dx, dy);
            },
            .circle_filled => |*c| moveVec(&c.center, dx, dy),
            .circle_outline => |*c| moveVec(&c.center, dx, dy),
            .circle_dashed => |*c| moveVec(&c.center, dx, dy),
            .text => |*c| moveVec(&c.pos, dx, dy),
        }
        return out;
    }
    /// Cópia de `self` com toda a geometria multiplicada por `factor`
    /// (logical → dispositivo, M125). Ângulos e cores não mudam; a
    /// região de origem (`.image`) continua em pixels do atlas, que
    /// deve estar na resolução do destino.
    pub fn scaled(self: DrawCommand, factor: f32) DrawCommand {
        var out = self;
        switch (out) {
            .clear => {},
            .clip => |*c| {
                if (!c.null_rect) scaleRect(&c.rect, factor);
            },
            .rect_filled => |*c| scaleRect(&c.rect, factor),
            .rect_outline => |*c| {
                scaleRect(&c.rect, factor);
                c.thickness *= factor;
            },
            .rect_rounded => |*c| {
                scaleRect(&c.rect, factor);
                c.radius *= factor;
            },
            .rect_gradient => |*c| {
                scaleRect(&c.rect, factor);
                scaleVec(&c.p0, factor);
                scaleVec(&c.p1, factor);
            },
            .rect_gradient_radial => |*c| {
                scaleRect(&c.rect, factor);
                c.radius *= factor;
            },
            .rect_gradient_conic => |*c| {
                scaleRect(&c.rect, factor);
                scaleVec(&c.center, factor);
            },
            .line => |*c| {
                scaleVec(&c.p0, factor);
                scaleVec(&c.p1, factor);
                c.thickness *= factor;
            },
            .line_dashed => |*c| {
                scaleVec(&c.p0, factor);
                scaleVec(&c.p1, factor);
                c.thickness *= factor;
                c.dash_len *= factor;
                c.gap_len *= factor;
            },
            .circle_filled => |*c| {
                scaleVec(&c.center, factor);
                c.radius *= factor;
            },
            .circle_outline => |*c| {
                scaleVec(&c.center, factor);
                c.radius *= factor;
                c.thickness *= factor;
            },
            .circle_dashed => |*c| {
                scaleVec(&c.center, factor);
                c.radius *= factor;
                c.thickness *= factor;
                c.dash_len *= factor;
                c.gap_len *= factor;
            },
            .text => |*c| {
                scaleVec(&c.pos, factor);
                c.size *= factor;
                c.width *= factor;
            },
            .rect_shadow => |*c| {
                scaleRect(&c.rect, factor);
                c.radius *= factor;
                scaleVec(&c.offset, factor);
                c.blur *= factor;
            },
            .blur => |*c| {
                scaleRect(&c.rect, factor);
                c.radius *= factor;
            },
            .image => |*c| scaleRect(&c.rect, factor),
            .glyph_run => |*c| {
                c.pos.x *= factor;
                c.pos.y *= factor;
                scaleRect(&c.bounds, factor);
                // O destino do glifo cresce com o frame: o atlas
                // (pixels de origem) fica, o fator atlas/lógico divide.
                c.scale = c.scale / factor;
            },
            .alpha => {},
        }
        return out;
    }
};

fn moveRect(r: *types.Rect, dx: f32, dy: f32) void {
    r.x += dx;
    r.y += dy;
}

fn scaleRect(r: *types.Rect, factor: f32) void {
    r.x *= factor;
    r.y *= factor;
    r.w *= factor;
    r.h *= factor;
}

fn moveVec(p: *types.Vec2, dx: f32, dy: f32) void {
    p.x += dx;
    p.y += dy;
}

fn scaleVec(p: *types.Vec2, factor: f32) void {
    p.x *= factor;
    p.y *= factor;
}

/// Lista de desenho do frame (bump por frame + retenção de capacidade).
/// `text_bytes` é a arena dos textos de comandos `.text`; comandos
/// guardam offsets, nunca slices (seguro contra realocação).
pub const DrawList = struct {
    list: std.ArrayList(DrawCommand),
    text_bytes: std.ArrayList(u8) = .empty,
    /// Blocos de glifos dos runs (ver `DrawCommand.glyph_run`). O
    /// ponteiro do comando precisa ser estável ⇒ os blocos nunca são
    /// movidos (quando um enche, outro é alocado).
    glyph_blocks: std.ArrayList([]GlyphRef) = .empty,
    /// Glifos usados no bloco atual (o bloco é reaproveitado no frame
    /// seguinte: sem alocação por frame).
    glyph_block_len: usize = 0,

    const Self = @This();

    pub fn initEmpty() Self {
        return .{ .list = .empty, .text_bytes = .empty };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.list.deinit(gpa);
        self.text_bytes.deinit(gpa);
        for (self.glyph_blocks.items) |block| gpa.free(block);
        self.glyph_blocks.deinit(gpa);
        self.glyph_block_len = 0;
    }

    pub fn clearRetainingCapacity(self: *Self) void {
        self.list.clearRetainingCapacity();
        self.text_bytes.clearRetainingCapacity();
        // Os blocos são REUSADOS no frame seguinte (mesmo endereço ⇒ os
        // comandos do frame anterior, já descartados, não importam).
        self.glyph_block_len = 0;
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
            if (cmd == .glyph_run) {
                try self.copyGlyphRun(gpa, out, cmd, dx, dy, 1.0);
                continue;
            }
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

    /// Reconstrói `out` como esta lista projetada para o espaço de
    /// DISPOSITIVO (M125): toda a geometria é multiplicada por `factor`
    /// (ver `DrawCommand.scaled`) e os bytes de texto são remontados
    /// (os offsets são reescritos). `out` deve ser OUTRA lista.
    /// A região de origem das imagens NÃO escala: o atlas/fonte deve
    /// estar na resolução do destino.
    pub fn scaledInto(
        self: *const Self,
        gpa: std.mem.Allocator,
        out: *Self,
        factor: f32,
    ) !void {
        if (!std.math.isFinite(factor) or factor <= 0) return error.InvalidArgument;
        out.clearRetainingCapacity();
        for (self.list.items) |cmd| {
            if (cmd == .glyph_run) {
                try self.copyGlyphRun(gpa, out, cmd, 0, 0, factor);
                continue;
            }
            if (cmd != .text) {
                try out.push(gpa, cmd.scaled(factor));
                continue;
            }
            const bytes = self.textOf(cmd);
            const start: u32 = @intCast(out.text_bytes.items.len);
            try out.text_bytes.appendSlice(gpa, bytes);
            var copy = cmd.scaled(factor);
            copy.text.start = start;
            copy.text.len = @intCast(bytes.len);
            try out.push(gpa, copy);
        }
    }

    /// Copia um run de glifos para outra lista: os offsets dos glifos
    /// são multiplicados por `factor` (escala) e a posição do run é
    /// transladada por (dx, dy).
    fn copyGlyphRun(
        self: *const Self,
        gpa: std.mem.Allocator,
        out: *Self,
        cmd: DrawCommand,
        dx: f32,
        dy: f32,
        factor: f32,
    ) !void {
        const refs = self.glyphsOf(cmd);
        var scaled: [256]GlyphRef = undefined;
        var list: []const GlyphRef = refs;
        if (factor != 1.0) {
            // Blocos locais (o caso comum cabe em 256 glifos).
            if (refs.len > scaled.len) return error.OutOfMemory;
            for (refs, 0..) |r, i| {
                scaled[i] = .{
                    .src_x = r.src_x,
                    .src_y = r.src_y,
                    .src_w = r.src_w,
                    .src_h = r.src_h,
                    .dx = r.dx * factor,
                    .dy = r.dy * factor,
                };
            }
            list = scaled[0..refs.len];
        }
        const ptr = if (list.len == 0) null else try out.allocGlyphs(gpa, list);
        var copy = if (factor == 1.0) cmd.translated(dx, dy) else cmd.scaled(factor);
        copy.glyph_run.refs = ptr;
        copy.glyph_run.count = @intCast(list.len);
        try out.push(gpa, copy);
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

    pub fn circleOutline(self: *Self, gpa: std.mem.Allocator, center: types.Vec2, radius: f32, color: types.Color, thickness: f32) !void {
        try self.push(gpa, .{ .circle_outline = .{ .center = center, .color = color, .radius = radius, .thickness = thickness } });
    }

    pub fn circleDashed(self: *Self, gpa: std.mem.Allocator, center: types.Vec2, radius: f32, color: types.Color, thickness: f32, dash_len: f32, gap_len: f32) !void {
        try self.push(gpa, .{ .circle_dashed = .{ .center = center, .color = color, .radius = radius, .thickness = thickness, .dash_len = dash_len, .gap_len = gap_len } });
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
    /// Preenchimento em gradiente radial: `color0` no centro, `color1` na borda,
    /// contido em `rect`.
    pub fn rectGradientRadial(
        self: *Self,
        gpa: std.mem.Allocator,
        rect: types.Rect,
        radius: f32,
        color0: types.Color,
        color1: types.Color,
    ) !void {
        try self.push(gpa, .{ .rect_gradient_radial = .{
            .rect = rect,
            .radius = radius,
            .color0 = color0,
            .color1 = color1,
        } });
    }

    /// Gradiente cônico: `color0` em `start_angle` (rad desde +X),
    /// `color1` em `start_angle + sweep`.
    pub fn rectGradientConic(
        self: *Self,
        gpa: std.mem.Allocator,
        rect: types.Rect,
        center: types.Vec2,
        start_angle: f32,
        sweep: f32,
        color0: types.Color,
        color1: types.Color,
    ) !void {
        try self.push(gpa, .{ .rect_gradient_conic = .{
            .rect = rect,
            .center = center,
            .start_angle = start_angle,
            .sweep = sweep,
            .color0 = color0,
            .color1 = color1,
        } });
    }

    /// Reta tracejada: `dash_len` px de traço alternando com `gap_len`.
    pub fn lineDashed(
        self: *Self,
        gpa: std.mem.Allocator,
        p0: types.Vec2,
        p1: types.Vec2,
        color: types.Color,
        thickness: f32,
        dash_len: f32,
        gap_len: f32,
    ) !void {
        try self.push(gpa, .{ .line_dashed = .{
            .p0 = p0,
            .p1 = p1,
            .color = color,
            .thickness = thickness,
            .dash_len = dash_len,
            .gap_len = gap_len,
        } });
    }
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

    /// Define o alfa global dos comandos seguintes (0..1; valores acima
    /// de 1 são tratados como 1 pelo backend). Ver `DrawCommand.alpha`.
    pub fn pushAlpha(self: *Self, gpa: std.mem.Allocator, factor: f32) !void {
        try self.push(gpa, .{ .alpha = .{ .factor = factor } });
    }

    /// Enfileira um run de glifos (atlas de fonte): os `refs` são
    /// copiados para a arena interna e o comando aponta para eles.
    /// `scale` = pixels do atlas por pixel lógico (1 = 1:1); o tamanho
    /// de cada glifo no destino é `src_w / scale`.
    pub fn glyphRun(
        self: *Self,
        gpa: std.mem.Allocator,
        pos: types.Vec2,
        color: types.Color,
        img: image_mod.Image,
        refs: []const GlyphRef,
        scale: f32,
    ) !void {
        if (!img.isValid()) return error.InvalidCommand;
        if (!std.math.isFinite(scale) or scale <= 0) return error.InvalidCommand;
        for (refs) |r| {
            const region = image_mod.Region.init(r.src_x, r.src_y, r.src_w, r.src_h);
            if (!region.isValidFor(img.width, img.height)) return error.InvalidCommand;
            if (!std.math.isFinite(r.dx) or !std.math.isFinite(r.dy)) return error.InvalidCommand;
        }
        // Bloco estável para os glifos (o ponteiro do comando não muda).
        const refs_ptr = if (refs.len == 0) null else try self.allocGlyphs(gpa, refs);
        // Bounds: união dos glifos no destino.
        var bounds = types.Rect.init(pos.x, pos.y, 0, 0);
        var first = true;
        for (refs) |r| {
            const w = @as(f32, @floatFromInt(r.src_w)) / scale;
            const h = @as(f32, @floatFromInt(r.src_h)) / scale;
            const g = types.Rect.init(pos.x + r.dx, pos.y + r.dy, w, h);
            bounds = if (first) g else bounds.unionWith(g);
            first = false;
        }
        try self.push(gpa, .{ .glyph_run = .{
            .pos = pos,
            .color = color,
            .pixels = img.pixels.ptr,
            .width = img.width,
            .height = img.height,
            .stride = img.stride,
            .scale = scale,
            .bounds = bounds,
            .refs = refs_ptr,
            .count = @intCast(refs.len),
        } });
    }

    /// Copia `refs` para um bloco estável da lista (aloca um bloco novo
    /// quando o atual não cabe) e devolve o ponteiro.
    fn allocGlyphs(self: *Self, gpa: std.mem.Allocator, refs: []const GlyphRef) ![*]const GlyphRef {
        const block_cap: usize = 256;
        if (self.glyph_blocks.items.len == 0 or
            self.glyph_block_len + refs.len > self.glyph_blocks.items[self.glyph_blocks.items.len - 1].len)
        {
            const cap = @max(block_cap, refs.len);
            const block = try gpa.alloc(GlyphRef, cap);
            errdefer gpa.free(block);
            try self.glyph_blocks.append(gpa, block);
            self.glyph_block_len = 0;
        }
        const block = self.glyph_blocks.items[self.glyph_blocks.items.len - 1];
        const dst = block.ptr + self.glyph_block_len;
        @memcpy(dst[0..refs.len], refs);
        self.glyph_block_len += refs.len;
        return dst;
    }

    /// Glifos de um run. Retorna vazio se o comando não for um run ou
    /// os offsets forem inconsistentes (defensivo).
    pub fn glyphsOf(self: *const Self, cmd: DrawCommand) []const GlyphRef {
        _ = self;
        const g = switch (cmd) {
            .glyph_run => |p| p,
            else => return &.{},
        };
        const ptr = g.refs orelse return &.{};
        return ptr[0..g.count];
    }

    /// Enfileira a imagem inteira em `rect` (blit escalável).
    /// `tint` modula RGBA; use `Color.rgb(255, 255, 255)` para identidade.
    /// Os bytes de `img` são emprestados e não copiados.
    pub fn image(
        self: *Self,
        gpa: std.mem.Allocator,
        rect: types.Rect,
        img: image_mod.Image,
        tint: types.Color,
    ) !void {
        try self.imageRegion(gpa, rect, img, img.fullRegion(), tint);
    }

    /// Enfileira um sub-retângulo inteiro de `img` em `rect`.
    /// Útil para sprites e atlas de glifos.
    pub fn imageRegion(
        self: *Self,
        gpa: std.mem.Allocator,
        rect: types.Rect,
        img: image_mod.Image,
        src: image_mod.Region,
        tint: types.Color,
    ) !void {
        if (!img.isValid()) return error.InvalidCommand;
        try self.push(gpa, .{ .image = .{
            .rect = rect,
            .src = src,
            .pixels = img.pixels.ptr,
            .width = img.width,
            .height = img.height,
            .stride = img.stride,
            .tint = tint,
        } });
    }
};

test "DrawList image: enfileira, valida e translada (M123)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);

    try dl.image(gpa, types.Rect.init(4, 5, 20, 10), img, types.Color.rgb(255, 255, 255));
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    const cmd = dl.items()[0];
    try stdt.testing.expect(cmd == .image);
    try stdt.testing.expectEqual(types.Rect.init(4, 5, 20, 10), cmd.image.rect);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 2), cmd.image.src);
    try stdt.testing.expectEqual(@as(u32, 2), cmd.image.width);
    try stdt.testing.expectEqual(@as(u32, 2), cmd.image.height);
    try stdt.testing.expectEqual(@as(u32, 8), cmd.image.stride);
    try stdt.testing.expect(cmd.image.pixels != null);
    try stdt.testing.expectEqual(types.Color.rgb(255, 255, 255), cmd.image.tint);

    // Região de origem (sprite/atlas) é preservada.
    try dl.imageRegion(
        gpa,
        types.Rect.init(0, 0, 4, 4),
        img,
        image_mod.Region.init(1, 0, 1, 1),
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual(image_mod.Region.init(1, 0, 1, 1), dl.items()[1].image.src);

    // Região fora da imagem é recusada sem enfileirar.
    try stdt.testing.expectError(error.InvalidCommand, dl.imageRegion(
        gpa,
        types.Rect.init(0, 0, 4, 4),
        img,
        image_mod.Region.init(2, 0, 1, 1),
        types.Color.rgb(255, 255, 255),
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.imageRegion(
        gpa,
        types.Rect.init(0, 0, 4, 4),
        img,
        image_mod.Region.init(0, 0, 0, 1),
        types.Color.rgb(255, 255, 255),
    ));
    try stdt.testing.expectEqual(@as(usize, 2), dl.len());

    // Imagem inválida (bytes curtos) é recusada.
    var short: [8]u8 = undefined;
    try stdt.testing.expectError(error.InvalidImage, image_mod.Image.initStrided(2, 2, 8, &short));

    // Comandos forjados são rejeitados por `isValid`.
    var forged = dl.items()[0];
    forged.image.pixels = null;
    try stdt.testing.expect(!forged.isValid());
    forged = dl.items()[0];
    forged.image.src = image_mod.Region.init(0, 0, 3, 3);
    try stdt.testing.expect(!forged.isValid());
    forged = dl.items()[0];
    forged.image.stride = 4;
    try stdt.testing.expect(!forged.isValid());
    forged = dl.items()[0];
    forged.image.rect = types.Rect.init(0, 0, -1, 4);
    try stdt.testing.expect(!forged.isValid());
    forged = dl.items()[0];
    forged.image.width = 0;
    try stdt.testing.expect(!forged.isValid());
}

test "DrawList translateInto preserva comando de imagem (M123)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var src = DrawList.initEmpty();
    defer src.deinit(gpa);
    var out = DrawList.initEmpty();
    defer out.deinit(gpa);

    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);
    try src.image(gpa, types.Rect.init(1, 2, 8, 8), img, types.Color.rgb(255, 255, 255));

    try src.translateInto(gpa, &out, 10, 20);
    try stdt.testing.expectEqual(@as(usize, 1), out.len());
    try stdt.testing.expectEqual(types.Rect.init(11, 22, 8, 8), out.items()[0].image.rect);
    // A região de origem continua em coordenadas da imagem.
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 2), out.items()[0].image.src);
    try stdt.testing.expect(out.items()[0].image.pixels != null);
}

test "fuzz pushImage: sem crash, comando sempre válido" {
    try std.testing.fuzz({}, fuzzPushImage, .{});
}

fn fuzzPushImage(_: void, smith: *std.testing.Smith) !void {
    var fb: [32]u8 = undefined;
    smith.bytes(&fb);
    const gpa = std.testing.allocator;

    var bytes: [64]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(4, 4, &bytes);

    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    const w = @as(f32, @floatFromInt(fb[0] % 40)) + 1.0;
    const h = @as(f32, @floatFromInt(fb[1] % 40)) + 1.0;
    const x = @as(f32, @floatFromInt(fb[2] % 20)) - 10.0;
    const y = @as(f32, @floatFromInt(fb[3] % 20)) - 10.0;
    const sx = @as(u32, fb[4] % 4);
    const sy = @as(u32, fb[5] % 4);
    const sw = @as(u32, fb[6] % (4 - sx + 1));
    const sh = @as(u32, fb[7] % (4 - sy + 1));
    const region = image_mod.Region.init(sx, sy, sw, sh);

    dl.imageRegion(gpa, types.Rect.init(x, y, w, h), img, region, types.Color.rgb(255, 255, 255)) catch |err| {
        try std.testing.expectEqual(error.InvalidCommand, err);
        return;
    };
    try std.testing.expectEqual(@as(usize, 1), dl.len());
    try std.testing.expect(dl.items()[0].isValid());
}

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

test "DrawList rectGradientRadial + circleOutline + circleDashed + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    // Gradiente radial válido.
    try dl.rectGradientRadial(
        gpa,
        types.Rect.init(0, 0, 8, 8),
        4,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    try stdt.testing.expect(dl.items()[0].isValid());
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 8, 8), dl.items()[0].rect_gradient_radial.rect);

    // Raio negativo é rejeitado.
    try stdt.testing.expectError(error.InvalidCommand, dl.rectGradientRadial(
        gpa,
        types.Rect.init(0, 0, 8, 8),
        -1,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    ));

    // Contorno de círculo.
    try dl.circleOutline(gpa, types.Vec2.init(4, 4), 3, types.Color.rgb(255, 255, 255), 1.5);
    try stdt.testing.expectEqual(@as(usize, 2), dl.len());
    try stdt.testing.expect(dl.items()[1].isValid());

    // Espessura não-positiva é rejeitada.
    try stdt.testing.expectError(error.InvalidCommand, dl.circleOutline(
        gpa,
        types.Vec2.init(4, 4),
        3,
        types.Color.rgb(255, 255, 255),
        0,
    ));

    // Círculo tracejado.
    try dl.circleDashed(gpa, types.Vec2.init(4, 4), 3, types.Color.rgb(255, 255, 255), 1, 2, 1);
    try stdt.testing.expectEqual(@as(usize, 3), dl.len());
    try stdt.testing.expect(dl.items()[2].isValid());

    // dash/gap não-positivos são rejeitados.
    try stdt.testing.expectError(error.InvalidCommand, dl.circleDashed(
        gpa,
        types.Vec2.init(4, 4),
        3,
        types.Color.rgb(255, 255, 255),
        1,
        0,
        1,
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.circleDashed(
        gpa,
        types.Vec2.init(4, 4),
        3,
        types.Color.rgb(255, 255, 255),
        1,
        2,
        0,
    ));
    try stdt.testing.expectEqual(@as(usize, 3), dl.len());
}

test "DrawList rectGradientConic + lineDashed + validação" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    // Gradiente cônico válido.
    try dl.rectGradientConic(
        gpa,
        types.Rect.init(0, 0, 8, 8),
        types.Vec2.init(4, 4),
        0,
        6.2831855,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    try stdt.testing.expect(dl.items()[0].isValid());

    // Ângulo não-finito é rejeitado.
    try stdt.testing.expectError(error.InvalidCommand, dl.rectGradientConic(
        gpa,
        types.Rect.init(0, 0, 8, 8),
        types.Vec2.init(4, 4),
        std.math.nan(f32),
        1,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
    ));

    // Linha tracejada válida.
    try dl.lineDashed(
        gpa,
        types.Vec2.init(0, 0),
        types.Vec2.init(10, 10),
        types.Color.rgb(255, 255, 255),
        2,
        3,
        1,
    );
    try stdt.testing.expectEqual(@as(usize, 2), dl.len());
    try stdt.testing.expect(dl.items()[1].isValid());

    // dash/gap não-positivos são rejeitados.
    try stdt.testing.expectError(error.InvalidCommand, dl.lineDashed(
        gpa,
        types.Vec2.init(0, 0),
        types.Vec2.init(10, 10),
        types.Color.rgb(255, 255, 255),
        2,
        0,
        1,
    ));
    try stdt.testing.expectError(error.InvalidCommand, dl.lineDashed(
        gpa,
        types.Vec2.init(0, 0),
        types.Vec2.init(10, 10),
        types.Color.rgb(255, 255, 255),
        2,
        3,
        0,
    ));
    try stdt.testing.expectEqual(@as(usize, 2), dl.len());
}

test "DrawList scaledInto projeta para o espaço de dispositivo (M125)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var src = DrawList.initEmpty();
    defer src.deinit(gpa);
    var out = DrawList.initEmpty();
    defer out.deinit(gpa);

    try src.rectFilled(gpa, types.Rect.init(1, 2, 10, 20), types.Color.rgb(1, 2, 3));
    try src.rectOutline(gpa, types.Rect.init(0, 0, 4, 4), types.Color.rgb(0, 0, 0), 1.0);
    try src.line(gpa, types.Vec2.init(1, 1), types.Vec2.init(3, 3), types.Color.rgb(0, 0, 0), 2.0);
    try src.circleFilled(gpa, types.Vec2.init(5, 5), 2.0, types.Color.rgb(0, 0, 0));
    try src.clip(gpa, types.Rect.init(0, 0, 2, 2));
    try src.pushText(
        gpa,
        types.Vec2.init(3, 4),
        types.Color.rgb(255, 255, 255),
        metrics_mod.FontMetrics.withSize(10),
        "Hi",
    );

    try src.scaledInto(gpa, &out, 2.0);
    try stdt.testing.expectEqual(src.len(), out.len());

    try stdt.testing.expectEqual(types.Rect.init(2, 4, 20, 40), out.items()[0].rect_filled.rect);
    try stdt.testing.expectEqual(@as(f32, 2.0), out.items()[1].rect_outline.thickness);
    try stdt.testing.expectEqual(types.Vec2.init(2, 2), out.items()[2].line.p0);
    try stdt.testing.expectEqual(types.Vec2.init(6, 6), out.items()[2].line.p1);
    try stdt.testing.expectEqual(@as(f32, 4.0), out.items()[2].line.thickness);
    try stdt.testing.expectEqual(types.Vec2.init(10, 10), out.items()[3].circle_filled.center);
    try stdt.testing.expectEqual(@as(f32, 4.0), out.items()[3].circle_filled.radius);
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 4, 4), out.items()[4].clip.rect);
    // Texto: posição/tamanho escalam, bytes e offsets seguem válidos.
    try stdt.testing.expectEqual(types.Vec2.init(6, 8), out.items()[5].text.pos);
    try stdt.testing.expectEqual(@as(f32, 20.0), out.items()[5].text.size);
    try stdt.testing.expectEqualStrings("Hi", out.textOf(out.items()[5]));

    // Fator inválido é recusado.
    try stdt.testing.expectError(error.InvalidArgument, src.scaledInto(gpa, &out, 0));
    try stdt.testing.expectError(error.InvalidArgument, src.scaledInto(gpa, &out, std.math.nan(f32)));
}

test "DrawList scaledInto mantém a região de origem da imagem (M125)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var src = DrawList.initEmpty();
    defer src.deinit(gpa);
    var out = DrawList.initEmpty();
    defer out.deinit(gpa);

    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);
    try src.image(gpa, types.Rect.init(0, 0, 4, 4), img, types.Color.rgb(255, 255, 255));

    try src.scaledInto(gpa, &out, 2.0);
    // Destino escala (lógico → dispositivo), a origem continua nos pixels
    // do atlas (que já estão na resolução do destino).
    try stdt.testing.expectEqual(types.Rect.init(0, 0, 8, 8), out.items()[0].image.rect);
    try stdt.testing.expectEqual(image_mod.Region.init(0, 0, 2, 2), out.items()[0].image.src);
}

test "DrawList glyphRun: um comando por run de glifos (M146)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var dl = DrawList.initEmpty();
    defer dl.deinit(gpa);

    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);
    const refs = [_]GlyphRef{
        .{ .src_x = 0, .src_y = 0, .src_w = 2, .src_h = 2, .dx = 0, .dy = 0 },
        .{ .src_x = 0, .src_y = 0, .src_w = 2, .src_h = 2, .dx = 4, .dy = 1 },
    };

    try dl.glyphRun(gpa, types.Vec2.init(10, 20), types.Color.rgb(255, 255, 255), img, &refs, 1.0);
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
    const cmd = dl.items()[0];
    try stdt.testing.expect(cmd == .glyph_run);
    try stdt.testing.expectEqual(types.Vec2.init(10, 20), cmd.glyph_run.pos);
    try stdt.testing.expectEqual(@as(u32, 2), cmd.glyph_run.count);
    try stdt.testing.expect(cmd.glyph_run.pixels != null);
    // Os glifos ficam acessíveis pela lista (cópia estável).
    const got = dl.glyphsOf(cmd);
    try stdt.testing.expectEqual(@as(usize, 2), got.len);
    try stdt.testing.expectEqual(@as(f32, 4), got[1].dx);
    // Bounds = união dos glifos no destino.
    try stdt.testing.expectEqual(types.Rect.init(10, 20, 6, 3), cmd.glyph_run.bounds);

    // Inválidos: escala, imagem e região fora.
    try stdt.testing.expectError(error.InvalidCommand, dl.glyphRun(gpa, .{}, .{}, img, &refs, 0));
    try stdt.testing.expectError(error.InvalidCommand, dl.glyphRun(gpa, .{}, .{}, img, &refs, std.math.nan(f32)));
    const bad_img = image_mod.Image{ .width = 0, .height = 0, .stride = 0, .pixels = &.{} };
    try stdt.testing.expectError(error.InvalidCommand, dl.glyphRun(gpa, .{}, .{}, bad_img, &refs, 1.0));
    const outside = [_]GlyphRef{.{ .src_x = 1, .src_y = 0, .src_w = 2, .src_h = 2 }};
    try stdt.testing.expectError(error.InvalidCommand, dl.glyphRun(gpa, .{}, .{}, img, &outside, 1.0));
    try stdt.testing.expectEqual(@as(usize, 1), dl.len());
}

test "DrawList translateInto/scaledInto copiam os glifos do run (M146)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var src = DrawList.initEmpty();
    defer src.deinit(gpa);
    var out = DrawList.initEmpty();
    defer out.deinit(gpa);

    var bytes: [16]u8 = undefined;
    for (&bytes, 0..) |*p, i| p.* = @intCast(i);
    const img = try image_mod.Image.init(2, 2, &bytes);
    const refs = [_]GlyphRef{
        .{ .src_x = 0, .src_y = 0, .src_w = 2, .src_h = 2, .dx = 0, .dy = 0 },
        .{ .src_x = 0, .src_y = 0, .src_w = 2, .src_h = 2, .dx = 4, .dy = 0 },
    };
    try src.glyphRun(gpa, types.Vec2.init(1, 2), types.Color.rgb(255, 255, 255), img, &refs, 1.0);

    // Translação: a posição do run muda, os glifos (relativos) ficam.
    try src.translateInto(gpa, &out, 10, 20);
    try stdt.testing.expectEqual(@as(usize, 1), out.len());
    try stdt.testing.expectEqual(types.Vec2.init(11, 22), out.items()[0].glyph_run.pos);
    const moved = out.glyphsOf(out.items()[0]);
    try stdt.testing.expectEqual(@as(usize, 2), moved.len);
    try stdt.testing.expectEqual(@as(f32, 4), moved[1].dx);

    // Escala: os deslocamentos dos glifos escalam; a escala do atlas
    // divide (o destino cresce).
    try src.scaledInto(gpa, &out, 2.0);
    try stdt.testing.expectEqual(types.Vec2.init(2, 4), out.items()[0].glyph_run.pos);
    try stdt.testing.expectEqual(@as(f32, 0.5), out.items()[0].glyph_run.scale);
    const scaled = out.glyphsOf(out.items()[0]);
    try stdt.testing.expectEqual(@as(f32, 8), scaled[1].dx);
}
