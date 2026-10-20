//! ZyntraUI — backend de referência em software (software/raster).
//!
//! Rasterizador CPU puro para VERIFICAÇÃO do contrato de desenho
//! (pixels reais, asserts exatos) e saída sem GPU. NÃO é um renderer
//! de produção: sem rasterização de glifos (runs de texto são pulados
//! E contados). Blending source-over com arredondamento (opaco e
//! transparente têm caminho rápido/idêntico ao legado).
//! - `SoftwareFramebuffer`: RGBA8 row-major, 1px = 1px lógico, origem
//!   no canto superior-esquerdo, amostra no centro do pixel.
//! - `render`: aplica `clip`, viewport e culling; retorna estatísticas.
//! - `encodePpm`: PPM binário (P6, RGB) em buffer do chamador, sem deps.
//! Ownership: fb detém `pixels` (alocador do chamador); comandos são
//! apenas lidos. Tudo determinístico e sem estado global.

const std = @import("std");
const types = @import("../core/types.zig");
const commands = @import("../draw/commands.zig");
const renderer = @import("../draw/renderer.zig");

pub const max_dimension: u32 = 8192;

/// RGBA8 row-major. Conteúdo inicial INDEFINIDO (lixo do alocador —
/// Debug preenche com 0xAA, Release zera): limpe com `clear` ou cubra
/// tudo antes de ler pixels.
pub const SoftwareFramebuffer = struct {
    w: u32,
    h: u32,
    pixels: []u8, // len == w*h*4, RGBA por pixel
    /// Buffer de trabalho do mesmo tamanho de `pixels`, usado por efeitos
    /// que precisam de uma cópia (ex.: `blur`). `init` sempre o
    /// dimensiona; uma construção manual deve fornecê-lo para usar blur.
    scratch: []u8 = &.{},

    const Self = @This();

    pub fn init(gpa: std.mem.Allocator, w: u32, h: u32) !Self {
        if (w == 0 or h == 0 or w > max_dimension or h > max_dimension) {
            return error.InvalidArgument;
        }
        const n: u64 = @as(u64, w) * h * 4;
        const pixels = try gpa.alloc(u8, @intCast(n));
        errdefer gpa.free(pixels);
        const scratch = try gpa.alloc(u8, @intCast(n));
        return .{ .w = w, .h = h, .pixels = pixels, .scratch = scratch };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        gpa.free(self.pixels);
        if (self.scratch.len != 0) gpa.free(self.scratch);
        self.pixels = &.{};
        self.scratch = &.{};
        self.w = 0;
        self.h = 0;
    }

    pub fn get(self: *const Self, x: u32, y: u32) [4]u8 {
        std.debug.assert(x < self.w and y < self.h);
        const i = (@as(usize, y) * self.w + x) * 4;
        return self.pixels[i..][0..4].*;
    }

    fn set(self: *Self, x: u32, y: u32, c: types.Color) void {
        const i = (@as(usize, y) * self.w + x) * 4;
        if (c.a == 255) {
            // Caminho rápido: opaco sobrescreve (idêntico ao legado).
            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = c.a;
            return;
        }
        if (c.a == 0) return; // transparente: no-op
        const d0: u32 = self.pixels[i];
        const d1: u32 = self.pixels[i + 1];
        const d2: u32 = self.pixels[i + 2];
        const d3: u32 = self.pixels[i + 3];
        const sa: u32 = c.a;
        const ia: u32 = 255 - sa;
        // Source-over com arredondamento (+127 antes de /255).
        self.pixels[i] = @intCast((@as(u32, c.r) * sa + d0 * ia + 127) / 255);
        self.pixels[i + 1] = @intCast((@as(u32, c.g) * sa + d1 * ia + 127) / 255);
        self.pixels[i + 2] = @intCast((@as(u32, c.b) * sa + d2 * ia + 127) / 255);
        self.pixels[i + 3] = @intCast((sa * 255 + d3 * ia + 127) / 255);
    }

    /// Escreve `c` com cobertura fracionária `cov` (0..1) — usado por
    /// bordas anti-serrilhadas (SDF). `cov == 1` equivale a `set`.
    fn setAlpha(self: *Self, x: u32, y: u32, c: types.Color, cov: f32) void {
        if (cov <= 0) return;
        if (cov >= 1) {
            self.set(x, y, c);
            return;
        }
        const a = @as(u32, @intFromFloat(@round(@as(f32, @floatFromInt(c.a)) * cov)));
        if (a == 0) return;
        const i = (@as(usize, y) * self.w + x) * 4;
        const sa = a;
        const ia: u32 = 255 - sa;
        const d0: u32 = self.pixels[i];
        const d1: u32 = self.pixels[i + 1];
        const d2: u32 = self.pixels[i + 2];
        const d3: u32 = self.pixels[i + 3];
        self.pixels[i] = @intCast((@as(u32, c.r) * sa + d0 * ia + 127) / 255);
        self.pixels[i + 1] = @intCast((@as(u32, c.g) * sa + d1 * ia + 127) / 255);
        self.pixels[i + 2] = @intCast((@as(u32, c.b) * sa + d2 * ia + 127) / 255);
        self.pixels[i + 3] = @intCast((sa * 255 + d3 * ia + 127) / 255);
    }

    pub fn clear(self: *Self, c: types.Color) void {
        var i: usize = 0;
        while (i < self.pixels.len) : (i += 4) {
            self.pixels[i] = c.r;
            self.pixels[i + 1] = c.g;
            self.pixels[i + 2] = c.b;
            self.pixels[i + 3] = c.a;
        }
    }

    /// Preenche a interseção de `r` com `clip` (quando presente).
    /// Coordenadas: pixel (i,j) cobre [i,i+1)×[j,j+1).
    /// Entradas não-finitas saturam em no-op (conversão float→int
    /// travaria; `render` já rejeita, isto protege chamadas diretas).
    pub fn fillRect(self: *Self, r: types.Rect, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h)) return;
        var x0 = @as(i64, @intFromFloat(@floor(r.x)));
        var y0 = @as(i64, @intFromFloat(@floor(r.y)));
        var x1 = @as(i64, @intFromFloat(@ceil(r.x + r.w)));
        var y1 = @as(i64, @intFromFloat(@ceil(r.y + r.h)));
        x0 = @max(x0, 0);
        y0 = @max(y0, 0);
        x1 = @min(x1, self.w);
        y1 = @min(y1, self.h);
        if (clip) |cp| {
            x0 = @max(x0, @as(i64, @intFromFloat(@floor(cp.x))));
            y0 = @max(y0, @as(i64, @intFromFloat(@floor(cp.y))));
            x1 = @min(x1, @as(i64, @intFromFloat(@ceil(cp.x + cp.w))));
            y1 = @min(y1, @as(i64, @intFromFloat(@ceil(cp.y + cp.h))));
        }
        if (c.a == 0) return; // transparente: no-op
        if (c.a == 255) {
            // Caminho rápido opaco (sequencial puro, vetorizável).
            var y = y0;
            while (y < y1) : (y += 1) {
                var o = @as(usize, @intCast(y)) * @as(usize, self.w) * 4 + @as(usize, @intCast(x0)) * 4;
                var x = x0;
                while (x < x1) : (x += 1) {
                    self.pixels[o] = c.r;
                    self.pixels[o + 1] = c.g;
                    self.pixels[o + 2] = c.b;
                    self.pixels[o + 3] = c.a;
                    o += 4;
                }
            }
            return;
        }
        // Blending com base içada (mesma matemática de set()).
        const sa: u32 = c.a;
        const ia: u32 = 255 - sa;
        var y = y0;
        while (y < y1) : (y += 1) {
            var o = @as(usize, @intCast(y)) * @as(usize, self.w) * 4 + @as(usize, @intCast(x0)) * 4;
            var x = x0;
            while (x < x1) : (x += 1) {
                self.pixels[o] = @intCast((@as(u32, c.r) * sa + @as(u32, self.pixels[o]) * ia + 127) / 255);
                self.pixels[o + 1] = @intCast((@as(u32, c.g) * sa + @as(u32, self.pixels[o + 1]) * ia + 127) / 255);
                self.pixels[o + 2] = @intCast((@as(u32, c.b) * sa + @as(u32, self.pixels[o + 2]) * ia + 127) / 255);
                self.pixels[o + 3] = @intCast((sa * 255 + @as(u32, self.pixels[o + 3]) * ia + 127) / 255);
                o += 4;
            }
        }
    }

    fn distPointSeg(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) f32 {
        const dx = bx - ax;
        const dy = by - ay;
        const l2 = dx * dx + dy * dy;
        if (l2 == 0) {
            const ex = px - ax;
            const ey = py - ay;
            return @sqrt(ex * ex + ey * ey);
        }
        var t = ((px - ax) * dx + (py - ay) * dy) / l2;
        t = std.math.clamp(t, 0, 1);
        const ex = px - (ax + t * dx);
        const ey = py - (ay + t * dy);
        return @sqrt(ex * ex + ey * ey);
    }

    fn inClip(x: i64, y: i64, clip: ?types.Rect) bool {
        const cp = clip orelse return true;
        const fx: f32 = @floatFromInt(x);
        const fy: f32 = @floatFromInt(y);
        return fx + 1 > cp.x and fx < cp.x + cp.w and fy + 1 > cp.y and fy < cp.y + cp.h;
    }

    pub fn strokeLine(self: *Self, p0: types.Vec2, p1: types.Vec2, thickness: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(p0.x) or !std.math.isFinite(p0.y) or
            !std.math.isFinite(p1.x) or !std.math.isFinite(p1.y) or
            !std.math.isFinite(thickness) or thickness <= 0) return;
        const r = thickness / 2;
        const x0f = @min(p0.x, p1.x) - r - 1;
        const y0f = @min(p0.y, p1.y) - r - 1;
        const x1f = @max(p0.x, p1.x) + r + 1;
        const y1f = @max(p0.y, p1.y) + r + 1;
        var y = @max(0, @as(i64, @intFromFloat(@floor(y0f))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(y1f))));
        while (y < y_end) : (y += 1) {
            var x = @max(0, @as(i64, @intFromFloat(@floor(x0f))));
            const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(x1f))));
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const cx: f32 = @floatFromInt(x);
                const cy: f32 = @floatFromInt(y);
                if (distPointSeg(cx + 0.5, cy + 0.5, p0.x, p0.y, p1.x, p1.y) <= r) {
                    self.set(@intCast(x), @intCast(y), c);
                }
            }
        }
    }

    pub fn fillCircle(self: *Self, center: types.Vec2, radius: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(center.x) or !std.math.isFinite(center.y) or
            !std.math.isFinite(radius) or radius < 0) return;
        var y = @max(0, @as(i64, @intFromFloat(@floor(center.y - radius))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(center.y + radius))));
        while (y < y_end) : (y += 1) {
            var x = @max(0, @as(i64, @intFromFloat(@floor(center.x - radius))));
            const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(center.x + radius))));
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const cx: f32 = @floatFromInt(x);
                const cy: f32 = @floatFromInt(y);
                const dx = (cx + 0.5) - center.x;
                const dy = (cy + 0.5) - center.y;
                if (@sqrt(dx * dx + dy * dy) <= radius) {
                    self.set(@intCast(x), @intCast(y), c);
                }
            }
        }
    }

    /// Contorno circular de `thickness` px: anel entre `radius - t/2` e
    /// `radius + t/2` (cobertura AA por distância radial).
    pub fn strokeCircle(self: *Self, center: types.Vec2, radius: f32, thickness: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(center.x) or !std.math.isFinite(center.y) or
            !std.math.isFinite(radius) or radius < 0 or
            !std.math.isFinite(thickness) or thickness <= 0) return;
        const half = thickness / 2;
        const outer = radius + half;
        const inner = @max(0, radius - half);
        var y = @max(0, @as(i64, @intFromFloat(@floor(center.y - outer))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(center.y + outer))));
        while (y < y_end) : (y += 1) {
            var x = @max(0, @as(i64, @intFromFloat(@floor(center.x - outer))));
            const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(center.x + outer))));
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const cx: f32 = @floatFromInt(x);
                const cy: f32 = @floatFromInt(y);
                const dx = (cx + 0.5) - center.x;
                const dy = (cy + 0.5) - center.y;
                const d = @sqrt(dx * dx + dy * dy);
                // Cobertura do anel: 1 dentro de [inner, outer], borda AA.
                const cov = @min(
                    std.math.clamp(outer - d, 0, 1),
                    std.math.clamp(d - inner, 0, 1),
                );
                if (cov > 0) {
                    self.setAlpha(@intCast(x), @intCast(y), c, cov);
                }
            }
        }
    }

    /// Contorno circular tracejado: alterna `dash_len` px de arco
    /// (desenhados) e `gap_len` px (vazados), medidos ao longo da
    /// circunferência. Fase 0 no ângulo 0 (eixo +X).
    pub fn strokeCircleDashed(
        self: *Self,
        center: types.Vec2,
        radius: f32,
        thickness: f32,
        dash_len: f32,
        gap_len: f32,
        clip: ?types.Rect,
        c: types.Color,
    ) void {
        if (!std.math.isFinite(center.x) or !std.math.isFinite(center.y) or
            !std.math.isFinite(radius) or radius < 0 or
            !std.math.isFinite(thickness) or thickness <= 0 or
            !std.math.isFinite(dash_len) or dash_len <= 0 or
            !std.math.isFinite(gap_len) or gap_len <= 0) return;
        const half = thickness / 2;
        const outer = radius + half;
        const inner = @max(0, radius - half);
        const period = dash_len + gap_len;
        const circumference = 2 * std.math.pi * radius;
        // Se o perímetro cabe num único dash, desenha o anel inteiro.
        const full_dash = circumference <= dash_len;
        var y = @max(0, @as(i64, @intFromFloat(@floor(center.y - outer))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(center.y + outer))));
        while (y < y_end) : (y += 1) {
            var x = @max(0, @as(i64, @intFromFloat(@floor(center.x - outer))));
            const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(center.x + outer))));
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const cx: f32 = @floatFromInt(x);
                const cy: f32 = @floatFromInt(y);
                const dx = (cx + 0.5) - center.x;
                const dy = (cy + 0.5) - center.y;
                const d = @sqrt(dx * dx + dy * dy);
                const cov = @min(
                    std.math.clamp(outer - d, 0, 1),
                    std.math.clamp(d - inner, 0, 1),
                );
                if (cov <= 0) continue;
                // Fase ao longo do arco: ângulo medido desde +X.
                const ang = std.math.atan2(dy, dx);
                var arc = if (ang < 0) ang + 2 * std.math.pi else ang;
                arc = arc * radius; // comprimento de arco
                const phase = @mod(arc, period);
                if (!full_dash and phase > dash_len) continue;
                self.setAlpha(@intCast(x), @intCast(y), c, cov);
            }
        }
    }

    /// Distância assinada (negativa dentro) ao retângulo de cantos
    /// arredondados — o SDF usado pela cobertura AA e pela sombra.
    fn roundRectDist(px: f32, py: f32, r: types.Rect, rad: f32) f32 {
        const hw = r.w / 2;
        const hh = r.h / 2;
        const qx = @abs(px - (r.x + hw)) - (hw - rad);
        const qy = @abs(py - (r.y + hh)) - (hh - rad);
        const ox = @max(qx, 0);
        const oy = @max(qy, 0);
        return @sqrt(ox * ox + oy * oy) + @min(@max(qx, qy), 0) - rad;
    }

    /// Cobertura (0..1) do ponto (`px`,`py`) num retângulo de cantos
    /// arredondados: `< 0` dentro, `0` na borda. A conversão em cobertura
    /// usa meia-largura de 1px (borda AA).
    fn roundRectCoverage(px: f32, py: f32, r: types.Rect, rad: f32) f32 {
        return std.math.clamp(0.5 - roundRectDist(px, py, r, rad), 0, 1);
    }

    /// Retângulo de cantos arredondados via SDF: amostra o centro de
    /// cada pixel e mistura com o alfa ponderado pela cobertura (bordas
    /// anti-serrilhadas). `radius` clampado a `min(w,h)/2`; entradas
    /// não-finitas saturam em no-op.
    pub fn fillRoundRect(self: *Self, r: types.Rect, radius: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(radius) or radius < 0) return;
        if (r.w <= 0 or r.h <= 0 or c.a == 0) return;
        const rad = @min(radius, @min(r.w, r.h) / 2);
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(r.y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        const base_a: f32 = @floatFromInt(c.a);
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const cov = roundRectCoverage(fx + 0.5, fy + 0.5, r, rad);
                if (cov <= 0) continue;
                const fa: f32 = @round(cov * base_a);
                const ea: u8 = @intFromFloat(@min(fa, 255.0));
                if (ea == 0) continue;
                self.set(@intCast(x), @intCast(y), .{ .r = c.r, .g = c.g, .b = c.b, .a = ea });
            }
        }
    }

    /// Sombra projetada: a silhueta `r` é deslocada por `off` e atenuada
    /// em `blur` px (falloff linear centrado na borda — aproximação
    /// barata de blur via SDF, sem passe offscreen). `blur == 0` deixa a
    /// borda dura com 1px de AA. Entradas não-finitas saturam em no-op.
    pub fn fillShadow(
        self: *Self,
        r: types.Rect,
        radius: f32,
        off: types.Vec2,
        blur: f32,
        clip: ?types.Rect,
        c: types.Color,
    ) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(radius) or radius < 0 or
            !std.math.isFinite(off.x) or !std.math.isFinite(off.y) or
            !std.math.isFinite(blur) or blur < 0) return;
        if (r.w <= 0 or r.h <= 0 or c.a == 0) return;
        const sr = types.Rect{ .x = r.x + off.x, .y = r.y + off.y, .w = r.w, .h = r.h };
        const rad = @min(radius, @min(r.w, r.h) / 2);
        const pad = blur / 2 + 1;
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(sr.x - pad))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(sr.y - pad))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(sr.x + sr.w + pad))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(sr.y + sr.h + pad))));
        const denom = @max(blur, 1.0);
        const base_a: f32 = @floatFromInt(c.a);
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const d = roundRectDist(fx + 0.5, fy + 0.5, sr, rad);
                const cov = std.math.clamp(0.5 - d / denom, 0, 1);
                if (cov <= 0) continue;
                const fa: f32 = @round(cov * base_a);
                const ea: u8 = @intFromFloat(@min(fa, 255.0));
                if (ea == 0) continue;
                self.set(@intCast(x), @intCast(y), .{ .r = c.r, .g = c.g, .b = c.b, .a = ea });
            }
        }
    }

    /// Box blur separável (H depois V) do conteúdo atual, gravando apenas
    /// a interseção de `r` com `clip`. `radius` é arredondado para um raio
    /// inteiro de janela (clampado a 4096 px); amostragem clamp-to-edge
    /// contra as bordas do framebuffer (o "backdrop" fora de `r` conta).
    /// Canais RGBA desfocados independentemente (não premultiplicado).
    /// Requer `scratch` do tamanho de `pixels` (garantido por `init`);
    /// entradas não-finitas/raio < 0.5/região vazia saturam em no-op.
    pub fn blurRegion(self: *Self, r: types.Rect, radius: f32, clip: ?types.Rect) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(radius)) return;
        if (r.w <= 0 or r.h <= 0) return;
        const ir: i64 = @intFromFloat(@round(@min(radius, 4096)));
        if (ir <= 0) return;
        if (self.scratch.len < self.pixels.len) return;
        const iw: i64 = @intCast(self.w);
        const ih: i64 = @intCast(self.h);
        const x0 = @max(@as(i64, 0), @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(@as(i64, 0), @as(i64, @intFromFloat(@floor(r.y))));
        const x1 = @min(iw, @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y1 = @min(ih, @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        if (x1 <= x0 or y1 <= y0) return;
        const win: u32 = @intCast(2 * ir + 1);
        // Passo H: linhas da região expandidas de `ir` para cima/baixo,
        // para o passo V ler vizinhança válida no scratch.
        const hy0 = @max(@as(i64, 0), y0 - ir);
        const hy1 = @min(ih, y1 + ir);
        const w_us: usize = self.w;
        var y = hy0;
        while (y < hy1) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                var acc: [4]u32 = .{ 0, 0, 0, 0 };
                var d: i64 = -ir;
                while (d <= ir) : (d += 1) {
                    const sx: usize = @intCast(std.math.clamp(x + d, 0, iw - 1));
                    const si: usize = (@as(usize, @intCast(y)) * w_us + sx) * 4;
                    acc[0] += self.pixels[si];
                    acc[1] += self.pixels[si + 1];
                    acc[2] += self.pixels[si + 2];
                    acc[3] += self.pixels[si + 3];
                }
                const di: usize = (@as(usize, @intCast(y)) * w_us + @as(usize, @intCast(x))) * 4;
                self.scratch[di] = @intCast(acc[0] / win);
                self.scratch[di + 1] = @intCast(acc[1] / win);
                self.scratch[di + 2] = @intCast(acc[2] / win);
                self.scratch[di + 3] = @intCast(acc[3] / win);
            }
        }
        // Passo V: lê o scratch (já desfocado na horizontal) e grava.
        y = y0;
        while (y < y1) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                var acc: [4]u32 = .{ 0, 0, 0, 0 };
                var d: i64 = -ir;
                while (d <= ir) : (d += 1) {
                    const sy: usize = @intCast(std.math.clamp(y + d, 0, ih - 1));
                    const si: usize = (sy * w_us + @as(usize, @intCast(x))) * 4;
                    acc[0] += self.scratch[si];
                    acc[1] += self.scratch[si + 1];
                    acc[2] += self.scratch[si + 2];
                    acc[3] += self.scratch[si + 3];
                }
                const di: usize = (@as(usize, @intCast(y)) * w_us + @as(usize, @intCast(x))) * 4;
                self.pixels[di] = @intCast(acc[0] / win);
                self.pixels[di + 1] = @intCast(acc[1] / win);
                self.pixels[di + 2] = @intCast(acc[2] / win);
                self.pixels[di + 3] = @intCast(acc[3] / win);
            }
        }
    }

    /// Interpola um canal (0..255) por `tq` em 0..255 (arredondado).
    fn lerpChannel(a: u8, b: u8, tq: u32) u8 {
        return @intCast((@as(u32, a) * (255 - tq) + @as(u32, b) * tq + 127) / 255);
    }

    /// Gradiente linear dentro de `r`: `color0` em `from`, `color1` em
    /// `to`; o pixel é projetado no eixo e `t` é clampado a [0,1]
    /// (quantizado em 0..255 para resultados determinísticos). `from ==
    /// to` degenera em `color0` sólido; entradas não-finitas saturam em
    /// no-op.
    pub fn fillGradient(
        self: *Self,
        r: types.Rect,
        from: types.Vec2,
        to: types.Vec2,
        color0: types.Color,
        color1: types.Color,
        clip: ?types.Rect,
    ) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(from.x) or !std.math.isFinite(from.y) or
            !std.math.isFinite(to.x) or !std.math.isFinite(to.y)) return;
        if (r.w <= 0 or r.h <= 0) return;
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        const den = dx * dx + dy * dy;
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(r.y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const t: f32 = if (den <= 0) 0 else std.math.clamp(
                    ((fx + 0.5 - from.x) * dx + (fy + 0.5 - from.y) * dy) / den,
                    0,
                    1,
                );
                const tq: u32 = @intFromFloat(@round(t * 255.0));
                const c = types.Color{
                    .r = lerpChannel(color0.r, color1.r, tq),
                    .g = lerpChannel(color0.g, color1.g, tq),
                    .b = lerpChannel(color0.b, color1.b, tq),
                    .a = lerpChannel(color0.a, color1.a, tq),
                };
                self.set(@intCast(x), @intCast(y), c);
            }
        }
    }

    /// Preenchimento em gradiente RADIAL: `color0` no centro do `rect`,
    /// `color1` na borda (distância `radius` do centro). Distâncias
    /// acima de `radius` saturam em `color1`.
    pub fn fillGradientRadial(
        self: *Self,
        r: types.Rect,
        radius: f32,
        color0: types.Color,
        color1: types.Color,
        clip: ?types.Rect,
    ) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(radius) or radius < 0) return;
        if (r.w <= 0 or r.h <= 0) return;
        const cx = r.x + r.w / 2;
        const cy = r.y + r.h / 2;
        // Raio efetivo: o maior entre o pedido e a meia-diagonal
        // (para cobrir os cantos do rect).
        const half_diag = @sqrt((r.w / 2) * (r.w / 2) + (r.h / 2) * (r.h / 2));
        const eff_radius = if (radius > 0) radius else half_diag;
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(r.y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const dx = (fx + 0.5) - cx;
                const dy = (fy + 0.5) - cy;
                const dist = @sqrt(dx * dx + dy * dy);
                const t: f32 = if (eff_radius <= 0) 0 else std.math.clamp(dist / eff_radius, 0, 1);
                const tq: u32 = @intFromFloat(@round(t * 255.0));
                const c = types.Color{
                    .r = lerpChannel(color0.r, color1.r, tq),
                    .g = lerpChannel(color0.g, color1.g, tq),
                    .b = lerpChannel(color0.b, color1.b, tq),
                    .a = lerpChannel(color0.a, color1.a, tq),
                };
                self.set(@intCast(x), @intCast(y), c);
            }
        }
    }

    /// Preenchimento em gradiente CÔNICO: `color0` no ângulo
    /// `start_angle` (rad desde +X, anti-horário), `color1` em
    /// `start_angle + sweep`. O ângulo é projetado em [0, 2π).
    pub fn fillGradientConic(
        self: *Self,
        r: types.Rect,
        center: types.Vec2,
        start_angle: f32,
        sweep: f32,
        color0: types.Color,
        color1: types.Color,
        clip: ?types.Rect,
    ) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(center.x) or !std.math.isFinite(center.y) or
            !std.math.isFinite(start_angle) or !std.math.isFinite(sweep)) return;
        if (r.w <= 0 or r.h <= 0) return;
        const two_pi = 2 * std.math.pi;
        // Normaliza o sweep para [0, 2π]. Um sweep de volta completa
        // (|sweep| >= 2π) equivale a 2π (não 0) — evita que `@mod` de
        // exatamente 2π por 2π resulte em zero.
        var sw: f32 = undefined;
        if (@abs(sweep) >= two_pi) {
            sw = two_pi;
        } else {
            sw = @mod(sweep, two_pi);
            if (sw < 0) sw += two_pi;
        }
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(r.x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(r.y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(r.x + r.w))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(r.y + r.h))));
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @floatFromInt(x);
                const fy: f32 = @floatFromInt(y);
                const dx = (fx + 0.5) - center.x;
                const dy = (fy + 0.5) - center.y;
                // Ângulo anti-horário desde +X: atan2(dy, dx).
                var ang = std.math.atan2(dy, dx);
                if (ang < 0) ang += two_pi;
                // Desloca para o ângulo inicial e normaliza.
                var rel = @mod(ang - start_angle, two_pi);
                if (rel < 0) rel += two_pi;
                const t: f32 = if (sw <= 0) 0 else std.math.clamp(rel / sw, 0, 1);
                const tq: u32 = @intFromFloat(@round(t * 255.0));
                const c = types.Color{
                    .r = lerpChannel(color0.r, color1.r, tq),
                    .g = lerpChannel(color0.g, color1.g, tq),
                    .b = lerpChannel(color0.b, color1.b, tq),
                    .a = lerpChannel(color0.a, color1.a, tq),
                };
                self.set(@intCast(x), @intCast(y), c);
            }
        }
    }

    /// Reta tracejada entre `p0` e `p1`: alterna `dash_len` px de traço
    /// e `gap_len` px de vazio, medidos ao longo da reta. Fase 0 em `p0`.
    pub fn strokeLineDashed(
        self: *Self,
        p0: types.Vec2,
        p1: types.Vec2,
        thickness: f32,
        dash_len: f32,
        gap_len: f32,
        clip: ?types.Rect,
        c: types.Color,
    ) void {
        if (!std.math.isFinite(p0.x) or !std.math.isFinite(p0.y) or
            !std.math.isFinite(p1.x) or !std.math.isFinite(p1.y) or
            !std.math.isFinite(thickness) or thickness <= 0 or
            !std.math.isFinite(dash_len) or dash_len <= 0 or
            !std.math.isFinite(gap_len) or gap_len <= 0) return;
        const dx = p1.x - p0.x;
        const dy = p1.y - p0.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len <= 0) return;
        const half = thickness / 2;
        // Bounds: caixa da reta expandida pela meia-espessura.
        const min_x = @min(p0.x, p1.x) - half;
        const min_y = @min(p0.y, p1.y) - half;
        const max_x = @max(p0.x, p1.x) + half;
        const max_y = @max(p0.y, p1.y) + half;
        const x0 = @max(0, @as(i64, @intFromFloat(@floor(min_x))));
        const y0 = @max(0, @as(i64, @intFromFloat(@floor(min_y))));
        const x_end = @min(@as(i64, self.w), @as(i64, @intFromFloat(@ceil(max_x))));
        const y_end = @min(@as(i64, self.h), @as(i64, @intFromFloat(@ceil(max_y))));
        const period = dash_len + gap_len;
        var y = y0;
        while (y < y_end) : (y += 1) {
            var x = x0;
            while (x < x_end) : (x += 1) {
                if (!inClip(x, y, clip)) continue;
                const fx: f32 = @as(f32, @floatFromInt(x)) + 0.5;
                const fy: f32 = @as(f32, @floatFromInt(y)) + 0.5;
                // Projeção do pixel na reta (t em [0,1]).
                const t = std.math.clamp(
                    ((fx - p0.x) * dx + (fy - p0.y) * dy) / (len * len),
                    0,
                    1,
                );
                // Distância perpendicular à reta.
                const px = p0.x + dx * t;
                const py = p0.y + dy * t;
                const dist = @sqrt((fx - px) * (fx - px) + (fy - py) * (fy - py));
                if (dist > half) continue;
                // Fase do tracejado ao longo da reta.
                const arc = t * len;
                const phase = @mod(arc, period);
                if (phase > dash_len) continue;
                self.set(@intCast(x), @intCast(y), c);
            }
        }
    }

    pub fn strokeRect(self: *Self, r: types.Rect, thickness: f32, clip: ?types.Rect, c: types.Color) void {
        if (!std.math.isFinite(r.x) or !std.math.isFinite(r.y) or
            !std.math.isFinite(r.w) or !std.math.isFinite(r.h) or
            !std.math.isFinite(thickness) or thickness <= 0) return;
        const t = @max(1.0, thickness);
        // Barras superior/inferior (largura total) + laterais (entre elas).
        self.fillRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = @min(t, r.h) }, clip, c);
        self.fillRect(.{ .x = r.x, .y = r.y + r.h - @min(t, r.h), .w = r.w, .h = @min(t, r.h) }, clip, c);
        const mid_y = r.y + @min(t, r.h);
        const mid_h = @max(0, r.h - 2 * @min(t, r.h));
        if (mid_h > 0) {
            self.fillRect(.{ .x = r.x, .y = mid_y, .w = @min(t, r.w), .h = mid_h }, clip, c);
            self.fillRect(.{ .x = r.x + r.w - @min(t, r.w), .y = mid_y, .w = @min(t, r.w), .h = mid_h }, clip, c);
        }
    }
};

/// Estatísticas de uma submissão ao rasterizador.
pub const SoftwareStats = extern struct {
    submitted: u32 = 0,
    drawn: u32 = 0,
    culled: u32 = 0,
    skipped_text: u32 = 0,
};

/// Visibilidade via bounds canônicos (`draw/renderer.commandBounds`):
/// fonte única de verdade p/ culling (antes duplicada com fórmula
/// divergente p/ linhas). `null` = global (clear/clip-nulo).
fn boundsVisible(cmd: commands.DrawCommand, viewport: types.Rect) bool {
    const b = renderer.commandBounds(cmd) orelse return true;
    return overlaps(b, viewport);
}

fn overlaps(a: types.Rect, b: types.Rect) bool {
    if (a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0) return false;
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h;
}

/// Executa comandos no framebuffer (1px = 1px lógico). Texto é pulado
/// E contado (sem fonte, sem glifos). Comandos inválidos retornam erro
/// sem efeito parcial garantido além do já desenhado. `clear` limpa o
/// framebuffer INTEIRO (não só o viewport).
pub fn render(fb: *SoftwareFramebuffer, cmds: []const commands.DrawCommand, viewport: types.Rect) !SoftwareStats {
    return renderInternal(fb, cmds, viewport, null);
}

/// Executa comandos restringindo-se a `region` (interseção com
/// `viewport` e com o framebuffer) — repintura parcial dirigida pelo
/// dirty rect de `Context` (`ctx.dirty_rect`). Diferenças em relação a
/// `render`:
/// - `clear` limpa apenas a região efetiva (o resto do framebuffer é
///   preservado: é o frame anterior, que continua válido fora dela).
/// - Comandos cujo bounds não toca a região contam em `culled` e são
///   pulados; dentro dela valem o clip corrente e a interseção.
/// - Região vazia (ou disjunta do viewport) não desenha nada.
/// Correção é responsabilidade do chamador: marque como sujo tudo cujo
/// pixel final mudou. Efeitos que amostram vizinhos (`.blur`,
/// `.rect_shadow`) leem o framebuffer preservado — os vizinhos precisam
/// estar corretos (isto é, não sujos) na região marcada.
pub fn renderRegion(
    fb: *SoftwareFramebuffer,
    cmds: []const commands.DrawCommand,
    viewport: types.Rect,
    region: types.Rect,
) !SoftwareStats {
    return renderInternal(fb, cmds, viewport, region);
}

fn renderInternal(
    fb: *SoftwareFramebuffer,
    cmds: []const commands.DrawCommand,
    viewport: types.Rect,
    region: ?types.Rect,
) !SoftwareStats {
    var out = SoftwareStats{ .submitted = @intCast(cmds.len) };
    var clip: ?types.Rect = null;
    const vp = types.Rect{
        .x = @max(0, viewport.x),
        .y = @max(0, viewport.y),
        .w = @max(0, @min(viewport.w, @as(f32, @floatFromInt(fb.w)))),
        .h = @max(0, @min(viewport.h, @as(f32, @floatFromInt(fb.h)))),
    };
    // Área efetiva de desenho: viewport clampado ao fb (e, na repintura
    // parcial, também à região suja). No caminho integral `area == vp`,
    // então o desenho é idêntico ao histórico.
    const area = if (region) |r| intersect(vp, r) else vp;
    // Culling: no caminho integral mantém-se a checagem histórica contra
    // `viewport` (não o clampado), preservando as estatísticas; na
    // repintura parcial culla-se contra a área efetiva.
    const cull_rect = if (region == null) viewport else area;
    for (cmds) |cmd| {
        if (!cmd.isValid()) return error.InvalidCommand;
        switch (cmd) {
            .clear => |c| {
                // Parcial: preserva o resto do framebuffer.
                if (region == null) fb.clear(c.color) else fb.fillRect(area, null, c.color);
                out.drawn += 1;
            },
            .clip => |c| {
                clip = if (c.null_rect) null else c.rect;
                out.drawn += 1;
            },
            .text => {
                out.skipped_text += 1;
            },
            else => {
                if (!boundsVisible(cmd, cull_rect)) {
                    out.culled += 1;
                    continue;
                }
                switch (cmd) {
                    .rect_filled => |c| fb.fillRect(intersectClip(c.rect, clip, area), null, c.color),
                    .rect_outline => |c| fb.strokeRect(c.rect, c.thickness, mergeClip(clip, area), c.color),
                    .line => |c| fb.strokeLine(c.p0, c.p1, c.thickness, mergeClip(clip, area), c.color),
                    .circle_filled => |c| fb.fillCircle(c.center, c.radius, mergeClip(clip, area), c.color),
                    .circle_outline => |c| fb.strokeCircle(c.center, c.radius, c.thickness, mergeClip(clip, area), c.color),
                    .circle_dashed => |c| fb.strokeCircleDashed(c.center, c.radius, c.thickness, c.dash_len, c.gap_len, mergeClip(clip, area), c.color),
                    .rect_rounded => |c| fb.fillRoundRect(c.rect, c.radius, mergeClip(clip, area), c.color),
                    .rect_gradient => |c| fb.fillGradient(c.rect, c.p0, c.p1, c.color0, c.color1, mergeClip(clip, area)),
                    .rect_gradient_radial => |c| fb.fillGradientRadial(c.rect, c.radius, c.color0, c.color1, mergeClip(clip, area)),
                    .rect_gradient_conic => |c| fb.fillGradientConic(c.rect, c.center, c.start_angle, c.sweep, c.color0, c.color1, mergeClip(clip, area)),
                    .line_dashed => |c| fb.strokeLineDashed(c.p0, c.p1, c.thickness, c.dash_len, c.gap_len, mergeClip(clip, area), c.color),
                    .rect_shadow => |c| fb.fillShadow(c.rect, c.radius, c.offset, c.blur, mergeClip(clip, area), c.color),
                    .blur => |c| fb.blurRegion(c.rect, c.radius, mergeClip(clip, area)),
                    else => unreachable,
                }
                out.drawn += 1;
            },
        }
    }
    return out;
}

/// Interseção de dois rects (vazio se disjuntos).
fn intersect(a: types.Rect, b: types.Rect) types.Rect {
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    return .{
        .x = x,
        .y = y,
        .w = @max(0, @min(a.x + a.w, b.x + b.w) - x),
        .h = @max(0, @min(a.y + a.h, b.y + b.h) - y),
    };
}

fn intersectClip(r: types.Rect, clip: ?types.Rect, vp: types.Rect) types.Rect {
    var out = intersect(r, vp);
    if (clip) |cp| out = intersect(out, cp);
    return out;
}

/// Combina clip de usuário + viewport num único rect-ou-nulo.
fn mergeClip(clip: ?types.Rect, vp: types.Rect) ?types.Rect {
    const cp = clip orelse return vp;
    return intersect(cp, vp);
}

/// PPM binário (P6) em `out`. Retorna bytes usados; `NoSpaceLeft` se
/// o buffer for curto. Alfa descartado (sem blending — documentado).
pub fn encodePpm(fb: *const SoftwareFramebuffer, out: []u8) !usize {
    const head = try std.fmt.bufPrint(out, "P6\n{d} {d}\n255\n", .{ fb.w, fb.h });
    const need = head.len + @as(usize, fb.w) * fb.h * 3;
    if (out.len < need) return error.NoSpaceLeft;
    var o = head.len;
    var i: usize = 0;
    while (i < fb.pixels.len) : (i += 4) {
        out[o] = fb.pixels[i];
        out[o + 1] = fb.pixels[i + 1];
        out[o + 2] = fb.pixels[i + 2];
        o += 3;
    }
    return o;
}

test "raster rect + clear pixel-exato" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 8, 8);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(7, 7));

    fb.fillRect(types.Rect.init(2, 2, 2, 2), null, types.Color.rgb(255, 0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(2, 2));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(3, 3));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(4, 4));

    // Clip restringe; fora da área nada muda.
    fb.fillRect(types.Rect.init(0, 0, 8, 8), types.Rect.init(0, 0, 1, 1), types.Color.rgb(0, 255, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 255, 0, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 0));

    try stdt.testing.expectError(error.InvalidArgument, SoftwareFramebuffer.init(gpa, 0, 8));
    try stdt.testing.expectError(error.InvalidArgument, SoftwareFramebuffer.init(gpa, 99999, 8));
}

test "raster linha diagonal e círculo" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));

    fb.strokeLine(.{ .x = 0, .y = 0 }, .{ .x = 3, .y = 3 }, 1.0, null, types.Color.rgb(0, 0, 255));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 255, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 255, 255 }, fb.get(2, 2));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 0)); // vizinho fora do raio 0.5
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(0, 1));

    fb.fillCircle(.{ .x = 7, .y = 7 }, 2.0, null, types.Color.rgb(255, 255, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 0, 255 }, fb.get(7, 7));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 0, 255 }, fb.get(8, 7)); // dist 1.5 <= 2
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(9, 9)); // dist ~3.5 > 2
}

test "render pipeline: clear, clip, cull, texto pulado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 100, 100);
    defer fb.deinit(gpa);
    const vp = types.Rect.init(0, 0, 100, 100);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(10, 10, 10) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(255, 0, 0) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(500, 500, 20, 20), .color = types.Color.rgb(0, 255, 0) } },
        .{ .clip = .{ .rect = types.Rect.init(0, 0, 15, 15), .null_rect = false } },
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(0, 0, 255) } },
        .{ .text = .{ .pos = .{ .x = 0, .y = 0 }, .color = types.Color.rgb(255, 255, 255), .size = 16, .width = 10, .start = 0, .len = 0 } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 6), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 4), s.drawn); // clear + rect + clip + rect(clippado)
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    try stdt.testing.expectEqual(@as(u32, 1), s.skipped_text);
    // Segundo rect (azul) só pintou a interseção com o clip [10,15):
    try stdt.testing.expectEqual([4]u8{ 0, 0, 255, 255 }, fb.get(12, 12));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(16, 16));
    try stdt.testing.expectEqual([4]u8{ 10, 10, 10, 255 }, fb.get(50, 50));

    const bad = [_]commands.DrawCommand{
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, -1, 5), .color = types.Color.rgb(0, 0, 0) } },
    };
    try stdt.testing.expectError(error.InvalidCommand, render(&fb, &bad, vp));
}

test "encodePpm cabeçalho e bytes exatos" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 2, 1);
    defer fb.deinit(gpa);
    fb.set(0, 0, types.Color.rgb(255, 0, 0));
    fb.set(1, 0, types.Color.rgb(0, 255, 0));
    var out: [32]u8 = undefined;
    const n = try encodePpm(&fb, &out);
    try stdt.testing.expectEqualStrings("P6\n2 1\n255\n", out[0..11]);
    try stdt.testing.expectEqual(@as(usize, 17), n);
    try stdt.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 0, 255, 0 }, out[11..17]);
    var tiny: [5]u8 = undefined;
    try stdt.testing.expectError(error.NoSpaceLeft, encodePpm(&fb, &tiny));
}

test "raster entradas não-finitas saturam em no-op" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 8, 8);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(1, 2, 3));
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const c = types.Color.rgb(9, 9, 9);

    // Nenhuma entrada degenerada pode travar/estourar; tudo vira no-op
    // e o buffer permanece intacto.
    fb.fillRect(types.Rect.init(nan, 0, 4, 4), null, c);
    fb.fillRect(types.Rect.init(0, 0, inf, 4), null, c);
    fb.strokeLine(.{ .x = nan, .y = 0 }, .{ .x = 1, .y = 1 }, 1, null, c);
    fb.strokeLine(.{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, nan, null, c);
    fb.fillCircle(.{ .x = nan, .y = nan }, 2, null, c);
    fb.fillCircle(.{ .x = 4, .y = 4 }, nan, null, c);
    fb.strokeRect(types.Rect.init(0, 0, inf, inf), 1, null, c);
    for (0..8) |y| {
        for (0..8) |x| {
            try stdt.testing.expectEqual([4]u8{ 1, 2, 3, 255 }, fb.get(@intCast(x), @intCast(y)));
        }
    }
}
test "fuzz primitivas: sem crash com bits arbitrários" {
    try std.testing.fuzz({}, fuzzRaster, .{});
}

fn fuzzRaster(_: void, smith: *std.testing.Smith) !void {
    var backing: [16 * 16 * 4]u8 = undefined;
    smith.bytes(&backing);
    var scratch: [16 * 16 * 4]u8 = undefined;
    var fb = SoftwareFramebuffer{ .w = 16, .h = 16, .pixels = &backing, .scratch = &scratch };

    var fb2: [16]u8 = undefined;
    smith.bytes(&fb2);
    const bits: [4]f32 = @bitCast(fb2);
    const r = types.Rect{ .x = bits[0], .y = bits[1], .w = bits[2], .h = bits[3] };
    const p0 = types.Vec2{ .x = bits[0], .y = bits[1] };
    const p1 = types.Vec2{ .x = bits[2], .y = bits[3] };
    const c = types.Color{ .r = 1, .g = 2, .b = 3, .a = 4 };

    // Nenhuma chamada pode travar/estourar: conversão insegura seria
    // panic no build com safety (o que o fuzz denunciaria).
    fb.fillRect(r, null, c);
    fb.fillRect(r, types.Rect.init(-100, -100, 1000, 1000), c);
    fb.strokeLine(p0, p1, @abs(bits[0]) + 1, null, c);
    fb.fillCircle(p0, @abs(bits[1]), null, c);
    fb.strokeRect(r, @abs(bits[2]) + 1, null, c);
    fb.fillRoundRect(r, @abs(bits[3]), null, c);
    fb.fillRoundRect(r, @abs(bits[3]), types.Rect.init(-100, -100, 1000, 1000), c);
    fb.fillGradient(r, p0, p1, c, c, null);
    fb.fillGradient(r, p0, p1, c, c, types.Rect.init(-100, -100, 1000, 1000));
    fb.fillShadow(r, @abs(bits[3]), p0, @abs(bits[1]), null, c);
    fb.fillShadow(r, @abs(bits[3]), p0, @abs(bits[1]), types.Rect.init(-100, -100, 1000, 1000), c);
    fb.blurRegion(r, @abs(bits[2]), null);
    fb.blurRegion(r, @abs(bits[2]), types.Rect.init(-100, -100, 1000, 1000));

    // Invariante estrutural: tamanho do buffer intacto.
    try std.testing.expectEqual(@as(usize, 16 * 16 * 4), fb.pixels.len);
}

test "raster blending source-over com arredondamento" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 4, 4);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));

    // Vermelho 50% sobre preto: (255*128+127)/255 = 128.
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, .{ .r = 255, .g = 0, .b = 0, .a = 128 });
    try stdt.testing.expectEqual([4]u8{ 128, 0, 0, 255 }, fb.get(0, 0));

    // Segunda demão: (255*128+128*127+127)/255 = 192.
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, .{ .r = 255, .g = 0, .b = 0, .a = 128 });
    try stdt.testing.expectEqual([4]u8{ 192, 0, 0, 255 }, fb.get(0, 0));

    // Transparente não toca; opaco sobrescreve exato (legado).
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
    try stdt.testing.expectEqual([4]u8{ 192, 0, 0, 255 }, fb.get(0, 0));
    fb.fillRect(types.Rect.init(0, 0, 4, 4), null, types.Color.rgb(1, 2, 3));
    try stdt.testing.expectEqual([4]u8{ 1, 2, 3, 255 }, fb.get(0, 0));
}

test "render e cull concordam na fronteira (bounds canônicos)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 100, 100);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    const vp = types.Rect.init(0, 0, 100, 100);
    // Linha em y=101, espessura 2: bounds canônicos [100,102) não
    // sobrepõem [0,100) (borda exclusiva) → cull. A fórmula antiga
    // ([99,103)) a considerava visível: divergência eliminada.
    const cmds = [_]commands.DrawCommand{
        .{ .rect_filled = .{ .rect = types.Rect.init(10, 10, 20, 20), .color = types.Color.rgb(255, 0, 0) } },
        .{ .line = .{
            .p0 = types.Vec2.init(0, 101),
            .p1 = types.Vec2.init(50, 101),
            .color = types.Color.rgb(0, 255, 0),
            .thickness = 2,
        } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 1), s.drawn);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    const c = renderer.cull(&cmds, vp);
    try stdt.testing.expectEqual(s.culled, c.culled);
    try stdt.testing.expectEqual(s.submitted, c.submitted);
    // E o pixel da linha inexistente confirma: nada desenhado fora.
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(10, 99));
}

test "raster retângulo arredondado: cantos, AA e clamp do raio" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Cantos cortados pelo arco; meio das arestas e miolo cheios.
    var fb = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillRoundRect(types.Rect.init(0, 0, 10, 10), 3.0, null, types.Color.rgb(255, 0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(9, 9));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(5, 5));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(5, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(0, 5));

    // Borda AA: arestas em x=0.5 e x=3.5 → colunas 0 e 3 a 50%.
    var fb2 = try SoftwareFramebuffer.init(gpa, 4, 4);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.fillRoundRect(types.Rect.init(0.5, 0, 3, 4), 0, null, types.Color.rgb(255, 255, 255));
    try stdt.testing.expectEqual([4]u8{ 128, 128, 128, 255 }, fb2.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 128, 128, 128, 255 }, fb2.get(3, 0));

    // Raio clampado a min(w,h)/2: 10x10 com raio 100 vira o círculo inscrito.
    var fb3 = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.fillRoundRect(types.Rect.init(0, 0, 10, 10), 100, null, types.Color.rgb(0, 255, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 255, 0, 255 }, fb3.get(5, 5));

    // Clip restringe; transparente/não-finito/vazio saturam em no-op.
    fb3.fillRoundRect(types.Rect.init(0, 0, 10, 10), 2, types.Rect.init(4, 4, 2, 2), types.Color.rgb(255, 0, 255));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 255, 255 }, fb3.get(4, 4));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(1, 0));
    const before = fb3.get(5, 5);
    fb3.fillRoundRect(types.Rect.init(0, 0, 10, 10), 2, null, .{ .r = 9, .g = 9, .b = 9, .a = 0 });
    fb3.fillRoundRect(types.Rect.init(std.math.nan(f32), 0, 4, 4), 2, null, types.Color.rgb(9, 9, 9));
    fb3.fillRoundRect(types.Rect.init(0, 0, 4, 4), std.math.nan(f32), null, types.Color.rgb(9, 9, 9));
    fb3.fillRoundRect(types.Rect.init(0, 0, 0, 4), 2, null, types.Color.rgb(9, 9, 9));
    try stdt.testing.expectEqual(before, fb3.get(5, 5));
}

test "render com retângulo arredondado (drawn + cull)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 40, 40);
    defer fb.deinit(gpa);
    const vp = types.Rect.init(0, 0, 40, 40);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } },
        .{ .rect_rounded = .{ .rect = types.Rect.init(4, 4, 16, 16), .radius = 4, .color = types.Color.rgb(255, 0, 0) } },
        .{ .rect_rounded = .{ .rect = types.Rect.init(500, 500, 16, 16), .radius = 4, .color = types.Color.rgb(0, 255, 0) } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 3), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 2), s.drawn);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(4, 4)); // canto cortado
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb.get(12, 12)); // miolo
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(20, 20)); // fora
}

test "raster gradiente linear: horizontal, vertical, degenerado e clip" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Horizontal preto→branco em 4 px: t = .125/.375/.625/.875.
    var fb = try SoftwareFramebuffer.init(gpa, 4, 2);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillGradient(
        types.Rect.init(0, 0, 4, 2),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 32, 32, 32, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 96, 96, 96, 255 }, fb.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 159, 159, 159, 255 }, fb.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 223, 223, 223, 255 }, fb.get(3, 0));
    try stdt.testing.expectEqual([4]u8{ 32, 32, 32, 255 }, fb.get(0, 1)); // eixo horizontal

    // Vertical: eixo (0,0)→(0,2), t = .25 e .75.
    var fb2 = try SoftwareFramebuffer.init(gpa, 2, 2);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.fillGradient(
        types.Rect.init(0, 0, 2, 2),
        types.Vec2.init(0, 0),
        types.Vec2.init(0, 2),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 64, 64, 64, 255 }, fb2.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 191, 191, 191, 255 }, fb2.get(0, 1));

    // Eixo degenerado (from == to) → color0 sólido.
    var fb3 = try SoftwareFramebuffer.init(gpa, 3, 1);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.fillGradient(
        types.Rect.init(0, 0, 3, 1),
        types.Vec2.init(1, 0),
        types.Vec2.init(1, 0),
        types.Color.rgb(10, 20, 30),
        types.Color.rgb(200, 200, 200),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 10, 20, 30, 255 }, fb3.get(1, 0));

    // Fora do eixo clampa em color0/color1.
    var fb4 = try SoftwareFramebuffer.init(gpa, 3, 1);
    defer fb4.deinit(gpa);
    fb4.clear(types.Color.rgb(0, 0, 0));
    fb4.fillGradient(
        types.Rect.init(0, 0, 3, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(1, 0),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 128, 128, 128, 255 }, fb4.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb4.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb4.get(2, 0));

    // Clip; alfa herdado; retângulo vazio/não-finito = no-op.
    var fb5 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb5.deinit(gpa);
    fb5.clear(types.Color.rgb(0, 0, 0));
    fb5.fillGradient(
        types.Rect.init(0, 0, 4, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(255, 0, 0),
        types.Color.rgb(255, 0, 0),
        types.Rect.init(1, 0, 2, 1),
    );
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb5.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 0, 0, 255 }, fb5.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb5.get(3, 0));
    fb5.fillGradient(
        types.Rect.init(0, 0, 4, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        .{ .r = 255, .g = 0, .b = 0, .a = 128 },
        .{ .r = 255, .g = 0, .b = 0, .a = 128 },
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 128, 0, 0, 255 }, fb5.get(0, 0));
    const before = fb5.get(2, 0);
    fb5.fillGradient(
        types.Rect.init(0, 0, 0, 1),
        types.Vec2.init(0, 0),
        types.Vec2.init(1, 0),
        types.Color.rgb(9, 9, 9),
        types.Color.rgb(9, 9, 9),
        null,
    );
    fb5.fillGradient(
        types.Rect.init(0, 0, 4, 1),
        types.Vec2.init(std.math.nan(f32), 0),
        types.Vec2.init(4, 0),
        types.Color.rgb(9, 9, 9),
        types.Color.rgb(9, 9, 9),
        null,
    );
    try stdt.testing.expectEqual(before, fb5.get(2, 0));
}

test "raster sombra projetada: offset, blur, raio e no-op" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Deslocamento puro (blur 0): a silhueta anda com o offset e o antigo
    // lugar fica limpo.
    var fb = try SoftwareFramebuffer.init(gpa, 12, 6);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillShadow(
        types.Rect.init(0, 0, 4, 4),
        0,
        types.Vec2.init(6, 0),
        0,
        null,
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 2));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb.get(7, 2));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(11, 2));

    // Atenuação linear: cov = clamp(0.5 - d/blur) sobre a borda.
    var fb2 = try SoftwareFramebuffer.init(gpa, 16, 16);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.fillShadow(
        types.Rect.init(0, 0, 10, 10),
        0,
        types.Vec2.init(0, 0),
        8,
        null,
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(5, 5)); // fundo cheio
    try stdt.testing.expectEqual([4]u8{ 143, 143, 143, 255 }, fb2.get(0, 0)); // d=-0.5
    try stdt.testing.expectEqual([4]u8{ 175, 175, 175, 255 }, fb2.get(1, 1)); // d=-1.5
    try stdt.testing.expectEqual([4]u8{ 48, 48, 48, 255 }, fb2.get(12, 8)); // fora, d=2.5

    // Raio arredonda a silhueta; canto cortado, centro cheio.
    var fb3 = try SoftwareFramebuffer.init(gpa, 10, 10);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.fillShadow(
        types.Rect.init(0, 0, 10, 10),
        5,
        types.Vec2.init(0, 0),
        0,
        null,
        types.Color.rgb(0, 255, 0),
    );
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 255, 0, 255 }, fb3.get(5, 5));

    // Alfa herda o blending (50% preto sobre branco) e no-ops não pintam.
    var fb4 = try SoftwareFramebuffer.init(gpa, 8, 4);
    defer fb4.deinit(gpa);
    fb4.clear(types.Color.rgb(255, 255, 255));
    fb4.fillShadow(
        types.Rect.init(0, 0, 4, 4),
        0,
        types.Vec2.init(0, 0),
        0,
        null,
        .{ .r = 0, .g = 0, .b = 0, .a = 128 },
    );
    try stdt.testing.expectEqual([4]u8{ 127, 127, 127, 255 }, fb4.get(1, 1));
    const before = fb4.get(6, 0);
    fb4.fillShadow(types.Rect.init(0, 0, 4, 4), 0, types.Vec2.init(0, 0), -1, null, types.Color.rgb(9, 9, 9));
    fb4.fillShadow(types.Rect.init(0, 0, 0, 4), 0, types.Vec2.init(0, 0), 2, null, types.Color.rgb(9, 9, 9));
    fb4.fillShadow(types.Rect.init(0, 0, 4, 4), 0, types.Vec2.init(std.math.nan(f32), 0), 2, null, types.Color.rgb(9, 9, 9));
    fb4.fillShadow(types.Rect.init(0, 0, 4, 4), 0, types.Vec2.init(0, 0), 2, null, .{ .r = 9, .g = 9, .b = 9, .a = 0 });
    try stdt.testing.expectEqual(before, fb4.get(6, 0));
}

test "render com sombra projetada (drawn + cull)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    var fb = try SoftwareFramebuffer.init(gpa, 60, 40);
    defer fb.deinit(gpa);
    const vp = types.Rect.init(0, 0, 60, 40);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } },
        .{ .rect_shadow = .{
            .rect = types.Rect.init(10, 10, 20, 20),
            .radius = 4,
            .offset = types.Vec2.init(4, 4),
            .blur = 8,
            .color = .{ .r = 255, .g = 255, .b = 255, .a = 128 },
        } },
        .{ .rect_shadow = .{
            .rect = types.Rect.init(500, 500, 20, 20),
            .radius = 4,
            .offset = types.Vec2.init(4, 4),
            .blur = 4,
            .color = .{ .r = 255, .g = 255, .b = 255, .a = 128 },
        } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 3), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 2), s.drawn);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    // Miolo da sombra (bem dentro da silhueta deslocada) pintado;
    // fora do raio de atenuação permanece limpo.
    try stdt.testing.expect(fb.get(24, 24)[0] > 0);
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(58, 38));
}

test "raster blur: box blur separável, região e clip" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Borda vertical [0,255,255,0]: raio 1 suaviza em [85,170,170,85].
    var fb = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillRect(types.Rect.init(1, 0, 2, 1), null, types.Color.rgb(255, 255, 255));
    fb.blurRegion(types.Rect.init(0, 0, 4, 1), 1, null);
    try stdt.testing.expectEqual([4]u8{ 85, 85, 85, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 170, 170, 170, 255 }, fb.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 170, 170, 170, 255 }, fb.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 85, 85, 85, 255 }, fb.get(3, 0));

    // 2D: pixel branco central espalha 28 (85/3) na vizinhança 3x3.
    var fbd = try SoftwareFramebuffer.init(gpa, 5, 5);
    defer fbd.deinit(gpa);
    fbd.clear(types.Color.rgb(0, 0, 0));
    fbd.fillRect(types.Rect.init(2, 2, 1, 1), null, types.Color.rgb(255, 255, 255));
    fbd.blurRegion(types.Rect.init(0, 0, 5, 5), 1, null);
    try stdt.testing.expectEqual([4]u8{ 28, 28, 28, 255 }, fbd.get(2, 2));
    try stdt.testing.expectEqual([4]u8{ 28, 28, 28, 255 }, fbd.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 28, 28, 28, 255 }, fbd.get(3, 3));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fbd.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fbd.get(4, 4));

    // Fora da região não muda; raio < 0.5, região vazia e NaN = no-op.
    var fb2 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.fillRect(types.Rect.init(1, 0, 2, 1), null, types.Color.rgb(255, 255, 255));
    fb2.blurRegion(types.Rect.init(0, 0, 2, 1), 1, null);
    try stdt.testing.expectEqual([4]u8{ 85, 85, 85, 255 }, fb2.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 170, 170, 170, 255 }, fb2.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb2.get(3, 0));
    fb2.blurRegion(types.Rect.init(0, 0, 4, 1), 0.4, null);
    fb2.blurRegion(types.Rect.init(0, 0, 0, 1), 2, null);
    fb2.blurRegion(types.Rect.init(0, 0, 4, 1), std.math.nan(f32), null);
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(2, 0));

    // Clip limita a escrita (o desfoque ainda lê o backdrop inteiro).
    var fb3 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.fillRect(types.Rect.init(1, 0, 2, 1), null, types.Color.rgb(255, 255, 255));
    fb3.blurRegion(types.Rect.init(0, 0, 4, 1), 1, types.Rect.init(1, 0, 1, 1));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 170, 170, 170, 255 }, fb3.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb3.get(2, 0));

    // Região uniforme permanece uniforme (inclusive alfa).
    var fb4 = try SoftwareFramebuffer.init(gpa, 3, 3);
    defer fb4.deinit(gpa);
    fb4.clear(types.Color.rgb(40, 80, 120));
    fb4.blurRegion(types.Rect.init(0, 0, 3, 3), 4, null);
    try stdt.testing.expectEqual([4]u8{ 40, 80, 120, 255 }, fb4.get(1, 1));
}

test "render com blur (ordem importa, drawn + cull)" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const vp = types.Rect.init(0, 0, 4, 1);

    // Blur DEPOIS do desenho: desfoca.
    var fb = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb.deinit(gpa);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(1, 0, 2, 1), .color = types.Color.rgb(255, 255, 255) } },
        .{ .blur = .{ .rect = types.Rect.init(0, 0, 4, 1), .radius = 1 } },
        .{ .blur = .{ .rect = types.Rect.init(500, 0, 4, 1), .radius = 1 } },
    };
    const s = try render(&fb, &cmds, vp);
    try stdt.testing.expectEqual(@as(u32, 4), s.submitted);
    try stdt.testing.expectEqual(@as(u32, 3), s.drawn);
    try stdt.testing.expectEqual(@as(u32, 1), s.culled);
    try stdt.testing.expectEqual([4]u8{ 85, 85, 85, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 170, 170, 170, 255 }, fb.get(1, 0));

    // Blur ANTES do desenho: o retângulo desenhado depois fica nítido.
    var fb2 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb2.deinit(gpa);
    const cmds2 = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(0, 0, 0) } },
        .{ .blur = .{ .rect = types.Rect.init(0, 0, 4, 1), .radius = 1 } },
        .{ .rect_filled = .{ .rect = types.Rect.init(1, 0, 2, 1), .color = types.Color.rgb(255, 255, 255) } },
    };
    _ = try render(&fb2, &cmds2, vp);
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb2.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb2.get(1, 0));
}

test "renderRegion repinta só a região suja e preserva o resto" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const vp = types.Rect.init(0, 0, 12, 4);
    const bg = types.Color.rgb(10, 10, 10);
    const box_a = types.Rect.init(0, 0, 4, 4);
    const box_b = types.Rect.init(8, 0, 4, 4);

    var fb = try SoftwareFramebuffer.init(gpa, 12, 4);
    defer fb.deinit(gpa);

    // Frame 1 (integral): fundo escuro + A e B cinza.
    const frame1 = [_]commands.DrawCommand{
        .{ .clear = .{ .color = bg } },
        .{ .rect_filled = .{ .rect = box_a, .color = types.Color.rgb(100, 100, 100) } },
        .{ .rect_filled = .{ .rect = box_b, .color = types.Color.rgb(100, 100, 100) } },
    };
    const s1 = try render(&fb, &frame1, vp);
    try stdt.testing.expectEqual(@as(u32, 3), s1.drawn);
    try stdt.testing.expectEqual([4]u8{ 100, 100, 100, 255 }, fb.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 100, 100, 100, 255 }, fb.get(9, 1));
    try stdt.testing.expectEqual([4]u8{ 10, 10, 10, 255 }, fb.get(6, 1));

    // Frame 2: só A mudou (ex.: hover). A região suja é o rect de A.
    const frame2 = [_]commands.DrawCommand{
        .{ .clear = .{ .color = bg } },
        .{ .rect_filled = .{ .rect = box_a, .color = types.Color.rgb(200, 200, 200) } },
        .{ .rect_filled = .{ .rect = box_b, .color = types.Color.rgb(100, 100, 100) } },
    };
    const s2 = try renderRegion(&fb, &frame2, vp, box_a);
    try stdt.testing.expectEqual(@as(u32, 3), s2.submitted);
    try stdt.testing.expectEqual(@as(u32, 2), s2.drawn); // clear parcial + A
    try stdt.testing.expectEqual(@as(u32, 1), s2.culled); // B fora da região
    // A repintado; B e o vão seguem do frame 1 (o clear não os tocou).
    try stdt.testing.expectEqual([4]u8{ 200, 200, 200, 255 }, fb.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 100, 100, 100, 255 }, fb.get(9, 1));
    try stdt.testing.expectEqual([4]u8{ 10, 10, 10, 255 }, fb.get(6, 1));
    try stdt.testing.expectEqual([4]u8{ 10, 10, 10, 255 }, fb.get(5, 3));
}

test "renderRegion: interseção com viewport, região vazia e clip do usuário" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const vp = types.Rect.init(0, 0, 12, 4);

    var fb = try SoftwareFramebuffer.init(gpa, 12, 4);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(7, 7, 7));
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(1, 1, 1) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, 4, 4), .color = types.Color.rgb(50, 0, 0) } },
        .{ .rect_filled = .{ .rect = types.Rect.init(8, 0, 4, 4), .color = types.Color.rgb(0, 60, 0) } },
    };

    // Região maior que o viewport: efetiva = interseção (10,0,2,4).
    const s = try renderRegion(&fb, &cmds, vp, types.Rect.init(10, 0, 100, 4));
    try stdt.testing.expectEqual(@as(u32, 2), s.drawn); // clear parcial + B
    try stdt.testing.expectEqual(@as(u32, 1), s.culled); // A
    try stdt.testing.expectEqual([4]u8{ 0, 60, 0, 255 }, fb.get(10, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 60, 0, 255 }, fb.get(11, 3));
    try stdt.testing.expectEqual([4]u8{ 7, 7, 7, 255 }, fb.get(9, 0)); // fora: intocado
    try stdt.testing.expectEqual([4]u8{ 7, 7, 7, 255 }, fb.get(0, 0));

    // Região vazia: `clear` executa (no-op em pixels), retângulos cullados.
    const empty = try renderRegion(&fb, &cmds, vp, types.Rect.init(0, 0, 0, 0));
    try stdt.testing.expectEqual(@as(u32, 1), empty.drawn);
    try stdt.testing.expectEqual(@as(u32, 2), empty.culled);
    try stdt.testing.expectEqual([4]u8{ 7, 7, 7, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 60, 0, 255 }, fb.get(10, 0));

    // Região disjunta do viewport (fora do framebuffer): nada muda.
    const outside = try renderRegion(&fb, &cmds, vp, types.Rect.init(100, 100, 4, 4));
    try stdt.testing.expectEqual(@as(u32, 2), outside.culled);
    try stdt.testing.expectEqual([4]u8{ 7, 7, 7, 255 }, fb.get(0, 0));

    // Clip do usuário continua restringindo dentro da região.
    var fb2 = try SoftwareFramebuffer.init(gpa, 12, 4);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(7, 7, 7));
    const clipped = [_]commands.DrawCommand{
        .{ .clip = .{ .rect = types.Rect.init(0, 0, 2, 2), .null_rect = false } },
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, 4, 4), .color = types.Color.rgb(90, 0, 0) } },
    };
    _ = try renderRegion(&fb2, &clipped, vp, types.Rect.init(0, 0, 4, 4));
    try stdt.testing.expectEqual([4]u8{ 90, 0, 0, 255 }, fb2.get(1, 1));
    try stdt.testing.expectEqual([4]u8{ 7, 7, 7, 255 }, fb2.get(2, 2));
    try stdt.testing.expectEqual([4]u8{ 7, 7, 7, 255 }, fb2.get(5, 1));
}

test "renderRegion com região == viewport == framebuffer equivale ao integral" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;
    const vp = types.Rect.init(0, 0, 8, 2);
    const cmds = [_]commands.DrawCommand{
        .{ .clear = .{ .color = types.Color.rgb(3, 3, 3) } },
        .{ .clip = .{ .rect = types.Rect.init(0, 0, 6, 2), .null_rect = false } },
        .{ .rect_filled = .{ .rect = types.Rect.init(0, 0, 8, 2), .color = types.Color.rgb(200, 10, 10) } },
        .{ .clip = .{ .rect = types.Rect.init(0, 0, 0, 0), .null_rect = true } },
        .{ .rect_filled = .{ .rect = types.Rect.init(7, 0, 1, 2), .color = types.Color.rgb(10, 200, 10) } },
        .{ .line = .{ .p0 = .{ .x = 1, .y = 0 }, .p1 = .{ .x = 6, .y = 1 }, .color = types.Color.rgb(255, 255, 0), .thickness = 1 } },
        .{ .text = .{ .pos = .{ .x = 0, .y = 0 }, .color = types.Color.rgb(255, 255, 255), .size = 8, .width = 4, .start = 0, .len = 0 } },
    };

    var full = try SoftwareFramebuffer.init(gpa, 8, 2);
    defer full.deinit(gpa);
    var region = try SoftwareFramebuffer.init(gpa, 8, 2);
    defer region.deinit(gpa);

    const sf = try render(&full, &cmds, vp);
    const sr = try renderRegion(&region, &cmds, vp, vp);
    try stdt.testing.expectEqual(sf.submitted, sr.submitted);
    try stdt.testing.expectEqual(sf.drawn, sr.drawn);
    try stdt.testing.expectEqual(sf.culled, sr.culled);
    try stdt.testing.expectEqual(sf.skipped_text, sr.skipped_text);
    var y: u32 = 0;
    while (y < 2) : (y += 1) {
        var x: u32 = 0;
        while (x < 8) : (x += 1) {
            try stdt.testing.expectEqual(full.get(x, y), region.get(x, y));
        }
    }
}

test "raster gradiente radial: centro→borda, clamp e degenerado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // 5x5, centro (2,2), radius 2: t = dist/2.
    var fb = try SoftwareFramebuffer.init(gpa, 5, 5);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillGradientRadial(
        types.Rect.init(0, 0, 5, 5),
        2,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    // Centro: dist ~0 → preto.
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(2, 2));
    // Borda do rect: dist >= 2 → branco saturado.
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb.get(0, 2));
    // Ponto intermediário: dist ~1.41 → t ~0.707 → ~180.
    const mid = fb.get(1, 2);
    try stdt.testing.expect(mid[0] > 120 and mid[0] < 220);

    // Raio 0 → color0 sólido em todo o rect.
    var fb2 = try SoftwareFramebuffer.init(gpa, 3, 3);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(255, 255, 255));
    fb2.fillGradientRadial(
        types.Rect.init(0, 0, 3, 3),
        0,
        types.Color.rgb(10, 20, 30),
        types.Color.rgb(200, 200, 200),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 10, 20, 30, 255 }, fb2.get(1, 1));

    // Entradas não-finitas saturam em no-op (framebuffer intacto).
    var fb3 = try SoftwareFramebuffer.init(gpa, 2, 2);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(7, 8, 9));
    fb3.fillGradientRadial(
        types.Rect.init(0, 0, 2, 2),
        std.math.nan(f32),
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 7, 8, 9, 255 }, fb3.get(0, 0));
}

test "raster contorno de círculo e tracejado" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Anel: centro vazado, borda pintada (espessura 3 → banda sólida
    // entre r-1.5 e r+1.5).
    var fb = try SoftwareFramebuffer.init(gpa, 9, 9);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.strokeCircle(types.Vec2.init(4, 4), 3, 3, null, types.Color.rgb(255, 255, 255));
    // Centro (4,4) não é pintado (dist 0 < inner 1.5).
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(4, 4));
    // Borda (4,1): dist ~2.55 → dentro da banda sólida.
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb.get(4, 1));

    // Espessura 0 é no-op.
    var fb2 = try SoftwareFramebuffer.init(gpa, 4, 4);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.strokeCircle(types.Vec2.init(2, 2), 1, 0, null, types.Color.rgb(255, 255, 255));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb2.get(2, 0));

    // Tracejado: pinta algum pixel do anel e deixa outro vazado.
    var fb3 = try SoftwareFramebuffer.init(gpa, 21, 21);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.strokeCircleDashed(types.Vec2.init(10, 10), 8, 1, 2, 4, null, types.Color.rgb(255, 255, 255));
    var painted: usize = 0;
    var y: usize = 0;
    while (y < 21) : (y += 1) {
        var x: usize = 0;
        while (x < 21) : (x += 1) {
            if (fb3.get(@intCast(x), @intCast(y))[0] > 0) painted += 1;
        }
    }
    try stdt.testing.expect(painted > 0);
    try stdt.testing.expect(painted < 21 * 21); // não preenche tudo

    // dash_len 0 é no-op.
    var fb4 = try SoftwareFramebuffer.init(gpa, 6, 6);
    defer fb4.deinit(gpa);
    fb4.clear(types.Color.rgb(0, 0, 0));
    fb4.strokeCircleDashed(types.Vec2.init(3, 3), 2, 1, 0, 1, null, types.Color.rgb(255, 255, 255));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb4.get(3, 1));
}

test "raster gradiente cônico: ângulo inicial e sweep" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // 5x5, centro (2,2): ângulo 0 = +X (direita), sweep 2π.
    var fb = try SoftwareFramebuffer.init(gpa, 5, 5);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.fillGradientConic(
        types.Rect.init(0, 0, 5, 5),
        types.Vec2.init(2, 2),
        0,
        2 * std.math.pi,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    // Centro exato do gradiente (2,2) → ângulo indefinido; usa o
    // fallback t=0 (color0).
    // Pixel à direita (4,2): centro do pixel em (4.5,2.5) → ângulo
    // ~0.197 rad → t ~0.031 → valor baixo (~8).
    const right = fb.get(4, 2);
    try stdt.testing.expect(right[0] < 20);
    // Pixel acima (2,4): ângulo ~1.373 rad → t ~0.219 → ~56.
    const up = fb.get(2, 4);
    try stdt.testing.expect(up[0] > 40 and up[0] < 90);

    // Sweep zero → color0 sólido.
    var fb2 = try SoftwareFramebuffer.init(gpa, 3, 3);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(255, 255, 255));
    fb2.fillGradientConic(
        types.Rect.init(0, 0, 3, 3),
        types.Vec2.init(1, 1),
        0,
        0,
        types.Color.rgb(10, 20, 30),
        types.Color.rgb(200, 200, 200),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 10, 20, 30, 255 }, fb2.get(2, 0));

    // Entradas não-finitas saturam em no-op.
    var fb3 = try SoftwareFramebuffer.init(gpa, 2, 2);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(7, 8, 9));
    fb3.fillGradientConic(
        types.Rect.init(0, 0, 2, 2),
        types.Vec2.init(1, 1),
        std.math.nan(f32),
        1,
        types.Color.rgb(0, 0, 0),
        types.Color.rgb(255, 255, 255),
        null,
    );
    try stdt.testing.expectEqual([4]u8{ 7, 8, 9, 255 }, fb3.get(0, 0));
}

test "raster linha tracejada: alternância e no-op" {
    const stdt = @import("std");
    const gpa = stdt.testing.allocator;

    // Reta horizontal 0..8, dash 2, gap 2: pixels em x=0,1 (dash),
    // x=2,3 (gap), x=4,5 (dash)...
    var fb = try SoftwareFramebuffer.init(gpa, 8, 1);
    defer fb.deinit(gpa);
    fb.clear(types.Color.rgb(0, 0, 0));
    fb.strokeLineDashed(
        types.Vec2.init(0, 0),
        types.Vec2.init(8, 0),
        1,
        2,
        2,
        null,
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb.get(0, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb.get(1, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(2, 0));
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb.get(3, 0));
    try stdt.testing.expectEqual([4]u8{ 255, 255, 255, 255 }, fb.get(4, 0));

    // dash_len 0 é no-op.
    var fb2 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb2.deinit(gpa);
    fb2.clear(types.Color.rgb(0, 0, 0));
    fb2.strokeLineDashed(
        types.Vec2.init(0, 0),
        types.Vec2.init(4, 0),
        1,
        0,
        2,
        null,
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb2.get(0, 0));

    // p0 == p1 (len 0) é no-op.
    var fb3 = try SoftwareFramebuffer.init(gpa, 4, 1);
    defer fb3.deinit(gpa);
    fb3.clear(types.Color.rgb(0, 0, 0));
    fb3.strokeLineDashed(
        types.Vec2.init(1, 0),
        types.Vec2.init(1, 0),
        1,
        2,
        2,
        null,
        types.Color.rgb(255, 255, 255),
    );
    try stdt.testing.expectEqual([4]u8{ 0, 0, 0, 255 }, fb3.get(1, 0));
}
